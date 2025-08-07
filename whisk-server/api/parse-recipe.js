export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { url } = req.body;
  
  if (!url) {
    return res.status(400).json({ error: 'URL is required' });
  }

  try {
    const result = await parseRecipe(url);
    res.json(result);
  } catch (error) {
    console.error('Error parsing recipe:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
}

async function parseRecipe(url) {
  console.log('Starting recipe parsing for URL:', url);
  
  // Fetch webpage content
  const htmlContent = await fetchWebpageContent(url);
  console.log('Fetched webpage content length:', htmlContent.length);
  
  // 1. FIRST PRIORITY: Try to extract structured data (JSON-LD)
  const structuredData = extractStructuredData(htmlContent);
  if (structuredData && structuredData.ingredients && structuredData.ingredients.length > 0) {
    console.log('✅ Found structured data with', structuredData.ingredients.length, 'ingredients');
    return {
      success: true,
      recipe: createRecipeFromStructuredData(structuredData, url),
      source: 'structured_data',
      metrics: {
        parsingTime: Date.now() - Date.now(), // Will be calculated properly
        ingredientsFound: structuredData.ingredients.length,
        confidence: 'high'
      }
    };
  } else {
    console.log('❌ No structured data found or no ingredients in structured data');
  }
  
  // 2. SECOND PRIORITY: Extract ingredients from HTML
  const extractedIngredients = extractIngredientsFromHTML(htmlContent);
  console.log('Extracted ingredients count:', extractedIngredients.length);
  
  if (extractedIngredients.length === 0) {
    console.log('❌ No ingredients extracted from HTML, trying fallback extraction...');
    // Try a more aggressive extraction
    const fallbackIngredients = extractIngredientsFallback(cleanTextContent);
    console.log('Fallback extracted ingredients count:', fallbackIngredients.length);
    if (fallbackIngredients.length > 0) {
      extractedIngredients.push(...fallbackIngredients);
    }
  }
  
  // 3. Extract recipe title from HTML
  const cleanTextContent = extractCleanText(htmlContent);
  const recipeTitle = extractRecipeTitle(cleanTextContent);
  console.log('Extracted recipe title:', recipeTitle || 'Not found');
  
  // 4. Create prompt for LLM
  const prompt = createLLMPrompt(extractedIngredients, recipeTitle);
  console.log('Created prompt length:', prompt.length);
  
  // Estimate token usage and truncate if necessary
  const estimatedTokens = estimateTokenCount(prompt);
  console.log('📊 Estimated tokens:', estimatedTokens);
  
  let finalPrompt = prompt;
  let finalIngredients = extractedIngredients;
  
  if (estimatedTokens > 3000) {
    console.log('⚠️ Prompt too long, truncating ingredients...');
    finalIngredients = extractedIngredients.slice(0, Math.floor(extractedIngredients.length * 0.7));
    finalPrompt = createLLMPrompt(finalIngredients, recipeTitle);
    console.log('📊 Truncated prompt tokens:', estimateTokenCount(finalPrompt));
  }
  
  // 5. Call OpenAI API
  let parsedRecipe;
  let source = 'llm_parsing';
  let metrics = {};
  
  try {
    const llmResponse = await callOpenAI(finalPrompt);
    console.log('Received LLM response length:', llmResponse.length);
    
    // 6. Parse LLM response
    parsedRecipe = parseLLMResponse(llmResponse, url);
    console.log('Parsed recipe ingredients count:', parsedRecipe.ingredients.length);
    
    metrics = {
      parsingTime: Date.now() - Date.now(), // Will be calculated properly
      ingredientsFound: parsedRecipe.ingredients.length,
      confidence: 'medium',
      tokensUsed: estimatedTokens
    };
  } catch (error) {
    console.log('❌ LLM parsing failed, falling back to regex parsing:', error.message);
    
    // 6b. Fallback to regex-based parsing
    parsedRecipe = parseWithRegex(finalIngredients, recipeTitle, url);
    source = 'regex_fallback';
    console.log('📋 Regex fallback parsed', parsedRecipe.ingredients.length, 'ingredients');
    
    metrics = {
      parsingTime: Date.now() - Date.now(), // Will be calculated properly
      ingredientsFound: parsedRecipe.ingredients.length,
      confidence: 'low',
      fallbackUsed: true
    };
  }
  
  return {
    success: true,
    recipe: parsedRecipe,
    source: source,
    metrics: metrics
  };
}

async function fetchWebpageContent(url) {
  console.log('🔗 Fetching webpage from:', url);
  
  const response = await fetch(url);
  
  if (!response.ok) {
    throw new Error(`HTTP Error: ${response.status}`);
  }
  
  const htmlString = await response.text();
  console.log('📄 Raw HTML length:', htmlString.length);
  console.log('📄 First 500 chars:', htmlString.substring(0, 500));
  
  return htmlString; // Return raw HTML for proper parsing
}

// Helper function to extract clean text from HTML
function extractCleanText(htmlString) {
  return htmlString
    .replace(/<[^>]+>/g, ' ') // Replace tags with spaces instead of removing
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&rsquo;/g, "'")
    .replace(/&lsquo;/g, "'")
    .replace(/&mdash;/g, "—")
    .replace(/&ndash;/g, "–")
    .replace(/\s+/g, ' '); // Normalize whitespace
}

function extractIngredientsFromHTML(htmlString) {
  const listPatterns = [
    /<ul[^>]*>(.*?)<\/ul>/gs,
    /<ol[^>]*>(.*?)<\/ol>/gs
  ];
  
  let extractedIngredients = [];
  
  for (const pattern of listPatterns) {
    const matches = htmlString.match(pattern);
    
    if (matches) {
      for (const match of matches) {
        const listContent = match;
        
        // Extract individual list items
        const itemPattern = /<li[^>]*>(.*?)<\/li>/gs;
        const itemMatches = listContent.match(itemPattern);
        
        if (itemMatches) {
          let allItems = [];
          let hasMeasurement = false;
          
          for (const itemMatch of itemMatches) {
            const itemContent = itemMatch.replace(/<[^>]*>/g, '').trim();
            allItems.push(itemContent);
            
            // Check if this item has measurement keywords
            const measurementKeywords = [
              'cup', 'cups', 'tablespoon', 'tablespoons', 'teaspoon', 'teaspoons',
              'ounce', 'ounces', 'pound', 'pounds', 'gram', 'grams', 'kilogram', 'kilograms',
              'ml', 'milliliter', 'milliliters', 'l', 'liter', 'liters',
              'small', 'medium', 'large', 'clove', 'cloves', 'bunch', 'bunches',
              'can', 'cans', 'package', 'packages', 'jar', 'jars', 'bottle', 'bottles'
            ];
            
            if (measurementKeywords.some(keyword => 
              itemContent.toLowerCase().includes(keyword))) {
              hasMeasurement = true;
            }
          }
          
          // If the list has measurements, include all items
          if (hasMeasurement) {
            for (const item of allItems) {
              if (item.trim()) {
                extractedIngredients.push(item.trim());
                console.log('📋 Found ingredient in validated list:', item.trim());
              }
            }
          }
        }
      }
    }
  }
  
  return extractedIngredients;
}

// NEW: More aggressive fallback ingredient extraction
function extractIngredientsFallback(htmlString) {
  console.log('🔍 Trying fallback ingredient extraction...');
  
  const fallbackIngredients = [];
  
  // Look for any text that contains measurement patterns
  const measurementPattern = /(\d+(?:\/\d+)?(?:\s+\d+\/\d+)?)\s+(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons|ounce|ounces|pound|pounds|gram|grams|ml|l|g|kg|oz|lb|tbsp|tsp)\s+([^<>\n]+)/gi;
  
  let match;
  while ((match = measurementPattern.exec(htmlString)) !== null) {
    const fullMatch = match[0];
    console.log('🔍 Found measurement pattern:', fullMatch);
    fallbackIngredients.push(fullMatch.trim());
  }
  
  // Also look for common ingredient keywords
  const ingredientKeywords = [
    'asparagus', 'miso', 'bearnaise', 'sauce', 'butter', 'garlic', 'lemon', 'salt', 'pepper',
    'flour', 'sugar', 'oil', 'vinegar', 'herbs', 'spices', 'vegetables', 'meat', 'fish'
  ];
  
  for (const keyword of ingredientKeywords) {
    const keywordPattern = new RegExp(`([^<>\n]*${keyword}[^<>\n]*)`, 'gi');
    let keywordMatch;
    while ((keywordMatch = keywordPattern.exec(htmlString)) !== null) {
      const text = keywordMatch[1].trim();
      if (text.length > 5 && text.length < 200) {
        console.log('🔍 Found ingredient keyword:', text);
        fallbackIngredients.push(text);
      }
    }
  }
  
  // Remove duplicates
  const uniqueIngredients = [...new Set(fallbackIngredients)];
  console.log('🔍 Fallback extraction found', uniqueIngredients.length, 'unique ingredients');
  
  return uniqueIngredients;
}

function extractRecipeTitle(htmlString) {
  // 1. Try to extract from JSON-LD structured data first
  const jsonLdPattern = /<script type="application\/ld\+json">(.*?)<\/script>/gs;
  const matches = htmlString.match(jsonLdPattern);
  
  if (matches) {
    for (const match of matches) {
      try {
        const jsonContent = match.replace(/<script type="application\/ld\+json">/, '').replace(/<\/script>/, '');
        const parsed = JSON.parse(jsonContent);
        
        if (parsed['@type'] === 'Recipe' && (parsed.name || parsed.title)) {
          const title = parsed.name || parsed.title;
          console.log('📝 Found recipe title from JSON-LD:', title);
          return cleanRecipeTitle(title);
        }
      } catch (error) {
        continue;
      }
    }
  }
  
  // 2. Try to extract from title tag
  const titleMatch = htmlString.match(/<title[^>]*>(.*?)<\/title>/i);
  if (titleMatch) {
    let recipeTitle = titleMatch[1].trim();
    console.log('📝 Found recipe title from <title>:', recipeTitle);
    return cleanRecipeTitle(recipeTitle);
  }
  
  // 3. Try to extract from h1 tags
  const h1Match = htmlString.match(/<h1[^>]*>(.*?)<\/h1>/i);
  if (h1Match) {
    let recipeTitle = h1Match[1].trim();
    console.log('📝 Found recipe title from <h1>:', recipeTitle);
    return cleanRecipeTitle(recipeTitle);
  }
  
  // 4. Try to extract from meta tags
  const metaTitleMatch = htmlString.match(/<meta[^>]*property="og:title"[^>]*content="([^"]*)"[^>]*>/i);
  if (metaTitleMatch) {
    let recipeTitle = metaTitleMatch[1].trim();
    console.log('📝 Found recipe title from og:title:', recipeTitle);
    return cleanRecipeTitle(recipeTitle);
  }
  
  return null;
}

function cleanRecipeTitle(title) {
  let cleaned = title
    .replace(/\s*-\s*.*$/, '') // Remove everything after dash
    .replace(/\s*\|\s*.*$/, '') // Remove everything after pipe
    .replace(/\s*Recipe\s*$/i, '') // Remove "Recipe" suffix
    .replace(/\s*Recipes?\s*$/i, '') // Remove "Recipes" suffix
    .replace(/\s*How to Make\s*/i, '') // Remove "How to Make"
    .replace(/\s*Easy\s*/i, '') // Remove "Easy"
    .replace(/\s*Best\s*/i, '') // Remove "Best"
    .replace(/\s*Delicious\s*/i, '') // Remove "Delicious"
    .replace(/\s*Homemade\s*/i, '') // Remove "Homemade"
    .trim();
  
  console.log('📝 Cleaned recipe title:', cleaned);
  return cleaned;
}

function createLLMPrompt(ingredients, recipeTitle) {
  const recipeName = recipeTitle || "Recipe Name";
  
  const prompt = `Parse ingredients into {"ingredients":[{"name":X,"amount":Y,"unit":Z,"category":C}]}

IMPORTANT: Only parse ingredients that are actually listed in the provided content. Do not add ingredients that are not present.

Rules:
1. name: Remove prep words, keep essential descriptors
2. amount: Convert ALL fractions to decimals (default to 1 if no amount)
3. unit: Standardize to full words (default to "piece" if no unit)
4. category: Must be one of [Produce, Meat & Seafood, Deli, Bakery, Frozen, Pantry, Dairy, Beverages]
5. ONLY include ingredients that are explicitly listed in the content

Examples showing exact expected output:
"2 1/2 tbsp finely chopped fresh basil"
{"name":"basil","amount":2.5,"unit":"tablespoons","category":"Produce"}

"1 (14.5 oz) can diced tomatoes, drained"
{"name":"tomatoes","amount":14.5,"unit":"ounces","category":"Pantry"}

"3 large cloves garlic, minced"
{"name":"garlic","amount":3,"unit":"large cloves","category":"Produce"}

"1 lb medium shrimp (31-40 count), peeled and deveined"
{"name":"shrimp","amount":1,"unit":"pound","category":"Meat & Seafood"}

"crispy shallots"
{"name":"crispy shallots","amount":1,"unit":"piece","category":"Produce"}

"1/2 cup dry white wine"
{"name":"white wine","amount":0.5,"unit":"cup","category":"Beverages"}

"1/4 cup fresh lemon juice"
{"name":"lemon juice","amount":0.25,"unit":"cup","category":"Produce"}

Now parse ONLY the ingredients listed in this content:
${ingredients.join('\n')}

Respond ONLY with a JSON object. Do not include markdown, explanation, or formatting.`;

  return prompt;
}

async function callOpenAI(prompt) {
  const apiKey = process.env.OPENAI_API_KEY;
  
  if (!apiKey) {
    throw new Error('OpenAI API key not found in environment variables');
  }
  
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'user',
          content: prompt
        }
      ],
      max_tokens: 2000,
      temperature: 0.1
    })
  });
  
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error: ${response.status} - ${errorText}`);
  }
  
  const data = await response.json();
  console.log('API Response Status:', response.status);
  console.log('API Response:', JSON.stringify(data));
  
  return data.choices[0].message.content;
}

function parseLLMResponse(response, originalURL) {
  // Extract JSON from the response
  let jsonString = response;
  
  // Remove markdown code blocks if present
  if (jsonString.includes('```json')) {
    const startIndex = jsonString.indexOf('```json') + 7;
    const endIndex = jsonString.lastIndexOf('```');
    jsonString = jsonString.substring(startIndex, endIndex);
    console.log('Extracted from ```json blocks');
  } else if (jsonString.includes('```')) {
    const startIndex = jsonString.indexOf('```') + 3;
    const endIndex = jsonString.lastIndexOf('```');
    jsonString = jsonString.substring(startIndex, endIndex);
    console.log('Extracted from ``` blocks');
  }
  
  // Parse the JSON
  const parsed = JSON.parse(jsonString);
  
  // Convert to Recipe format
  const recipe = {
    url: originalURL,
    name: parsed.recipeName,
    ingredients: parsed.ingredients.map(ing => ({
      name: ing.name,
      amount: ing.amount,
      unit: ing.unit,
      category: ing.category,
      isChecked: false,
      isRemoved: false
    })),
    isParsed: true
  };
  
  return recipe;
} 

// NEW: Extract structured data (JSON-LD) from HTML
function extractStructuredData(htmlString) {
  console.log('🔍 Looking for structured data (JSON-LD)');
  
  // Look for JSON-LD script tags
  const jsonLdPattern = /<script type="application\/ld\+json">(.*?)<\/script>/gs;
  const matches = htmlString.match(jsonLdPattern);
  
  if (matches) {
    for (const match of matches) {
      try {
        // Extract the JSON content
        const jsonContent = match.replace(/<script type="application\/ld\+json">/, '').replace(/<\/script>/, '');
        const parsed = JSON.parse(jsonContent);
        
        console.log('🔍 Found JSON-LD data:', JSON.stringify(parsed).substring(0, 200) + '...');
        
        // Check if this contains recipe data
        if (parsed['@type'] === 'Recipe' || parsed.recipeIngredient || parsed.ingredients) {
          console.log('✅ Found recipe structured data');
          return parsed;
        }
      } catch (error) {
        console.log('❌ Failed to parse JSON-LD:', error.message);
        continue;
      }
    }
  }
  
  return null;
}

// NEW: Create recipe from structured data
function createRecipeFromStructuredData(structuredData, url) {
  const recipe = {
    url: url,
    name: structuredData.name || structuredData.title || "Recipe",
    ingredients: [],
    isParsed: true
  };
  
  // Extract ingredients from structured data
  const ingredients = structuredData.recipeIngredient || structuredData.ingredients || [];
  
  for (const ingredient of ingredients) {
    if (typeof ingredient === 'string') {
      // Parse ingredient string (e.g., "2 cups flour")
      const parsed = parseIngredientString(ingredient);
      if (parsed) {
        recipe.ingredients.push(parsed);
      }
    } else if (typeof ingredient === 'object') {
      // Already structured ingredient object
      recipe.ingredients.push({
        name: ingredient.name || ingredient.text || '',
        amount: ingredient.amount || 1,
        unit: ingredient.unit || 'piece',
        category: ingredient.category || 'Pantry',
        isChecked: false,
        isRemoved: false
      });
    }
  }
  
  console.log('📋 Created recipe from structured data with', recipe.ingredients.length, 'ingredients');
  return recipe;
}

// NEW: Parse ingredient string into structured format
function parseIngredientString(ingredientString) {
  // Simple regex-based parsing as fallback
  const patterns = [
    // "2 cups flour" -> {amount: 2, unit: "cups", name: "flour"}
    /^(\d+(?:\/\d+)?(?:\s+\d+\/\d+)?)\s+(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons|ounce|ounces|pound|pounds|gram|grams|ml|l|g|kg|oz|lb|tbsp|tsp)\s+(.+)$/i,
    // "2 large eggs" -> {amount: 2, unit: "large", name: "eggs"}
    /^(\d+)\s+(small|medium|large|extra large)\s+(.+)$/i,
    // "3 cloves garlic" -> {amount: 3, unit: "cloves", name: "garlic"}
    /^(\d+)\s+(clove|cloves|slice|slices|piece|pieces)\s+(.+)$/i,
    // "1/2 cup olive oil" -> {amount: 0.5, unit: "cup", name: "olive oil"}
    /^(\d+\/\d+)\s+(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons)\s+(.+)$/i
  ];
  
  for (const pattern of patterns) {
    const match = ingredientString.match(pattern);
    if (match) {
      let amount = parseFloat(match[1]);
      
      // Handle fractions
      if (match[1].includes('/')) {
        const [num, denom] = match[1].split('/');
        amount = parseFloat(num) / parseFloat(denom);
      }
      
      return {
        name: match[match.length - 1].trim(),
        amount: amount,
        unit: match[2],
        category: categorizeIngredient(match[match.length - 1].trim()),
        isChecked: false,
        isRemoved: false
      };
    }
  }
  
  // Fallback: treat as single ingredient
  return {
    name: ingredientString.trim(),
    amount: 1,
    unit: 'piece',
    category: categorizeIngredient(ingredientString.trim()),
    isChecked: false,
    isRemoved: false
  };
}

// NEW: Categorize ingredient based on name
function categorizeIngredient(name) {
  const lowerName = name.toLowerCase();
  
  const categories = {
    'Produce': ['tomato', 'onion', 'garlic', 'lettuce', 'carrot', 'pepper', 'cucumber', 'basil', 'herb', 'vegetable', 'fruit', 'lemon', 'lime', 'orange', 'apple', 'banana', 'berry'],
    'Meat & Seafood': ['chicken', 'beef', 'pork', 'fish', 'salmon', 'shrimp', 'meat', 'steak', 'turkey', 'lamb', 'seafood', 'tuna', 'cod', 'sausage'],
    'Deli': ['ham', 'salami', 'prosciutto', 'deli', 'cold cut'],
    'Bakery': ['bread', 'roll', 'bun', 'bagel', 'muffin', 'cake', 'pastry'],
    'Frozen': ['frozen', 'ice cream', 'ice'],
    'Pantry': ['flour', 'sugar', 'salt', 'spice', 'oil', 'sauce', 'pasta', 'rice', 'bean', 'canned', 'dry', 'dried'],
    'Dairy': ['milk', 'cream', 'yogurt', 'butter', 'mozzarella', 'cheese', 'egg'],
    'Beverages': ['water', 'juice', 'soda', 'drink', 'beverage', 'wine', 'beer', 'liquor']
  };
  
  for (const [category, keywords] of Object.entries(categories)) {
    for (const keyword of keywords) {
      if (lowerName.includes(keyword)) {
        return category;
      }
    }
  }
  
  return 'Pantry'; // Default category
}

// NEW: Regex-based ingredient parsing fallback
function parseWithRegex(ingredients, recipeTitle, url) {
  console.log('🔧 Using regex fallback parsing for', ingredients.length, 'ingredients');
  
  const recipe = {
    url: url,
    name: recipeTitle || "Recipe",
    ingredients: [],
    isParsed: true
  };
  
  // Enhanced regex patterns for ingredient parsing
  const patterns = [
    // "2 1/2 cups flour" -> {amount: 2.5, unit: "cups", name: "flour"}
    {
      regex: /^(\d+(?:\/\d+)?(?:\s+\d+\/\d+)?)\s+(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons|ounce|ounces|pound|pounds|gram|grams|ml|l|g|kg|oz|lb|tbsp|tsp)\s+(.+)$/i,
      extract: (match) => ({
        amount: parseFraction(match[1]),
        unit: standardizeUnit(match[2]),
        name: cleanIngredientName(match[3])
      })
    },
    // "2 large eggs" -> {amount: 2, unit: "large", name: "eggs"}
    {
      regex: /^(\d+)\s+(small|medium|large|extra large)\s+(.+)$/i,
      extract: (match) => ({
        amount: parseFloat(match[1]),
        unit: match[2],
        name: cleanIngredientName(match[3])
      })
    },
    // "3 cloves garlic" -> {amount: 3, unit: "cloves", name: "garlic"}
    {
      regex: /^(\d+)\s+(clove|cloves|slice|slices|piece|pieces|can|cans|jar|jars|bottle|bottles|package|packages|bag|bags|bunch|bunches|head|heads)\s+(.+)$/i,
      extract: (match) => ({
        amount: parseFloat(match[1]),
        unit: match[2],
        name: cleanIngredientName(match[3])
      })
    },
    // "1/2 cup olive oil" -> {amount: 0.5, unit: "cup", name: "olive oil"}
    {
      regex: /^(\d+\/\d+)\s+(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons)\s+(.+)$/i,
      extract: (match) => ({
        amount: parseFraction(match[1]),
        unit: standardizeUnit(match[2]),
        name: cleanIngredientName(match[3])
      })
    },
    // "1 (14.5 oz) can diced tomatoes" -> {amount: 14.5, unit: "ounces", name: "tomatoes"}
    {
      regex: /^(\d+)\s*\((\d+(?:\.\d+)?)\s*(oz|ounce|ounces|lb|pound|pounds)\)\s+(.+)$/i,
      extract: (match) => ({
        amount: parseFloat(match[2]),
        unit: standardizeUnit(match[3]),
        name: cleanIngredientName(match[4])
      })
    },
    // "crispy shallots" -> {amount: 1, unit: "piece", name: "crispy shallots"}
    {
      regex: /^(.+)$/i,
      extract: (match) => ({
        amount: 1,
        unit: "piece",
        name: cleanIngredientName(match[1])
      })
    }
  ];
  
  for (const ingredient of ingredients) {
    let parsed = null;
    
    // Try each pattern
    for (const pattern of patterns) {
      const match = ingredient.match(pattern.regex);
      if (match) {
        parsed = pattern.extract(match);
        break;
      }
    }
    
    if (parsed) {
      recipe.ingredients.push({
        name: parsed.name,
        amount: parsed.amount,
        unit: parsed.unit,
        category: categorizeIngredient(parsed.name),
        isChecked: false,
        isRemoved: false
      });
    }
  }
  
  console.log('✅ Regex parsing completed with', recipe.ingredients.length, 'ingredients');
  return recipe;
}

// Helper functions for regex parsing
function parseFraction(fractionStr) {
  if (fractionStr.includes('/')) {
    const parts = fractionStr.split(/\s+/);
    let total = 0;
    
    for (const part of parts) {
      if (part.includes('/')) {
        const [num, denom] = part.split('/');
        total += parseFloat(num) / parseFloat(denom);
      } else {
        total += parseFloat(part);
      }
    }
    
    return Math.round(total * 100) / 100; // Round to 2 decimal places
  }
  
  return parseFloat(fractionStr);
}

function standardizeUnit(unit) {
  const unitMap = {
    'tbsp': 'tablespoons',
    'tbs': 'tablespoons',
    'tsp': 'teaspoons',
    'oz': 'ounces',
    'lb': 'pounds',
    'lbs': 'pounds',
    'g': 'grams',
    'kg': 'kilograms',
    'ml': 'milliliters',
    'l': 'liters',
    'c': 'cups',
    'pt': 'pints',
    'qt': 'quarts',
    'gal': 'gallons'
  };
  
  const lowerUnit = unit.toLowerCase();
  return unitMap[lowerUnit] || unit;
}

function cleanIngredientName(name) {
  // Remove common preparation words
  const prepWords = [
    'fresh', 'diced', 'chopped', 'minced', 'sliced', 'grated', 'shredded',
    'peeled', 'seeded', 'cored', 'trimmed', 'drained', 'rinsed', 'washed',
    'finely', 'coarsely', 'thinly', 'roughly', 'rough', 'fine', 'coarse',
    'whole', 'raw', 'cooked', 'roasted', 'toasted', 'crispy', 'softened',
    'melted', 'thawed', 'defrosted', 'divided', 'separated', 'reserved'
  ];
  
  let cleaned = name.trim();
  
  // Remove preparation words from the beginning
  for (const word of prepWords) {
    const pattern = new RegExp(`^\\s*${word}\\s+`, 'i');
    cleaned = cleaned.replace(pattern, '');
  }
  
  // Remove preparation words from the end
  for (const word of prepWords) {
    const pattern = new RegExp(`\\s+${word}\\s*$`, 'i');
    cleaned = cleaned.replace(pattern, '');
  }
  
  return cleaned.trim() || name.trim();
}

// NEW: Token usage estimation
function estimateTokenCount(text) {
  // Rough estimation: 1 token ≈ 4 characters for English text
  // This is a conservative estimate for GPT models
  const charCount = text.length;
  const estimatedTokens = Math.ceil(charCount / 4);
  
  // Add some buffer for special tokens and formatting
  return estimatedTokens + 50;
} 
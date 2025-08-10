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
  
  // Extract ingredients from HTML
  const extractedIngredients = extractIngredientsFromHTML(htmlContent);
  console.log('Extracted ingredients count:', extractedIngredients.length);
  
  // Extract recipe title from HTML
  const recipeTitle = extractRecipeTitle(htmlContent);
  console.log('Extracted recipe title:', recipeTitle || 'Not found');
  
  // Create prompt for LLM
  const prompt = createLLMPrompt(extractedIngredients, recipeTitle);
  console.log('Created prompt length:', prompt.length);
  
  // Call OpenAI API
  const llmResponse = await callOpenAI(prompt);
  console.log('Received LLM response length:', llmResponse.length);
  
  // Parse LLM response
  const parsedRecipe = parseLLMResponse(llmResponse, url);
  console.log('Parsed recipe ingredients count:', parsedRecipe.ingredients.length);
  
  return {
    success: true,
    recipe: parsedRecipe
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
  
  // Enhanced approach: Extract text while preserving ingredient information
  let textContent = htmlString
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
  
  return textContent;
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

function extractRecipeTitle(htmlString) {
  // Try to extract from title tag
  const titleMatch = htmlString.match(/<title[^>]*>(.*?)<\/title>/i);
  if (titleMatch) {
    let recipeTitle = titleMatch[1].trim();
    console.log('📝 Found recipe title from <title>:', recipeTitle);
    
    // Clean up the title
    recipeTitle = recipeTitle
      .replace(/\s*-\s*.*$/, '') // Remove everything after dash
      .replace(/\s*\|\s*.*$/, '') // Remove everything after pipe
      .replace(/\s*Recipe\s*$/i, '') // Remove "Recipe" suffix
      .replace(/\s*Recipes?\s*$/i, '') // Remove "Recipes" suffix
      .trim();
    
    console.log('📝 Cleaned recipe title:', recipeTitle);
    return recipeTitle;
  }
  
  // Try to extract from h1 tags
  const h1Match = htmlString.match(/<h1[^>]*>(.*?)<\/h1>/i);
  if (h1Match) {
    let recipeTitle = h1Match[1].trim();
    console.log('📝 Found recipe title from <h1>:', recipeTitle);
    
    // Clean up the title
    recipeTitle = recipeTitle
      .replace(/\s*-\s*.*$/, '') // Remove everything after dash
      .replace(/\s*\|\s*.*$/, '') // Remove everything after pipe
      .replace(/\s*Recipe\s*$/i, '') // Remove "Recipe" suffix
      .replace(/\s*Recipes?\s*$/i, '') // Remove "Recipes" suffix
      .trim();
    
    console.log('📝 Cleaned recipe title:', recipeTitle);
    return recipeTitle;
  }
  
  return null;
}

function createLLMPrompt(ingredients, recipeTitle) {
  const recipeName = recipeTitle || "Recipe Name";
  
  const prompt = `You are a recipe ingredient parser. Extract and standardize ingredients from the following list for the recipe: "${recipeName}".

Return ONLY a valid JSON object with this exact structure:

{
  "recipeName": "${recipeName}",
  "ingredients": [
    {
      "name": "ingredient name (cleaned)",
      "amount": number,
      "unit": "standardized unit",
      "category": "Produce|Pantry|Dairy|Meat & Seafood|Deli|Beverages"
    }
  ]
}

Rules:
- Convert all fractions to decimals (e.g., 1/2 → 0.5, 1 1/2 → 1.5)
- Standardize units: cups, tablespoons, teaspoons, ounces, pounds, grams, etc.
- Clean ingredient names by removing:
  - Preparation methods: "halved", "diced", "chopped", "finely chopped", "coarsely chopped", "roughly chopped", "thinly sliced", "finely sliced", "thickly sliced", "roughly diced", "finely diced", "minced", "grated", "shredded", "torn into small pieces", "cut into strips", "julienned", "zested", "torn", "cubed", "mashed", "pureed", "whipped", "beaten", "crushed"
  - Cooking states: "crispy", "toasted", "roasted", "grilled", "fried", "sautéed", "baked", "broiled", "steamed", "poached", "seared", "caramelized", "blanched", "boiled", "pickled", "smoked", "marinated", "candied", "melted", "softened", "thawed", "defrosted"
  - Processing: "peeled", "deveined", "tail-on", "pitted", "seeded", "cored", "trimmed", "stemmed", "skinned", "deboned", "boneless", "skinless", "filleted", "rinsed", "washed", "patted dry", "squeezed", "pressed", "drained"
  - State descriptors: "fresh", "raw", "uncooked", "cold", "warm", "hot", "divided", "separated", "reserved"
  - Size descriptors: "large", "medium", "small" (unless it's part of the ingredient name like "large eggs")
- Categorize ingredients appropriately
- Only include actual ingredients, not cooking instructions

Ingredients to parse:
${ingredients.join('\n')}

Return ONLY the JSON object, no other text.`;

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
  function sanitizeIngredientName(rawName) {
    if (!rawName || typeof rawName !== 'string') return rawName;
    let name = rawName;

    // Remove parenthetical descriptors that contain prep terms
    name = name.replace(/\((?:(?!\)).)*(?:chopped|sliced|diced|minced|grated|shredded|julienned|zested|torn|cubed|mashed|pureed|whipped|beaten|crushed)[^)]*\)/gi, '');

    // Remove trailing or inline descriptors like ", finely chopped" or "- coarsely chopped"
    name = name.replace(/(?:,|–|-)?\s*(?:finely|roughly|coarsely|thinly|thickly|lightly)?\s*(?:chopped|sliced|diced|minced|grated|shredded|torn|julienned|zested|cubed|mashed|pureed|whipped|beaten|crushed)\b/gi, '');

    // Remove phrases like "torn into small pieces" or "cut into strips"
    name = name.replace(/\b(?:torn into small pieces|cut into strips)\b/gi, '');

    // Remove leading descriptors like "finely chopped " at the start
    name = name.replace(/^(?:finely|roughly|coarsely|thinly|thickly|lightly)?\s*(?:chopped|sliced|diced|minced|grated|shredded|torn|julienned|zested|cubed|mashed|pureed|whipped|beaten|crushed)\s+/gi, '');

    // Cleanup: remove duplicate spaces and stray punctuation
    name = name.replace(/\s{2,}/g, ' ');
    name = name.replace(/\s*(?:,|;|:|-|–)\s*$/g, '');

    return name.trim();
  }
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
      name: sanitizeIngredientName(ing.name),
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
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
  
  // Extract recipe data from HTML
  const recipeData = extractRecipeData(htmlContent);
  console.log('Extracted ingredients count:', recipeData.ingredients.length);
  console.log('Extracted recipe title:', recipeData.title || 'Not found');
  
  // Create prompt for LLM
  const prompt = createLLMPrompt(recipeData.ingredients, recipeData.title);
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

function extractRecipeData(htmlString) {
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
  
  // Extract recipe title from various sources
  let recipeTitle = null;
  
  // Try to extract from title tag
  const titleMatch = htmlString.match(/<title[^>]*>(.*?)<\/title>/i);
  if (titleMatch) {
    recipeTitle = titleMatch[1].trim();
    console.log('📝 Found recipe title from <title>:', recipeTitle);
  }
  
  // Try to extract from h1 tags
  if (!recipeTitle) {
    const h1Match = htmlString.match(/<h1[^>]*>(.*?)<\/h1>/i);
    if (h1Match) {
      recipeTitle = h1Match[1].trim();
      console.log('📝 Found recipe title from <h1>:', recipeTitle);
    }
  }
  
  // Try to extract from h2 tags
  if (!recipeTitle) {
    const h2Match = htmlString.match(/<h2[^>]*>(.*?)<\/h2>/i);
    if (h2Match) {
      recipeTitle = h2Match[1].trim();
      console.log('📝 Found recipe title from <h2>:', recipeTitle);
    }
  }
  
  // Try to extract from meta tags
  if (!recipeTitle) {
    const metaMatch = htmlString.match(/<meta[^>]*property="og:title"[^>]*content="([^"]*)"[^>]*>/i);
    if (metaMatch) {
      recipeTitle = metaMatch[1].trim();
      console.log('📝 Found recipe title from og:title meta:', recipeTitle);
    }
  }
  
  // Clean up the title if found
  if (recipeTitle) {
    // Remove common suffixes
    recipeTitle = recipeTitle
      .replace(/\s*-\s*.*$/, '') // Remove everything after dash
      .replace(/\s*\|\s*.*$/, '') // Remove everything after pipe
      .replace(/\s*Recipe\s*$/i, '') // Remove "Recipe" suffix
      .replace(/\s*Recipes?\s*$/i, '') // Remove "Recipes" suffix
      .trim();
    
    console.log('📝 Cleaned recipe title:', recipeTitle);
  }
  
  return {
    ingredients: extractedIngredients,
    title: recipeTitle
  };
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
  - Preparation methods: "halved", "diced", "chopped", "finely chopped", "coarsely chopped", "thinly sliced", "minced", "grated", "shredded", "torn into small pieces", "cut into strips", "julienned", "zested", "torn", "cubed", "mashed", "pureed", "whipped", "beaten", "crushed", "ground"
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
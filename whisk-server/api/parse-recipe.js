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
  
  const prompt = `Parse ingredients into {"ingredients":[{"name":X,"amount":Y,"unit":Z,"category":C}]}

Rules:
1. name: The ingredient name should be what you would buy at the store (e.g., "black beans", "rosemary", "garlic cloves")
2. amount: Convert ALL fractions to decimals (default to 1 if no amount)
3. unit: PRESERVE the original quantity/unit from the recipe. Use singular form for 1, plural for >1. Only use weight measurements (ounces, pounds, grams) if that's what's explicitly stated in the recipe. For individual items, use "" (empty string) or omit unit entirely. NEVER use "pieces" as a unit - it's not a valid measurement.
4. category: Must be one of [Produce, Meat & Seafood, Deli, Bakery, Frozen, Pantry, Dairy, Beverages]
5. SKIP water ingredients - do not include them in the output
6. ALL vinegars (white wine vinegar, red wine vinegar, apple cider vinegar, etc.) should be categorized as "Pantry"
7. ALL wines (dry wine, rice wine, white wine, red wine, etc.) should be categorized as "Beverages"
8. Lemon juice and lime juice should be categorized as "Pantry" (not Beverages)
9. Banana pepper rings are jarred and should be categorized as "Pantry"

Examples showing exact expected output:
"3 small red bell peppers"
{"name":"red bell peppers","amount":3,"unit":"","category":"Produce"}

"1 large shallot"
{"name":"shallot","amount":1,"unit":"","category":"Produce"}

"5 medium cloves garlic"
{"name":"garlic cloves","amount":5,"unit":"","category":"Produce"}

"2 cups grape tomatoes"
{"name":"grape tomatoes","amount":2,"unit":"cups","category":"Produce"}

"1 cup olive oil"
{"name":"olive oil","amount":1,"unit":"cup","category":"Pantry"}

"1/2 cup olive oil"
{"name":"olive oil","amount":0.5,"unit":"cup","category":"Pantry"}

"1 pound shrimp"
{"name":"shrimp","amount":1,"unit":"pound","category":"Meat & Seafood"}

"2 pounds shrimp"
{"name":"shrimp","amount":2,"unit":"pounds","category":"Meat & Seafood"}

"1 tablespoon olive oil"
{"name":"olive oil","amount":1,"unit":"tablespoon","category":"Pantry"}

"2 tablespoons olive oil"
{"name":"olive oil","amount":2,"unit":"tablespoons","category":"Pantry"}

"1/4 cup white wine vinegar"
{"name":"white wine vinegar","amount":0.25,"unit":"cup","category":"Pantry"}

"1/2 cup red wine vinegar"
{"name":"red wine vinegar","amount":0.5,"unit":"cup","category":"Pantry"}

"1/4 cup white wine vinegar"
{"name":"white wine vinegar","amount":0.25,"unit":"cup","category":"Pantry"}

"1/2 cup dry wine"
{"name":"dry wine","amount":0.5,"unit":"cup","category":"Beverages"}

"1/4 cup rice wine"
{"name":"rice wine","amount":0.25,"unit":"cup","category":"Beverages"}

"1/4 cup lemon juice"
{"name":"lemon juice","amount":0.25,"unit":"cup","category":"Pantry"}

"2 tablespoons lime juice"
{"name":"lime juice","amount":2,"unit":"tablespoons","category":"Pantry"}

"1/2 cup banana pepper rings"
{"name":"banana pepper rings","amount":0.5,"unit":"cup","category":"Pantry"}

"2 ripe medium avocados"
{"name":"avocados","amount":2,"unit":"","category":"Produce"}

"8 thin tomato slices"
{"name":"tomatoes","amount":8,"unit":"","category":"Produce"}

"12 raw onion rings"
{"name":"onion","amount":12,"unit":"","category":"Produce"}

"4 cemita buns"
{"name":"cemita buns","amount":4,"unit":"","category":"Bakery"}

"3 sprigs tarragon"
{"name":"tarragon sprigs","amount":3,"unit":"","category":"Produce"}

"5 medium cloves garlic"
{"name":"garlic cloves","amount":5,"unit":"","category":"Produce"}

"2 ripe medium avocados"
{"name":"avocados","amount":2,"unit":"","category":"Produce"}

"8 thin tomato slices"
{"name":"tomatoes","amount":8,"unit":"","category":"Produce"}

"12 raw onion rings"
{"name":"onion","amount":12,"unit":"","category":"Produce"}

"2 celery stalks"
{"name":"celery stalks","amount":2,"unit":"","category":"Produce"}

"4 papaya leaves"
{"name":"papaya leaves","amount":4,"unit":"","category":"Produce"}

"1/2 cup mayonnaise"
{"name":"mayonnaise","amount":0.5,"unit":"cup","category":"Pantry"}

Now parse exactly as shown:
${ingredients.join('\n')}`;

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
export default async function handler(req, res) {
  const testHTML = `
    <html>
      <head>
        <title>Italian Pasta Salad Recipe</title>
      </head>
      <body>
        <h1>Italian Pasta Salad</h1>
        <ul>
          <li>1 onion</li>
          <li>3 cloves garlic</li>
          <li>1 bell pepper</li>
          <li>2 tomatoes</li>
        </ul>
      </body>
    </html>
  `;
  
  const recipeData = extractRecipeData(testHTML);
  
  res.json({
    ingredients: recipeData.ingredients,
    title: recipeData.title
  });
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
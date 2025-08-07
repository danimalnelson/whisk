export default async function handler(req, res) {
  const { url } = req.body;
  
  if (!url) {
    return res.status(400).json({ error: 'URL is required' });
  }
  
  try {
    console.log('🔗 Testing HTML fetch for:', url);
    
    const response = await fetch(url);
    console.log('📄 Response status:', response.status);
    console.log('📄 Response ok:', response.ok);
    
    if (!response.ok) {
      return res.json({ error: `HTTP Error: ${response.status}` });
    }
    
    const htmlString = await response.text();
    console.log('📄 HTML length:', htmlString.length);
    console.log('📄 First 1000 chars:', htmlString.substring(0, 1000));
    
    // Look for recipe-related content
    const hasRecipe = htmlString.toLowerCase().includes('recipe');
    const hasIngredients = htmlString.toLowerCase().includes('ingredient');
    const hasTitle = htmlString.includes('<title>');
    
    res.json({
      success: true,
      htmlLength: htmlString.length,
      hasRecipe,
      hasIngredients,
      hasTitle,
      first1000Chars: htmlString.substring(0, 1000)
    });
    
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message });
  }
} 
export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { prompt } = req.body;
  if (!prompt) {
    return res.status(400).json({ error: 'Prompt is required' });
  }

  const timings = {};
  const startTime = Date.now();

  try {
    // Time the API call
    const apiCallStartTime = Date.now();
    const response = await fetch('https://api.openai.com/v1/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: 'gpt-3.5-turbo-instruct',
        prompt: prompt,
        max_tokens: 2000,
        temperature: 0.0,
        presence_penalty: 0,
        frequency_penalty: 0,
        top_p: 1,
        stream: false
      })
    });
    timings.apiCall = Date.now() - apiCallStartTime;

    if (!response.ok) {
      const errorText = await response.text();
      console.error('❌ OpenAI API error:', response.status, errorText);
      throw new Error(`OpenAI API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    if (!data.choices?.[0]?.text) {
      throw new Error('Invalid response format from OpenAI API');
    }
    
    const content = data.choices[0].text;
    const totalTime = Date.now() - startTime;

    // Log only essential metrics
    console.log('=== OpenAI Performance ===');
    console.log(`⏱️ API call: ${timings.apiCall}ms`);
    console.log(`⏱️ Total time: ${totalTime}ms`);
    console.log(`📊 Tokens: ${data.usage?.total_tokens || 'N/A'}`);
    console.log('========================');
    
    res.json({
      success: true,
      content: content,
      metrics: {
        apiCallTime: timings.apiCall,
        totalTime: totalTime,
        tokens: data.usage?.total_tokens
      }
    });
  } catch (error) {
    console.error('❌ Error:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message
    });
  }
}
// Simple in-memory LRU cache for responses by prompt hash (best-effort on serverless)
const responseCache = new Map();
const MAX_CACHE_ENTRIES = 50;

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
    // Cache key based on prompt length and a simple hash
    const key = simpleHash(prompt);
    if (responseCache.has(key)) {
      const cached = responseCache.get(key);
      // Move to recent
      responseCache.delete(key);
      responseCache.set(key, cached);
      return res.json({ success: true, content: cached.content, metrics: { apiCallTime: 0, totalTime: Date.now() - startTime, tokens: cached.tokens || undefined, cached: true } });
    }

    // Time the API call
    const apiCallStartTime = Date.now();

    // Abort if slow (> 12s)
    const controller = new AbortController();
    const abortTimeout = setTimeout(() => controller.abort(), 12000);

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 900,
        temperature: 0.1,
        top_p: 1
      }),
      signal: controller.signal
    });
    clearTimeout(abortTimeout);
    timings.apiCall = Date.now() - apiCallStartTime;

    if (!response.ok) {
      const errorText = await response.text();
      console.error('❌ OpenAI API error:', response.status, errorText);
      throw new Error(`OpenAI API error: ${response.status} - ${errorText}`);
    }

    const data = await response.json();
    const content = data.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error('Invalid response format from OpenAI API');
    }
    const totalTime = Date.now() - startTime;

    // Log only essential metrics
    console.log('=== OpenAI Performance ===');
    console.log(`⏱️ API call: ${timings.apiCall}ms`);
    console.log(`⏱️ Total time: ${totalTime}ms`);
    console.log(`📊 Tokens: ${data.usage?.total_tokens || 'N/A'}`);
    console.log('========================');
    
    // Cache response (best effort LRU)
    try {
      responseCache.set(key, { content, tokens: data.usage?.total_tokens });
      if (responseCache.size > MAX_CACHE_ENTRIES) {
        const firstKey = responseCache.keys().next().value;
        responseCache.delete(firstKey);
      }
    } catch (_) {}

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

function simpleHash(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const chr = str.charCodeAt(i);
    hash = (hash << 5) - hash + chr;
    hash |= 0; // Convert to 32bit integer
  }
  return String(hash);
}
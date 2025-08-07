export default async function handler(req, res) {
  console.log('🔍 Debug endpoint called');
  console.log('🔍 Request method:', req.method);
  console.log('🔍 Request body:', req.body);
  
  res.json({
    message: 'Debug endpoint working',
    timestamp: new Date().toISOString(),
    requestMethod: req.method,
    requestBody: req.body
  });
} 
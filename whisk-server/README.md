# Whisk Server

This is the server component for the Whisk iOS app that handles recipe parsing securely.

## Setup

1. Install dependencies:
```bash
npm install
```

2. Deploy to Vercel:
```bash
npx vercel
```

3. Set environment variables in Vercel:
   - `OPENAI_API_KEY`: Your OpenAI API key

## API Endpoints

### POST /api/parse-recipe

Parses a recipe URL and extracts ingredients.

**Request:**
```json
{
  "url": "https://www.seriouseats.com/italian-pasta-salad-recipe-7486410"
}
```

**Response:**
```json
{
  "success": true,
  "recipe": {
    "name": "Italian Pasta Salad",
    "ingredients": [...]
  }
}
```

## Security

- API keys are stored securely on the server
- No sensitive data is exposed to the client
- Rate limiting and usage tracking can be added

## Development

Run locally:
```bash
npx vercel dev
``` 

## Static ingredient images

Serve images from `public/ingredients/` with filenames matching iOS slugs, e.g., `tarragon.webp`, `green-onion.webp`.

Headers for `/ingredients/*` are set in `vercel.json` to `Cache-Control: public, max-age=31536000, immutable`.

Recommended sizes: 60×90 (2x for 30×45 display) or 90×135 (@3x). Use WebP.
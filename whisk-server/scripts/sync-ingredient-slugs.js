/*
 Ensures that for each ingredient image in public/ingredients, a singular-slug alias also exists.
 This mirrors the iOS app's slugging behavior so newly added images work immediately.

 Rules implemented:
 - Lowercase, hyphenated slugs
 - Alias overrides (e.g., "red bell peppers" -> "red-bell-pepper")
 - Singularization: ies->y, es->(drop 2), s->(drop 1)
 - Special fix: asparagu -> asparagus

 Usage: node scripts/sync-ingredient-slugs.js
*/

const fs = require('fs');
const path = require('path');

const ING_DIR = path.join(__dirname, '..', 'public', 'ingredients');

/** Convert a hyphenated slug to a space-joined phrase for alias checks */
function toPhrase(slug) {
  return slug.replace(/-/g, ' ').toLowerCase();
}

/** Convert phrase back to slug */
function toSlug(phrase) {
  return phrase.trim().toLowerCase().replace(/\s+/g, '-');
}

/** Minimal singularization mirroring the app */
function singularize(word) {
  if (!word) return word;
  if (word.endsWith('ies')) return word.slice(0, -3) + 'y';
  if (word.endsWith('es')) return word.slice(0, -2);
  if (word.endsWith('s')) return word.slice(0, -1);
  return word;
}

/** Apply singularization to a multi-token phrase */
function singularizePhrase(phrase) {
  const tokens = phrase.split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return phrase;
  // Only singularize the last token to better preserve descriptors (matches app heuristics)
  const last = singularize(tokens[tokens.length - 1]);
  const rebuilt = [...tokens.slice(0, -1), last].join(' ');
  return rebuilt.replace('asparagu', 'asparagus');
}

// Aliases should be lowercase phrases
const aliasMap = {
  'bell peppers': 'bell-pepper',
  'red bell peppers': 'red-bell-pepper',
  'tomatoes': 'tomato',
  'grape tomatoes': 'grape-tomato',
  'shallots': 'shallot',
  'green onions': 'green-onion',
  'scallions': 'green-onion',
  'coriander': 'cilantro',
  'aubergine': 'eggplant'
};

function ensureSingularAliasForFile(fileName) {
  if (!fileName.endsWith('.webp')) return null;
  const srcPath = path.join(ING_DIR, fileName);
  if (!fs.existsSync(srcPath)) return null;

  const base = path.basename(fileName, '.webp').toLowerCase();
  const phrase = toPhrase(base);
  let targetSlug = null;

  if (aliasMap[phrase]) {
    targetSlug = aliasMap[phrase];
  } else {
    const singularPhrase = singularizePhrase(phrase);
    targetSlug = toSlug(singularPhrase);
  }

  if (!targetSlug || targetSlug === base) {
    return null; // No alias needed or already singular
  }

  const destName = `${targetSlug}.webp`;
  const destPath = path.join(ING_DIR, destName);
  if (fs.existsSync(destPath)) {
    return null; // Already present
  }

  fs.copyFileSync(srcPath, destPath);
  return destName;
}

function main() {
  if (!fs.existsSync(ING_DIR)) {
    console.error(`Ingredients directory not found: ${ING_DIR}`);
    process.exit(0);
  }

  const entries = fs.readdirSync(ING_DIR);
  const created = [];

  for (const entry of entries) {
    const alias = ensureSingularAliasForFile(entry);
    if (alias) created.push(alias);
  }

  if (created.length === 0) {
    console.log('No singular aliases needed.');
  } else {
    console.log(`Created ${created.length} singular alias file(s):`);
    for (const name of created) console.log(` - ${name}`);
  }
}

main();



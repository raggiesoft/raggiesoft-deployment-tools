#!/usr/bin/env node
/**
 * @license MIT
 * ============================================================================
 * validate-network-seo.mjs — Network-Wide SEO, Sitemap & Deep-Link Validator
 * ============================================================================
 * PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
 *   Why is the extension `.mjs` instead of `.js`?
 *   `.mjs` ("Modular JavaScript") tells Node.js to use modern **ES Modules**
 *   (`import ... from 'node:fs'`) instead of older CommonJS (`require('fs')`).
 *
 *   Think of `validate-network-seo.mjs` as our automated quality-assurance
 *   inspector for search engines and cross-site hyperlinks across ALL 11
 *   RaggieSoft websites (`raggiesoft.com`, 9 `*.raggiesoft.com` subdomains,
 *   and `michaelpragsdale.com`):
 *     1. Checks that every property has `robots.txt` pointing to `sitemap.xml`,
 *        a valid `sitemap.xml` with `<lastmod>` dates, and our IndexNow API key
 *        file (`726167676965736f6674696e6465786e.txt`).
 *     2. Checks that static sites ship a real `404.html` with `noindex` and
 *        that NO Nginx `.conf` file uses a "soft-404" (`try_files ... /index.html;`
 *        where missing pages falsely return HTTP 200 OK instead of HTTP 404).
 *     3. Builds an in-memory `Set` of every valid URL in `books.raggiesoft.com`
 *        and `music.raggiesoft.com` sitemaps, then scans all source code and
 *        Backstage Markdown files to catch any broken book/song deep links!
 *
 * WHEN IT RUNS:
 *   Run locally (`node raggiesoft-deployment-tools/validate-network-seo.mjs`)
 *   after building subdomains and running `paige.php` to verify zero SEO or
 *   broken-link regressions before shipping.
 *
 * Properties Audited:
 *   1. https://raggiesoft.com              (/raggiesoft.com/www)
 *   2. https://music.raggiesoft.com        (/raggiesoft.com/subdomains/music)
 *   3. https://books.raggiesoft.com        (/raggiesoft.com/subdomains/books)
 *   4. https://engineroom.raggiesoft.com   (/raggiesoft.com/subdomains/engineroom)
 *   5. https://stardust.raggiesoft.com     (/raggiesoft.com/subdomains/stardust)
 *   6. https://corporate.raggiesoft.com    (/raggiesoft.com/subdomains/corporate)
 *   7. https://storetrainer.raggiesoft.com (/raggiesoft.com/subdomains/storetrainer)
 *   8. https://backstage.raggiesoft.com    (/raggiesoft.com/subdomains/backstage)
 *   9. https://lore.raggiesoft.com         (/raggiesoft.com/subdomains/lore)
 *  10. https://nebulae.raggiesoft.com      (/raggiesoft.com/subdomains/nebulae)
 *  11. https://michaelpragsdale.com        (/michaelpragsdale.com/www)
 * ============================================================================
 */

// ES Module (`import`) syntax using Node's explicit `node:` built-in namespace prefix.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// In ES Modules (`.mjs`), CommonJS globals `__filename` and `__dirname` don't exist by default;
// `fileURLToPath(import.meta.url)` converts this module's `file:///...` URL into a standard OS path!
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const serversRoot = path.resolve(__dirname, '../raggiesoft-servers');
const INDEXNOW_KEY = '726167676965736f6674696e6465786e';

// Running counters accumulated across all 3 audit phases; if `errors > 0` at the end, exit with code 1.
let errors = 0;
let totalSitemapUrls = 0;

function fail(msg) {
  console.error(`❌ [SEO ERROR] ${msg}`);
  errors++;
}

function pass(msg) {
  console.log(`✅ ${msg}`);
}

/**
 * Extracts all `<loc>` values from an XML sitemap or `<sitemapindex>` (recursing into child sitemaps).
 * Returns a JavaScript `Set`—a hash-set data structure that automatically deduplicates items
 * and checks `set.has(url)` in `O(1)` constant time!
 *
 * @param {string} xmlPath
 * @param {string} rootDir
 * @param {string} expectedOrigin
 * @returns {Set<string>}
 */
function collectSitemapUrls(xmlPath, rootDir, expectedOrigin) {
  const urls = new Set();
  if (!fs.existsSync(xmlPath)) {
    fail(`Missing sitemap XML: ${xmlPath}`);
    return urls;
  }
  const xml = fs.readFileSync(xmlPath, 'utf8');
  if (!xml.includes('<lastmod>')) {
    fail(`Sitemap missing <lastmod> timestamps: ${xmlPath}`);
  }

  // Recursive case: if `sitemap.xml` is a `<sitemapindex>` (like `books.raggiesoft.com/sitemap.xml`
  // pointing to `sitemaps/editorial.xml`, `books.xml`, `chapters.xml`, `parts.xml`), recursively
  // call `collectSitemapUrls` on each child XML file and merge all URLs into one unified `Set`.
  if (xml.includes('<sitemapindex')) {
    // `[...xml.matchAll(/.../g)]` spreads regex iterator matches into an Array so we can `.map()` capture group 1 (`m[1]`)
    const childLocs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1].trim());
    for (const childUrl of childLocs) {
      const rel = childUrl.replace(expectedOrigin, '').replace(/^\//, '');
      const childPath = path.join(rootDir, rel);
      const childUrls = collectSitemapUrls(childPath, rootDir, expectedOrigin);
      for (const u of childUrls) urls.add(u);
    }
    return urls;
  }

  // Base case: standard `<urlset>` sitemap containing individual page `<loc>` tags
  for (const m of xml.matchAll(/<loc>([^<]+)<\/loc>/g)) {
    const loc = m[1].trim();
    if (!loc.startsWith(expectedOrigin)) {
      fail(`Sitemap ${xmlPath} contains off-origin URL: ${loc}`);
    }
    urls.add(loc);
  }
  return urls;
}

// ============================================================================
// 1. AUDIT ALL 11 PROPERTIES FOR ROBOTS, SITEMAPS, INDEXNOW & 404 PAGES
// ============================================================================
// Static SSG sites (`music/build`, `engineroom/dist`, `michaelpragsdale.com/.../browser`, etc.)
// require a compiled `404.html` (`requireStatic404: true`), whereas dynamic PHP-FPM apps
// (`raggiesoft.com`, `books.raggiesoft.com`) serve HTTP 404 dynamically via PHP routers.
const properties = [
  {
    domain: 'music.raggiesoft.com',
    origin: 'https://music.raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/subdomains/music/build'),
    requireStatic404: true
  },
  {
    domain: 'books.raggiesoft.com',
    origin: 'https://books.raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/subdomains/books'),
    requireStatic404: false
  },
  {
    domain: 'engineroom.raggiesoft.com',
    origin: 'https://engineroom.raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/subdomains/engineroom/dist'),
    requireStatic404: true
  },
  {
    domain: 'stardust.raggiesoft.com',
    origin: 'https://stardust.raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/subdomains/stardust/dist'),
    requireStatic404: true
  },
  {
    domain: 'corporate.raggiesoft.com',
    origin: 'https://corporate.raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/subdomains/corporate/dist'),
    requireStatic404: true
  },
  {
    domain: 'storetrainer.raggiesoft.com',
    origin: 'https://storetrainer.raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/subdomains/storetrainer/dist'),
    requireStatic404: true
  },
  {
    domain: 'backstage.raggiesoft.com',
    origin: 'https://backstage.raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/subdomains/backstage/dist'),
    requireStatic404: true
  },
  {
    domain: 'lore.raggiesoft.com',
    origin: 'https://lore.raggiesoft.com',
    webDir: fs.existsSync(path.join(serversRoot, 'raggiesoft.com/subdomains/lore/out/sitemap.xml'))
      ? path.join(serversRoot, 'raggiesoft.com/subdomains/lore/out')
      : path.join(serversRoot, 'raggiesoft.com/subdomains/lore/public'),
    requireStatic404: fs.existsSync(path.join(serversRoot, 'raggiesoft.com/subdomains/lore/out/sitemap.xml'))
  },
  {
    domain: 'nebulae.raggiesoft.com',
    origin: 'https://nebulae.raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/subdomains/nebulae'),
    requireStatic404: false
  },
  {
    domain: 'michaelpragsdale.com',
    origin: 'https://michaelpragsdale.com',
    webDir: path.join(serversRoot, 'michaelpragsdale.com/www/dist/raggiesoft-portfolio/browser'),
    requireStatic404: true
  },
  {
    domain: 'raggiesoft.com',
    origin: 'https://raggiesoft.com',
    webDir: path.join(serversRoot, 'raggiesoft.com/www'),
    requireStatic404: false,
    allowPendingJennaGenerate: true
  }
];

// `Map` stores `domain -> Set<string>` of canonical URLs for Phase 3's cross-link audit
const domainUrlSets = new Map();

for (const prop of properties) {
  const robotsPath = path.join(prop.webDir, 'robots.txt');
  const sitemapPath = path.join(prop.webDir, 'sitemap.xml');
  const indexNowPath = path.join(prop.webDir, `${INDEXNOW_KEY}.txt`);

  // Check 1A: `robots.txt` exists and declares the exact `Sitemap: https://<domain>/sitemap.xml` line
  if (!fs.existsSync(robotsPath)) {
    fail(`${prop.domain}: Missing robots.txt at ${robotsPath}`);
  } else {
    const robotsTxt = fs.readFileSync(robotsPath, 'utf8');
    if (!robotsTxt.includes(`Sitemap: ${prop.origin}/sitemap.xml`)) {
      fail(`${prop.domain}: robots.txt missing canonical Sitemap directive (${prop.origin}/sitemap.xml)`);
    }
  }

  // Check 1B: IndexNow ownership verification file (`<KEY>.txt`) exists and contains `<KEY>`
  if (!fs.existsSync(indexNowPath)) {
    if (!prop.allowPendingJennaGenerate) {
      fail(`${prop.domain}: Missing IndexNow verification file at ${indexNowPath}`);
    }
  } else {
    const keyVal = fs.readFileSync(indexNowPath, 'utf8').trim();
    if (keyVal !== INDEXNOW_KEY) {
      fail(`${prop.domain}: Invalid IndexNow key content in ${indexNowPath}`);
    }
  }

  // Check 1C: Static `404.html` exists and instructs search crawlers `noindex`
  if (prop.requireStatic404) {
    const p404 = path.join(prop.webDir, '404.html');
    if (!fs.existsSync(p404)) {
      fail(`${prop.domain}: Missing static 404.html at ${p404}`);
    } else {
      const html404 = fs.readFileSync(p404, 'utf8');
      if (!/noindex/i.test(html404)) {
        fail(`${prop.domain}: 404.html is missing <meta name="robots" content="noindex, follow">`);
      }
    }
  }

  // Check 1D: Parse `sitemap.xml` (and any child sitemaps) and store the canonical URL set
  if (fs.existsSync(sitemapPath)) {
    const urls = collectSitemapUrls(sitemapPath, prop.webDir, prop.origin);
    domainUrlSets.set(prop.domain, urls);
    totalSitemapUrls += urls.size;
    pass(`${prop.domain}: ${urls.size} canonical URLs verified (robots.txt + sitemap.xml + 404 guard)`);
  } else {
    fail(`${prop.domain}: Missing sitemap.xml at ${sitemapPath}`);
  }
}

// ============================================================================
// 2. AUDIT ALL NGINX CONFIGS FOR SOFT-404 FALLBACKS
// ============================================================================
// In single-page app tutorials, people often write `try_files $uri $uri/ /index.html;`.
// Unfortunately, that tells Nginx to return `HTTP 200 OK` (instead of `HTTP 404 Not Found`)
// for ANY mistyped URL, which Google penalizes as a "Soft 404". Our static sites pre-render
// every route and must end `try_files` with `=404;` instead!
const nginxDir = path.join(serversRoot, 'nginx-config');
for (const file of fs.readdirSync(nginxDir).filter((f) => f.endsWith('.conf'))) {
  const full = path.join(nginxDir, file);
  const conf = fs.readFileSync(full, 'utf8');
  if (/try_files\s+[^;]*\/index\.html\s*;/.test(conf)) {
    fail(`Nginx config ${file} still contains a soft-404 '/index.html;' fallback!`);
  }
}
pass('All Nginx virtual host configs free of soft-404 /index.html fallbacks.');

// ============================================================================
// 3. CROSS-SITE DEEP-LINK INTEGRITY AUDIT (BOOKS & MUSIC)
// ============================================================================
const validBookUrls = domainUrlSets.get('books.raggiesoft.com') || new Set();
const validMusicUrls = domainUrlSets.get('music.raggiesoft.com') || new Set();

// Allow known dynamic utility routes on books/music that are intentionally `noindex` (excluded from sitemaps)
const allowedExtraBookUrls = new Set([
  'https://books.raggiesoft.com',
  'https://books.raggiesoft.com/',
  'https://books.raggiesoft.com/saved',
  'https://books.raggiesoft.com/search'
]);
const allowedExtraMusicUrls = new Set([
  'https://music.raggiesoft.com',
  'https://music.raggiesoft.com/',
  'https://music.raggiesoft.com/radio',
  'https://music.raggiesoft.com/settings'
]);

/**
 * Recursively walks a directory (`withFileTypes: true` avoids an extra `fs.statSync` call per file!)
 * and collects source/content files while pruning generated build & dependency directories.
 * @param {string} dir
 * @param {string[]} acc
 */
function walkSourceFiles(dir, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (
      entry.name.startsWith('.') ||
      entry.name === 'node_modules' ||
      entry.name === 'dist' ||
      entry.name === 'build' ||
      entry.name === 'out' ||
      entry.name === '.svelte-kit' ||
      entry.name === '.output' ||
      entry.name === 'logs' ||
      entry.name === 'sitemaps'
    ) {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkSourceFiles(full, acc);
    } else if (/\.(?:php|js|mjs|ts|tsx|svelte|json|md|conf)$/i.test(entry.name)) {
      acc.push(full);
    }
  }
  return acc;
}

const scanRoots = [
  path.join(serversRoot, 'raggiesoft.com/www'),
  path.join(serversRoot, 'raggiesoft.com/subdomains'),
  path.join(serversRoot, 'raggiesoft-narratives/backstage'),
  path.join(serversRoot, 'nginx-config')
];

// Match every hardcoded `https://books.raggiesoft.com/...` or `https://music.raggiesoft.com/...` link
const linkRegex = /https:\/\/(?:books|music)\.raggiesoft\.com(?:\/[a-zA-Z0-9_\-\/]+)?/g;
const brokenCrossLinks = [];

for (const root of scanRoots) {
  for (const file of walkSourceFiles(root)) {
    // Skip validation scripts themselves where example strings appear in comments
    if (file.includes('validate-seo')) continue;
    const text = fs.readFileSync(file, 'utf8');
    for (const match of text.matchAll(linkRegex)) {
      const rawUrl = match[0];
      // Ignore static file extensions (`.jpg`, `.png`, `.xml`, `.txt`, `.json`) and JS/PHP template
      // interpolations (`https://books.raggiesoft.com/${slug}` or `"https://..." + slug`) by peeking
      // at the 6 characters immediately following the regex match!
      const afterIdx = (match.index || 0) + rawUrl.length;
      const nextChars = text.slice(afterIdx, afterIdx + 6);
      if (
        nextChars.startsWith('.') ||
        nextChars.startsWith('${') ||
        nextChars.startsWith("' +") ||
        nextChars.startsWith('" +') ||
        nextChars.startsWith('$')
      ) {
        continue;
      }
      const normalized = rawUrl.replace(/\/+$/, '');
      const rootNormalized = normalized.includes('.com/') ? normalized : `${normalized}/`;

      if (rawUrl.startsWith('https://books.raggiesoft.com')) {
        if (
          !validBookUrls.has(normalized) &&
          !validBookUrls.has(rootNormalized) &&
          !allowedExtraBookUrls.has(rawUrl) &&
          !allowedExtraBookUrls.has(normalized)
        ) {
          brokenCrossLinks.push({ file: path.relative(serversRoot, file), url: rawUrl });
        }
      } else if (rawUrl.startsWith('https://music.raggiesoft.com')) {
        if (
          !validMusicUrls.has(normalized) &&
          !validMusicUrls.has(rootNormalized) &&
          !allowedExtraMusicUrls.has(rawUrl) &&
          !allowedExtraMusicUrls.has(normalized)
        ) {
          brokenCrossLinks.push({ file: path.relative(serversRoot, file), url: rawUrl });
        }
      }
    }
  }
}

if (brokenCrossLinks.length > 0) {
  for (const b of brokenCrossLinks.slice(0, 30)) {
    fail(`Broken cross-site link in ${b.file}: ${b.url}`);
  }
  if (brokenCrossLinks.length > 30) {
    fail(`...and ${brokenCrossLinks.length - 30} additional broken cross-site links.`);
  }
} else {
  pass('Zero broken cross-site deep links to books.raggiesoft.com or music.raggiesoft.com across the monorepo!');
}

// Exit with status code `1` if any check failed (stopping CI/deployment), or `0` if 100% clean!
if (errors > 0) {
  console.error(`\n🛑 Network SEO Validation FAILED with ${errors} error(s).`);
  process.exit(1);
}

console.log(
  `\n🚀 Network SEO Validation PASSED! (${totalSitemapUrls.toLocaleString()} total canonical URLs indexed across 11 RaggieSoft properties).`
);

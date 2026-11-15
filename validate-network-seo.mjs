#!/usr/bin/env node
/**
 * @license MIT
 * ============================================================================
 * validate-network-seo.mjs — Network-Wide SEO, Sitemap & Deep-Link Validator
 * ============================================================================
 * Architectural Overview:
 * Automated cross-repository quality gate for all 11 RaggieSoft properties:
 *   1. https://raggiesoft.com            (/raggiesoft.com/www)
 *   2. https://music.raggiesoft.com      (/raggiesoft.com/subdomains/music)
 *   3. https://books.raggiesoft.com      (/raggiesoft.com/subdomains/books)
 *   4. https://engineroom.raggiesoft.com (/raggiesoft.com/subdomains/engineroom)
 *   5. https://stardust.raggiesoft.com   (/raggiesoft.com/subdomains/stardust)
 *   6. https://corporate.raggiesoft.com  (/raggiesoft.com/subdomains/corporate)
 *   7. https://storetrainer.raggiesoft.com (/raggiesoft.com/subdomains/storetrainer)
 *   8. https://backstage.raggiesoft.com  (/raggiesoft.com/subdomains/backstage)
 *   9. https://lore.raggiesoft.com       (/raggiesoft.com/subdomains/lore)
 *  10. https://nebulae.raggiesoft.com    (/raggiesoft.com/subdomains/nebulae)
 *  11. https://michaelpragsdale.com      (/michaelpragsdale.com/www)
 *
 * Verification Checks Performed:
 * 1. Crawler Discovery & IndexNow Verification Parity:
 *    - Asserts `robots.txt` (with `Sitemap:`), `sitemap.xml` (with `<lastmod>`),
 *      and `726167676965736f6674696e6465786e.txt` exist on every property.
 * 2. Soft-404 Elimination & Nginx Vhost Audit:
 *    - Asserts static `404.html` files carry `<meta name="robots" content="noindex, follow"`
 *      and zero Nginx `.conf` files fall back to `/index.html;` soft-404s.
 * 3. Cross-Property Deep-Link Integrity (`books.raggiesoft.com` & `music.raggiesoft.com`):
 *    - Extracts every valid canonical URL from the compiled Book Reader and
 *      Listening Room sitemaps and scans source files across the entire monorepo
 *      to ensure zero broken deep links to books, chapters, artists, albums, or songs.
 * ============================================================================
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const serversRoot = path.resolve(__dirname, '../raggiesoft-servers');
const INDEXNOW_KEY = '726167676965736f6674696e6465786e';

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
 * Extracts all `<loc>` values from an XML sitemap or sitemapindex (recursing into child sitemaps).
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

  if (xml.includes('<sitemapindex')) {
    const childLocs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1].trim());
    for (const childUrl of childLocs) {
      const rel = childUrl.replace(expectedOrigin, '').replace(/^\//, '');
      const childPath = path.join(rootDir, rel);
      const childUrls = collectSitemapUrls(childPath, rootDir, expectedOrigin);
      for (const u of childUrls) urls.add(u);
    }
    return urls;
  }

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

const domainUrlSets = new Map();

for (const prop of properties) {
  const robotsPath = path.join(prop.webDir, 'robots.txt');
  const sitemapPath = path.join(prop.webDir, 'sitemap.xml');
  const indexNowPath = path.join(prop.webDir, `${INDEXNOW_KEY}.txt`);

  if (!fs.existsSync(robotsPath)) {
    fail(`${prop.domain}: Missing robots.txt at ${robotsPath}`);
  } else {
    const robotsTxt = fs.readFileSync(robotsPath, 'utf8');
    if (!robotsTxt.includes(`Sitemap: ${prop.origin}/sitemap.xml`)) {
      fail(`${prop.domain}: robots.txt missing canonical Sitemap directive (${prop.origin}/sitemap.xml)`);
    }
  }

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

// Allow known dynamic utility routes on books/music that are intentionally noindex or 301-redirected
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
 * Recursively collects source/data files across a directory while skipping heavy/irrelevant folders.
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

const linkRegex = /https:\/\/(?:books|music)\.raggiesoft\.com(?:\/[a-zA-Z0-9_\-\/]+)?/g;
const brokenCrossLinks = [];

for (const root of scanRoots) {
  for (const file of walkSourceFiles(root)) {
    // Skip validation scripts themselves where example strings appear in comments
    if (file.includes('validate-seo')) continue;
    const text = fs.readFileSync(file, 'utf8');
    for (const match of text.matchAll(linkRegex)) {
      const rawUrl = match[0];
      // Ignore static file extensions (.jpg, .png, .xml, .txt, .json, etc.) and template interpolations
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

if (errors > 0) {
  console.error(`\n🛑 Network SEO Validation FAILED with ${errors} error(s).`);
  process.exit(1);
}

console.log(
  `\n🚀 Network SEO Validation PASSED! (${totalSitemapUrls.toLocaleString()} total canonical URLs indexed across 11 RaggieSoft properties).`
);

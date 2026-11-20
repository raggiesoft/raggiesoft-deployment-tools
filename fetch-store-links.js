#!/usr/bin/env node
/**
 * ============================================================================
 * Architectural Block: fetch-store-links.js
 * ============================================================================
 * PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
 *   Once DistroKid distributes an Engine Room Records album to commercial
 *   streaming platforms (Apple Music, Spotify, Amazon Music, YouTube Music),
 *   every store assigns the album its own URL. Manually hunting down those URLs
 *   for dozens of albums is tedious—so `fetch-store-links.js` reads the album's
 *   12-digit Universal Product Code barcode (`gtin12` / UPC) from `album.json`,
 *   queries the public Apple iTunes Search API (and optionally the authenticated
 *   Spotify Web API), and saves confirmed store URLs straight back into
 *   `album.json`'s Schema.org `"sameAs"` array!
 *
 * WHEN IT RUNS:
 *   Manually from the terminal (`node fetch-store-links.js <path/to/album.json>`)
 *   a day or two after a DistroKid release goes live on streaming stores.
 *
 * INPUTS & OUTPUTS:
 *   - Reads: `<path/to/album.json>` (plus optional `SPOTIFY_CLIENT_ID` and
 *     `SPOTIFY_CLIENT_SECRET` environment variables).
 *   - Writes: Injects deduplicated DistroKid HyperFollow, Apple Music, and
 *     Spotify URLs into `album.json` (`"sameAs": [...]`) so `music.raggiesoft.com`
 *     and `engineroom.raggiesoft.com` render live store badges automatically.
 *
 * HOW LINE 1 (`#!/usr/bin/env node`) WORKS:
 *   Tells macOS/Linux/Git Bash to execute this JavaScript file using Node.js
 *   directly from the command line, outside of any web browser.
 * ============================================================================
 */

// CommonJS (`require`) imports Node.js built-in standard library modules:
// - `fs` ("file system") reads and writes local files on disk.
// - `path` resolves relative file paths (`./album.json`) into full OS paths.
const fs = require('fs');
const path = require('path');

/**
 * Exchanges a Spotify Developer App ID + Secret for a short-lived OAuth 2.0
 * Bearer token using the "Client Credentials" flow (`async`/`await` pauses
 * cleanly while waiting for the HTTPS network reply without freezing Node).
 */
async function getSpotifyToken(clientId, clientSecret) {
    // HTTP Basic Auth encodes `clientId:clientSecret` as Base64 in the `Authorization` header.
    const response = await fetch('https://accounts.spotify.com/api/token', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Authorization': 'Basic ' + Buffer.from(clientId + ':' + clientSecret).toString('base64')
        },
        body: 'grant_type=client_credentials'
    });
    const data = await response.json();
    return data.access_token;
}

/**
 * Queries Spotify's catalog by barcode (`q=upc:<12-digit-upc>`) using the Bearer token
 * obtained above, returning the canonical `https://open.spotify.com/album/...` URL if live.
 */
async function searchSpotifyByUpc(upc, token) {
    const response = await fetch(`https://api.spotify.com/v1/search?q=upc:${upc}&type=album&limit=1`, {
        headers: {
            'Authorization': `Bearer ${token}`
        }
    });
    const data = await response.json();
    if (data.albums && data.albums.items && data.albums.items.length > 0) {
        return data.albums.items[0].external_urls.spotify;
    }
    return null;
}

async function main() {
    // `process.argv` is Node's command-line argument array:
    //   argv[0] = `/path/to/node`
    //   argv[1] = `/path/to/fetch-store-links.js`
    //   argv[2..] = user arguments! `.slice(2)` drops the first two items.
    const args = process.argv.slice(2);
    if (args.length === 0) {
        console.error("Usage: node fetch-store-links.js <path/to/album.json>");
        // `process.exit(1)` signals an error exit code (`1`) back to the shell.
        process.exit(1);
    }

    const albumJsonPath = path.resolve(args[0]);
    if (!fs.existsSync(albumJsonPath)) {
        console.error("File not found:", albumJsonPath);
        process.exit(1);
    }

    // Read `album.json` as UTF-8 text and parse it into a JavaScript object (`JSON.parse`).
    // `?.` is JavaScript's "Optional Chaining" operator: if `byArtist` is missing/undefined,
    // it returns `undefined` safely instead of throwing `TypeError: Cannot read properties of undefined`.
    const albumData = JSON.parse(fs.readFileSync(albumJsonPath, 'utf8'));
    const upc = albumData.gtin12 || albumData.gtin13 || albumData.gtin14;
    const artist = albumData.byArtist?.name || "Unknown Artist";
    const title = albumData.name || "Unknown Album";

    if (!upc) {
        console.error("Error: Could not find a UPC (gtin12, gtin13, or gtin14) in the album.json file.");
        process.exit(1);
    }

    console.log(`\n🔍 Searching stores for: ${artist} - ${title} (UPC: ${upc})`);
    
    // Strip everything except lowercase letters and digits (`[^a-z0-9]`) to build DistroKid's HyperFollow slug
    const dkArtist = artist.toLowerCase().replace(/[^a-z0-9]/g, '');
    const dkTitle = title.toLowerCase().replace(/[^a-z0-9]/g, '');
    
    const links = {
        distrokid: `https://distrokid.com/hyperfollow/${dkArtist}/${dkTitle}`
    };

    // 1. iTunes / Apple Music (Free Public Lookup API — zero API key required!)
    console.log("   -> Querying Apple Music/iTunes API...");
    try {
        const itunesResponse = await fetch(`https://itunes.apple.com/search?upc=${upc}&entity=album`);
        const itunesData = await itunesResponse.json();
        if (itunesData.resultCount > 0) {
            links.appleMusic = itunesData.results[0].collectionViewUrl;
            console.log("      ✓ Found on Apple Music!");
        } else {
            console.log("      ⚠️  Not found on Apple Music (Might not be live yet, or UPC mismatch).");
        }
    } catch (e) {
        console.log("      ❌ Error querying Apple Music API:", e.message);
    }

    // 2. Spotify (Requires OAuth Client ID & Secret from `process.env`)
    console.log("   -> Querying Spotify API...");
    const SPOTIFY_CLIENT_ID = process.env.SPOTIFY_CLIENT_ID;
    const SPOTIFY_CLIENT_SECRET = process.env.SPOTIFY_CLIENT_SECRET;
    
    if (SPOTIFY_CLIENT_ID && SPOTIFY_CLIENT_SECRET) {
        try {
            const token = await getSpotifyToken(SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET);
            const spotifyUrl = await searchSpotifyByUpc(upc, token);
            if (spotifyUrl) {
                links.spotify = spotifyUrl;
                console.log("      ✓ Found on Spotify!");
            } else {
                console.log("      ⚠️  Not found on Spotify.");
            }
        } catch (e) {
            console.log("      ❌ Error querying Spotify API:", e.message);
        }
    } else {
        console.log("      ⚠️  Skipping Spotify API: SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET environment variables are not set.");
        // `encodeURIComponent` escapes spaces and symbols (`&`, `?`) so they are safe inside a URL path/query
        links.spotifySearch = `https://open.spotify.com/search/${encodeURIComponent(artist + " " + title)}`;
    }

    // 3. Amazon & YouTube (Generate search links for terminal reference since they lack public unauthenticated UPC APIs)
    links.amazonSearch = `https://music.amazon.com/search/${encodeURIComponent(artist + " " + title)}`;
    links.youtubeSearch = `https://music.youtube.com/search?q=${encodeURIComponent(artist + " " + title)}`;

    console.log("\n📦 Generated Store Links:");
    // `JSON.stringify(value, null, 2)` pretty-prints the object with 2-space indentation
    console.log(JSON.stringify(links, null, 2));

    // Persist ONLY confirmed direct store URLs (filtering out `*Search` fallback keys)
    // into Schema.org's standard `"sameAs"` array inside `album.json`.
    const confirmedUrls = Object.keys(links)
        .filter(key => !key.includes('Search') && links[key])
        .map(key => links[key]);

    if (confirmedUrls.length > 0) {
        // Normalize existing `sameAs` in case an older `album.json` stored a single string instead of an array
        let sameAs = albumData.sameAs || [];
        if (!Array.isArray(sameAs)) {
            sameAs = [sameAs];
        }
        
        // Deduplicate: only append URLs that aren't already listed in `sameAs`
        for (const url of confirmedUrls) {
            if (!sameAs.includes(url)) {
                sameAs.push(url);
            }
        }
        
        albumData.sameAs = sameAs;
        fs.writeFileSync(albumJsonPath, JSON.stringify(albumData, null, 2));
        console.log(`\n✅ Successfully injected confirmed links into ${albumJsonPath}`);
    } else {
        console.log(`\n⚠️ No confirmed direct store links found to inject into the file.`);
    }
}

// Kick off the top-level async workflow
main();


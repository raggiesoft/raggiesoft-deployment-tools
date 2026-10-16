#!/usr/bin/env node
/**
 * fetch-store-links.js
 * Automatically fetches streaming store links for an album using its UPC (gtin12/gtin13).
 * Queries the iTunes API for Apple Music links and generates fallback/search URLs for others.
 * If SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET environment variables are set, it will query Spotify.
 * 
 * Usage: node fetch-store-links.js <path/to/album.json>
 */

const fs = require('fs');
const path = require('path');

async function getSpotifyToken(clientId, clientSecret) {
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
    const args = process.argv.slice(2);
    if (args.length === 0) {
        console.error("Usage: node fetch-store-links.js <path/to/album.json>");
        process.exit(1);
    }

    const albumJsonPath = path.resolve(args[0]);
    if (!fs.existsSync(albumJsonPath)) {
        console.error("File not found:", albumJsonPath);
        process.exit(1);
    }

    const albumData = JSON.parse(fs.readFileSync(albumJsonPath, 'utf8'));
    const upc = albumData.gtin12 || albumData.gtin13 || albumData.gtin14;
    const artist = albumData.byArtist?.name || "Unknown Artist";
    const title = albumData.name || "Unknown Album";

    if (!upc) {
        console.error("Error: Could not find a UPC (gtin12, gtin13, or gtin14) in the album.json file.");
        process.exit(1);
    }

    console.log(`\n🔍 Searching stores for: ${artist} - ${title} (UPC: ${upc})`);
    
    // Format DistroKid URL safely
    const dkArtist = artist.toLowerCase().replace(/[^a-z0-9]/g, '');
    const dkTitle = title.toLowerCase().replace(/[^a-z0-9]/g, '');
    
    const links = {
        distrokid: `https://distrokid.com/hyperfollow/${dkArtist}/${dkTitle}`
    };

    // 1. iTunes / Apple Music (Public API)
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

    // 2. Spotify (Requires Auth)
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
        // Fallback: search link
        links.spotifySearch = `https://open.spotify.com/search/${encodeURIComponent(artist + " " + title)}`;
    }

    // 3. Amazon & YouTube (Generate search links as fallback since they lack public open UPC APIs)
    links.amazonSearch = `https://music.amazon.com/search/${encodeURIComponent(artist + " " + title)}`;
    links.youtubeSearch = `https://music.youtube.com/search?q=${encodeURIComponent(artist + " " + title)}`;

    console.log("\n📦 Generated Store Links:");
    console.log(JSON.stringify(links, null, 2));

    // Update the file using the Schema.org "sameAs" property for social/store links
    // We only inject confirmed URLs (not the fallback search links)
    const confirmedUrls = Object.keys(links)
        .filter(key => !key.includes('Search') && links[key])
        .map(key => links[key]);

    if (confirmedUrls.length > 0) {
        // Merge with existing sameAs if it exists
        let sameAs = albumData.sameAs || [];
        if (!Array.isArray(sameAs)) {
            sameAs = [sameAs];
        }
        
        // Add new URLs, avoiding duplicates
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

main();


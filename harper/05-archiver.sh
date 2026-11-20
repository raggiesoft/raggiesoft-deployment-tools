#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 05: ARCHIVER (`harper/05-archiver.sh`)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Sourced at the end of each album in `03-album-processor.sh` (right after all
#   parallel FFmpeg workers finish), Module 05 uses **7-Zip** (`7zz` / `7za.exe`)
#   to bundle 6 self-contained album packages—each containing the audio files,
#   `album-art.jpg`, `read-me.txt`, Markdown + `.vtt` timed lyrics, and CC BY-SA 4.0
#   `/suno-prompts/*.md` recreation prompts:
#     1. `<year>-<album>-mp3.zip`              (Vault: LAME V0 MP3s)
#     2. `<year>-<album>-ogg.zip`              (Vault: Vorbis Q9 OGGs)
#     3. `<year>-<album>-wav.7z`               (Vault: BWF Master WAVs in Ultra Solid 7z)
#     4. `<year>-<album>-flac.7z`              (Vault: Lossless FLACs in Ultra Solid 7z)
#     5. `<year>-<album>-standard-archive.zip` (Vault: Combined V0 MP3 + Q9 OGG)
#     6. `web-mp3/<year>-<album>-free-archive.zip` (Public CDN: Free 128 kbps MP3 download!)
#
# WHY `.zip -mx=5` FOR MP3/OGG vs. `.7z -mx=9 -ms=on` FOR WAV/FLAC:
#   - MP3 and OGG files are *already* heavily compressed; running ultra LZMA2
#     compression on them saves < 1% space while burning CPU, AND `.zip` opens
#     natively on every phone/OS with double-click (`-tzip -mx=5` normal compression).
#   - Uncompressed WAVs (~50 MB/song) benefit massively from 7-Zip's LZMA2 Ultra
#     (`-t7z -mx=9`) + **Solid Mode** (`-ms=on`, which compresses all files together
#     as one continuous data stream so shared headers/silence shrink dramatically!).
# ==============================================================================

# Proceed with archiving only if 7-Zip was found AND we aren't in `--metadata` mode
# (`{ cmdA || cmdB; }` groups boolean conditions inside the same shell without a subshell).
if [ "$USE_SEVEN_ZIP" = true ] && { [ "$METADATA_ONLY" = false ] || [ "$ALBUM_MINTED_NEW_ISRC" = true ]; }; then
    ARCHIVE_OVERWRITE="$OVERWRITE"
    if [ "$ALBUM_MINTED_NEW_ISRC" = true ]; then
        ARCHIVE_OVERWRITE=true
    fi
    VAULT_TARGET="${ALBUM_VAULT_DIR:-vault}"
    mkdir -p "$VAULT_TARGET/archives"

    # Target archive paths inside the private local Vault (`/raggiesoft-vaults/...`)
    ZIP_MP3="$VAULT_TARGET/archives/${ARCHIVE_BASE_NAME}-mp3.zip"
    ZIP_OGG="$VAULT_TARGET/archives/${ARCHIVE_BASE_NAME}-ogg.zip"
    ZIP_WAV="$VAULT_TARGET/archives/${ARCHIVE_BASE_NAME}-wav.7z"
    ZIP_FLAC="$VAULT_TARGET/archives/${ARCHIVE_BASE_NAME}-flac.7z"
    ZIP_STANDARD="$VAULT_TARGET/archives/${ARCHIVE_BASE_NAME}-standard-archive.zip"

    echo "      🎙️  HARPER: Booting up the Archiver. Securing files into the Vault ($VAULT_TARGET)..."

    # --------------------------------------------------------------------------
    # 1. Premium MP3 Archive (`-mp3.zip`)
    # --------------------------------------------------------------------------
    # Staging Pattern: Copy all desired files into a temporary `staging_mp3/` folder,
    # `pushd` inside it so `*` zips clean relative filenames (no ugly `../../vault/`
    # parent folders inside the `.zip`!), then `popd` and `rm -rf` the staging folder!
    if [ ! -f "$ZIP_MP3" ] || [ "$ARCHIVE_OVERWRITE" = true ]; then
        echo "         -> 📦 Packing Premium MP3 Archive..."
        rm -f "$ZIP_MP3"
        mkdir -p "$VAULT_TARGET/archives/staging_mp3/lyrics"
        mkdir -p "$VAULT_TARGET/archives/staging_mp3/metadata"
        
        # Stage V0 MP3 audio, DSP metadata sheets, README, cover art, lyrics + `.vtt`, and `suno-prompts/`
        cp "$VAULT_TARGET/mp3/"*.mp3 "$VAULT_TARGET/archives/staging_mp3/" 2>/dev/null
        cp streaming-services/song-metadata/*.md "$VAULT_TARGET/archives/staging_mp3/metadata/" 2>/dev/null
        cp "$README_FILE" "$VAULT_TARGET/archives/staging_mp3/"
        [ -f "$ART_FILE" ] && cp "$ART_FILE" "$VAULT_TARGET/archives/staging_mp3/"
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md "$VAULT_TARGET/archives/staging_mp3/lyrics/" 2>/dev/null
            cp lyrics/*.vtt "$VAULT_TARGET/archives/staging_mp3/lyrics/" 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" "$VAULT_TARGET/archives/staging_mp3/"
        fi

        if [ "$HAS_SUNO_PROMPTS" = true ]; then
            mkdir -p "$VAULT_TARGET/archives/staging_mp3/suno-prompts"
            cp suno-prompts/*.md "$VAULT_TARGET/archives/staging_mp3/suno-prompts/" 2>/dev/null
        fi
        
        # `7zz a -tzip -mx=5` (`a` = add to archive, `-tzip` = ZIP format, `-mx=5` = level 5 compression)
        pushd "$VAULT_TARGET/archives/staging_mp3" > /dev/null
        "$SEVEN_ZIP_CMD" a -tzip -mx=5 "../${ARCHIVE_BASE_NAME}-mp3.zip" * || HARPER_ARCHIVE_ERRORS=$((HARPER_ARCHIVE_ERRORS + 1))
        popd > /dev/null
        rm -rf "$VAULT_TARGET/archives/staging_mp3"
    else
        echo "         ⏭️  Premium MP3 Archive already exists! Skipping."
    fi

    # --------------------------------------------------------------------------
    # 2. Premium OGG Archive (`-ogg.zip`)
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_OGG" ] || [ "$ARCHIVE_OVERWRITE" = true ]; then
        echo "         -> 📦 Packing Premium OGG Archive..."
        rm -f "$ZIP_OGG"
        mkdir -p "$VAULT_TARGET/archives/staging_ogg/lyrics"
        mkdir -p "$VAULT_TARGET/archives/staging_ogg/metadata"
        
        cp "$VAULT_TARGET/ogg/"*.ogg "$VAULT_TARGET/archives/staging_ogg/" 2>/dev/null
        cp streaming-services/song-metadata/*.md "$VAULT_TARGET/archives/staging_ogg/metadata/" 2>/dev/null
        cp "$README_FILE" "$VAULT_TARGET/archives/staging_ogg/"
        [ -f "$ART_FILE" ] && cp "$ART_FILE" "$VAULT_TARGET/archives/staging_ogg/"
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md "$VAULT_TARGET/archives/staging_ogg/lyrics/" 2>/dev/null
            cp lyrics/*.vtt "$VAULT_TARGET/archives/staging_ogg/lyrics/" 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" "$VAULT_TARGET/archives/staging_ogg/"
        fi

        if [ "$HAS_SUNO_PROMPTS" = true ]; then
            mkdir -p "$VAULT_TARGET/archives/staging_ogg/suno-prompts"
            cp suno-prompts/*.md "$VAULT_TARGET/archives/staging_ogg/suno-prompts/" 2>/dev/null
        fi
        
        pushd "$VAULT_TARGET/archives/staging_ogg" > /dev/null
        "$SEVEN_ZIP_CMD" a -tzip -mx=5 "../${ARCHIVE_BASE_NAME}-ogg.zip" * || HARPER_ARCHIVE_ERRORS=$((HARPER_ARCHIVE_ERRORS + 1))
        popd > /dev/null
        rm -rf "$VAULT_TARGET/archives/staging_ogg"
    else
        echo "         ⏭️  Premium OGG Archive already exists! Skipping."
    fi

    # --------------------------------------------------------------------------
    # 3. WAV Master Archive (`-wav.7z` — LZMA2 Ultra Solid Compression)
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_WAV" ] || [ "$ARCHIVE_OVERWRITE" = true ]; then
        echo "         -> 📦 Packing massive WAV Master Archive (Ultra Compression active!)..."
        rm -f "$ZIP_WAV"
        mkdir -p "$VAULT_TARGET/archives/staging_wav/lyrics"
        mkdir -p "$VAULT_TARGET/archives/staging_wav/metadata"
        
        cp "$VAULT_TARGET/wav/"*.wav "$VAULT_TARGET/archives/staging_wav/" 2>/dev/null
        cp streaming-services/song-metadata/*.md "$VAULT_TARGET/archives/staging_wav/metadata/" 2>/dev/null
        cp "$README_FILE" "$VAULT_TARGET/archives/staging_wav/"
        [ -f "$ART_FILE" ] && cp "$ART_FILE" "$VAULT_TARGET/archives/staging_wav/"
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md "$VAULT_TARGET/archives/staging_wav/lyrics/" 2>/dev/null
            cp lyrics/*.vtt "$VAULT_TARGET/archives/staging_wav/lyrics/" 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" "$VAULT_TARGET/archives/staging_wav/"
        fi

        if [ "$HAS_SUNO_PROMPTS" = true ]; then
            mkdir -p "$VAULT_TARGET/archives/staging_wav/suno-prompts"
            cp suno-prompts/*.md "$VAULT_TARGET/archives/staging_wav/suno-prompts/" 2>/dev/null
        fi
        
        # `-t7z -mx=9 -ms=on`: 7z container, Ultra level-9 dictionary, Solid archive block enabled
        pushd "$VAULT_TARGET/archives/staging_wav" > /dev/null
        "$SEVEN_ZIP_CMD" a -t7z -mx=9 -ms=on "../${ARCHIVE_BASE_NAME}-wav.7z" * || HARPER_ARCHIVE_ERRORS=$((HARPER_ARCHIVE_ERRORS + 1))
        popd > /dev/null
        rm -rf "$VAULT_TARGET/archives/staging_wav"
    else
        echo "         ⏭️  WAV Master Archive already exists! Skipping."
    fi

    # --------------------------------------------------------------------------
    # 4. Audiophile FLAC Archive (`-flac.7z`)
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_FLAC" ] || [ "$ARCHIVE_OVERWRITE" = true ]; then
        echo "         -> 📦 Packing Audiophile FLAC Archive..."
        rm -f "$ZIP_FLAC"
        mkdir -p "$VAULT_TARGET/archives/staging_flac/lyrics"
        mkdir -p "$VAULT_TARGET/archives/staging_flac/metadata"
        
        cp "$VAULT_TARGET/flac/"*.flac "$VAULT_TARGET/archives/staging_flac/" 2>/dev/null
        cp streaming-services/song-metadata/*.md "$VAULT_TARGET/archives/staging_flac/metadata/" 2>/dev/null
        cp "$README_FILE" "$VAULT_TARGET/archives/staging_flac/"
        [ -f "$ART_FILE" ] && cp "$ART_FILE" "$VAULT_TARGET/archives/staging_flac/"
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md "$VAULT_TARGET/archives/staging_flac/lyrics/" 2>/dev/null
            cp lyrics/*.vtt "$VAULT_TARGET/archives/staging_flac/lyrics/" 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" "$VAULT_TARGET/archives/staging_flac/"
        fi

        if [ "$HAS_SUNO_PROMPTS" = true ]; then
            mkdir -p "$VAULT_TARGET/archives/staging_flac/suno-prompts"
            cp suno-prompts/*.md "$VAULT_TARGET/archives/staging_flac/suno-prompts/" 2>/dev/null
        fi
        
        pushd "$VAULT_TARGET/archives/staging_flac" > /dev/null
        "$SEVEN_ZIP_CMD" a -t7z -mx=9 -ms=on "../${ARCHIVE_BASE_NAME}-flac.7z" * || HARPER_ARCHIVE_ERRORS=$((HARPER_ARCHIVE_ERRORS + 1))
        popd > /dev/null
        rm -rf "$VAULT_TARGET/archives/staging_flac"
    else
        echo "         ⏭️  Audiophile FLAC Archive already exists! Skipping."
    fi
    
    # --------------------------------------------------------------------------
    # 5. Standard Archive (`-standard-archive.zip` — Combined V0 MP3 + Q9 OGG)
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_STANDARD" ] || [ "$ARCHIVE_OVERWRITE" = true ]; then
        echo "         -> 📦 Packing the Standard Archive (MP3 & OGG)..."
        rm -f "$ZIP_STANDARD"
        mkdir -p "$VAULT_TARGET/archives/staging_standard/lyrics"
        mkdir -p "$VAULT_TARGET/archives/staging_standard/metadata"
        mkdir -p "$VAULT_TARGET/archives/staging_standard/mp3"
        mkdir -p "$VAULT_TARGET/archives/staging_standard/ogg"
        
        cp "$VAULT_TARGET/mp3/"*.mp3 "$VAULT_TARGET/archives/staging_standard/mp3/" 2>/dev/null
        cp "$VAULT_TARGET/ogg/"*.ogg "$VAULT_TARGET/archives/staging_standard/ogg/" 2>/dev/null
        
        cp streaming-services/song-metadata/*.md "$VAULT_TARGET/archives/staging_standard/metadata/" 2>/dev/null
        cp "$README_FILE" "$VAULT_TARGET/archives/staging_standard/"
        [ -f "$ART_FILE" ] && cp "$ART_FILE" "$VAULT_TARGET/archives/staging_standard/"
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md "$VAULT_TARGET/archives/staging_standard/lyrics/" 2>/dev/null
            cp lyrics/*.vtt "$VAULT_TARGET/archives/staging_standard/lyrics/" 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" "$VAULT_TARGET/archives/staging_standard/"
        fi

        if [ "$HAS_SUNO_PROMPTS" = true ]; then
            mkdir -p "$VAULT_TARGET/archives/staging_standard/suno-prompts"
            cp suno-prompts/*.md "$VAULT_TARGET/archives/staging_standard/suno-prompts/" 2>/dev/null
        fi
        
        pushd "$VAULT_TARGET/archives/staging_standard" > /dev/null
        "$SEVEN_ZIP_CMD" a -tzip -mx=5 "../${ARCHIVE_BASE_NAME}-standard-archive.zip" * || HARPER_ARCHIVE_ERRORS=$((HARPER_ARCHIVE_ERRORS + 1))
        popd > /dev/null
        rm -rf "$VAULT_TARGET/archives/staging_standard"
    else
        echo "         ⏭️  Standard Archive (MP3 & OGG) already exists! Skipping."
    fi

    # --------------------------------------------------------------------------
    # 6. Free Web Archive (`web-mp3/<album>-free-archive.zip` — Public CC BY-SA 4.0 CDN Bundle)
    # --------------------------------------------------------------------------
    # Unlike Tiers 1–5 (which stay inside `/raggiesoft-vaults`), this `.zip` lives in
    # `web-mp3/` inside `raggiesoft-assets` so `jenna-sync.sh` uploads it to DigitalOcean
    # Spaces CDN (`assets.raggiesoft.com`), giving listeners on `music.raggiesoft.com`
    # one-click free album downloads!
    ZIP_FREE="web-mp3/${ARCHIVE_BASE_NAME}-free-archive.zip"

    if [ ! -f "$ZIP_FREE" ] || [ "$ARCHIVE_OVERWRITE" = true ]; then
        echo "         -> 📦 Packing the Free Web Archive (128kbps MP3)..."
        rm -f "$ZIP_FREE"
        
        mkdir -p web-mp3/staging_free/lyrics
        
        cp web-mp3/*.mp3 web-mp3/staging_free/ 2>/dev/null
        cp "$README_FILE" web-mp3/staging_free/
        [ -f "$ART_FILE" ] && cp "$ART_FILE" web-mp3/staging_free/
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md web-mp3/staging_free/lyrics/ 2>/dev/null
            cp lyrics/*.vtt web-mp3/staging_free/lyrics/ 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" web-mp3/staging_free/
        fi

        if [ "$HAS_SUNO_PROMPTS" = true ]; then
            mkdir -p web-mp3/staging_free/suno-prompts
            cp suno-prompts/*.md web-mp3/staging_free/suno-prompts/ 2>/dev/null
        fi
        
        pushd web-mp3/staging_free 
        "$SEVEN_ZIP_CMD" a -tzip -mx=5 "../${ARCHIVE_BASE_NAME}-free-archive.zip" * || HARPER_ARCHIVE_ERRORS=$((HARPER_ARCHIVE_ERRORS + 1))
        popd 
        
        rm -rf web-mp3/staging_free
    else
        echo "         ⏭️  Free Web Archive (128kbps MP3) already exists! Skipping."
    fi
    
    echo "   📦 HARPER: Vault secure. Archives packed."
fi
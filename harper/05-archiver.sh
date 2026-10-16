#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 05: ARCHIVER
# ==============================================================================
# ARCHITECTURAL OVERVIEW:
# This script handles the automated packaging of album directories into various 
# delivery formats (ZIP and 7z). It builds distribution packages for MP3, OGG, 
# WAV, FLAC, and standard multi-format archives, as well as a lower-bitrate free web version.
#
# FUTURE MAINTENANCE NOTES:
# - This script is dynamically sourced at the end of the album loop in Module 03,
#   meaning variables like $ARCHIVE_BASE_NAME, $HAS_LYRICS, etc., are inherited.
# - 7-Zip compression levels (e.g., -mx=9 for FLAC/WAV, -mx=5 for MP3) should be 
#   adjusted carefully depending on speed-vs-size requirements.
# ==============================================================================
# Note: This is sourced at the end of the album loop in Module 03.

# Proceed with archiving only if 7-zip was located and we aren't doing metadata-only
if [ "$USE_SEVEN_ZIP" = true ] && [ "$METADATA_ONLY" = false ]; then
    # Define standard target paths for archive variations
    ZIP_MP3="vault/archives/${ARCHIVE_BASE_NAME}-mp3.zip"
    ZIP_OGG="vault/archives/${ARCHIVE_BASE_NAME}-ogg.zip"
    ZIP_WAV="vault/archives/${ARCHIVE_BASE_NAME}-wav.7z"
    ZIP_FLAC="vault/archives/${ARCHIVE_BASE_NAME}-flac.7z"
    ZIP_STANDARD="vault/archives/${ARCHIVE_BASE_NAME}-standard-archive.zip"

    echo "      🎙️  HARPER: Booting up the Archiver. Securing files into the Vault..."

    # --------------------------------------------------------------------------
    # 1. Premium MP3 Archive
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_MP3" ] || [ "$OVERWRITE" = true ]; then
        echo "         -> 📦 Packing Premium MP3 Archive..."
        rm -f "$ZIP_MP3"
        mkdir -p vault/archives/staging_mp3/lyrics
        mkdir -p vault/archives/staging_mp3/metadata
        
        # Stage necessary assets (audio, metadata, artwork, lyrics)
        cp vault/mp3/*.mp3 vault/archives/staging_mp3/ 2>/dev/null
        cp streaming-services/song-metadata/*.md vault/archives/staging_mp3/metadata/ 2>/dev/null
        cp "$README_FILE" vault/archives/staging_mp3/
        [ -f "$ART_FILE" ] && cp "$ART_FILE" vault/archives/staging_mp3/
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md vault/archives/staging_mp3/lyrics/ 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" vault/archives/staging_mp3/
        fi
        
        # Zip the staged directory and cleanup
        pushd vault/archives/staging_mp3 
        "$SEVEN_ZIP_CMD" a -tzip -mx=5 "../${ARCHIVE_BASE_NAME}-mp3.zip" * 
        popd 
        rm -rf vault/archives/staging_mp3
    else
        echo "         ⏭️  Premium MP3 Archive already exists! Skipping."
    fi

    # --------------------------------------------------------------------------
    # 2. Premium OGG Archive
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_OGG" ] || [ "$OVERWRITE" = true ]; then
        echo "         -> 📦 Packing Premium OGG Archive..."
        rm -f "$ZIP_OGG"
        mkdir -p vault/archives/staging_ogg/lyrics
        mkdir -p vault/archives/staging_ogg/metadata
        
        # Stage OGG assets
        cp vault/ogg/*.ogg vault/archives/staging_ogg/ 2>/dev/null
        cp streaming-services/song-metadata/*.md vault/archives/staging_ogg/metadata/ 2>/dev/null
        cp "$README_FILE" vault/archives/staging_ogg/
        [ -f "$ART_FILE" ] && cp "$ART_FILE" vault/archives/staging_ogg/
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md vault/archives/staging_ogg/lyrics/ 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" vault/archives/staging_ogg/
        fi
        
        # Zip the staged directory and cleanup
        pushd vault/archives/staging_ogg 
        "$SEVEN_ZIP_CMD" a -tzip -mx=5 "../${ARCHIVE_BASE_NAME}-ogg.zip" * 
        popd 
        rm -rf vault/archives/staging_ogg
    else
        echo "         ⏭️  Premium OGG Archive already exists! Skipping."
    fi

    # --------------------------------------------------------------------------
    # 3. WAV Master Archive (Ultra Compression)
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_WAV" ] || [ "$OVERWRITE" = true ]; then
        echo "         -> 📦 Packing massive WAV Master Archive (Ultra Compression active!)..."
        rm -f "$ZIP_WAV"
        mkdir -p vault/archives/staging_wav/lyrics
        mkdir -p vault/archives/staging_wav/metadata
        
        # Stage WAV assets
        cp vault/wav/*.wav vault/archives/staging_wav/ 2>/dev/null
        cp streaming-services/song-metadata/*.md vault/archives/staging_wav/metadata/ 2>/dev/null
        cp "$README_FILE" vault/archives/staging_wav/
        [ -f "$ART_FILE" ] && cp "$ART_FILE" vault/archives/staging_wav/
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md vault/archives/staging_wav/lyrics/ 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" vault/archives/staging_wav/
        fi
        
        # Use 7z solid archiving with maximum compression (-mx=9) to handle massive uncompressed audio
        pushd vault/archives/staging_wav 
        "$SEVEN_ZIP_CMD" a -t7z -mx=9 -ms=on "../${ARCHIVE_BASE_NAME}-wav.7z" * 
        popd 
        rm -rf vault/archives/staging_wav
    else
        echo "         ⏭️  WAV Master Archive already exists! Skipping."
    fi

    # --------------------------------------------------------------------------
    # 4. Audiophile FLAC Archive
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_FLAC" ] || [ "$OVERWRITE" = true ]; then
        echo "         -> 📦 Packing Audiophile FLAC Archive..."
        rm -f "$ZIP_FLAC"
        mkdir -p vault/archives/staging_flac/lyrics
        mkdir -p vault/archives/staging_flac/metadata
        
        # Stage FLAC assets
        cp vault/flac/*.flac vault/archives/staging_flac/ 2>/dev/null
        cp streaming-services/song-metadata/*.md vault/archives/staging_flac/metadata/ 2>/dev/null
        cp "$README_FILE" vault/archives/staging_flac/
        [ -f "$ART_FILE" ] && cp "$ART_FILE" vault/archives/staging_flac/
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md vault/archives/staging_flac/lyrics/ 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" vault/archives/staging_flac/
        fi
        
        # Use 7z solid archiving for maximum efficiency on FLAC files
        pushd vault/archives/staging_flac 
        "$SEVEN_ZIP_CMD" a -t7z -mx=9 -ms=on "../${ARCHIVE_BASE_NAME}-flac.7z" * 
        popd 
        rm -rf vault/archives/staging_flac
    else
        echo "         ⏭️  Audiophile FLAC Archive already exists! Skipping."
    fi
    
    # --------------------------------------------------------------------------
    # 5. Standard Archive (MP3 & OGG combined)
    # --------------------------------------------------------------------------
    if [ ! -f "$ZIP_STANDARD" ] || [ "$OVERWRITE" = true ]; then
        echo "         -> 📦 Packing the Standard Archive (MP3 & OGG)..."
        rm -f "$ZIP_STANDARD"
        mkdir -p vault/archives/staging_standard/lyrics
        mkdir -p vault/archives/staging_standard/metadata
        mkdir -p vault/archives/staging_standard/mp3
        mkdir -p vault/archives/staging_standard/ogg
        
        # Stage both MP3 and OGG along with shared assets
        cp vault/mp3/*.mp3 vault/archives/staging_standard/mp3/ 2>/dev/null
        cp vault/ogg/*.ogg vault/archives/staging_standard/ogg/ 2>/dev/null
        
        cp streaming-services/song-metadata/*.md vault/archives/staging_standard/metadata/ 2>/dev/null
        cp "$README_FILE" vault/archives/staging_standard/
        [ -f "$ART_FILE" ] && cp "$ART_FILE" vault/archives/staging_standard/
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md vault/archives/staging_standard/lyrics/ 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" vault/archives/staging_standard/
        fi
        
        pushd vault/archives/staging_standard 
        "$SEVEN_ZIP_CMD" a -tzip -mx=5 "../${ARCHIVE_BASE_NAME}-standard-archive.zip" * 
        popd 
        rm -rf vault/archives/staging_standard
    else
        echo "         ⏭️  Standard Archive (MP3 & OGG) already exists! Skipping."
    fi

    # --------------------------------------------------------------------------
    # 6. Free Web Archive (128kbps MP3)
    # --------------------------------------------------------------------------
    ZIP_FREE="web-mp3/${ARCHIVE_BASE_NAME}-free-archive.zip"

    if [ ! -f "$ZIP_FREE" ] || [ "$OVERWRITE" = true ]; then
        echo "         -> 📦 Packing the Free Web Archive (128kbps MP3)..."
        rm -f "$ZIP_FREE"
        
        mkdir -p web-mp3/staging_free/lyrics
        
        # Stage lower quality assets directly from the web-mp3 directory
        cp web-mp3/*.mp3 web-mp3/staging_free/ 2>/dev/null
        cp "$README_FILE" web-mp3/staging_free/
        [ -f "$ART_FILE" ] && cp "$ART_FILE" web-mp3/staging_free/
        
        if [ "$HAS_LYRICS" = true ]; then
            cp lyrics/*.md web-mp3/staging_free/lyrics/ 2>/dev/null
            [ -f "$COMBINED_LYRICS_FILE" ] && cp "$COMBINED_LYRICS_FILE" web-mp3/staging_free/
        fi
        
        pushd web-mp3/staging_free 
        "$SEVEN_ZIP_CMD" a -tzip -mx=5 "../${ARCHIVE_BASE_NAME}-free-archive.zip" * 
        popd 
        
        rm -rf web-mp3/staging_free
    else
        echo "         ⏭️  Free Web Archive (128kbps MP3) already exists! Skipping."
    fi
    
    echo "   📦 HARPER: Vault secure. Archives packed."
fi
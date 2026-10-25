#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 03: ALBUM PROCESSOR
# ==============================================================================
# Architecture & Purpose:
# This module acts as the primary orchestrator for individual album processing.
# It scans the directory tree for `album.json` files, sorts them chronologically
# based on their narrative timeline, and handles global album-level operations.
#
# Key Operations:
# 1. Finds and sorts all albums sequentially.
# 2. Parses album metadata and creates/appends to the Master Discography Markdown.
# 3. Downscales high-resolution cover art to 3000px for DistroKid requirements.
# 4. Generates a master `read-me.txt` for the album.
# 5. Spawns `04-track-processor.sh` for each track listed in `tracks.json`.
# 6. Waits for parallel audio processing threads to complete before proceeding.
# 7. Compiles the master combined lyric booklet.
#
# Maintenance Notes:
# - Uses `jq` extensively for JSON parsing.
# - Pushes and pops directories (`pushd`/`popd`) to maintain contextual isolation
#   while processing each album.
# ==============================================================================

echo "   🔍 HARPER: Indexing vault chronologically by Narrative Year..."
TEMP_SORTED_ALBUMS="temp_sorted_albums.txt"
> "$TEMP_SORTED_ALBUMS"

# --- MASTER DISCOGRAPHY CLEANUP BLOCK ---
# Clear out old generated Master Discography markdown files at the start of the
# chronological pass so each artist's `*-discography-and-lyrics.md` is freshly bound
# without duplicate sections.
echo "   🧹 HARPER: Refreshing Master Discography booklets..."
find "$SEARCH_PATH" -name "*-discography-and-lyrics.md" -type f -delete

# ------------------------------------------------------------------------------
# 1. Chronological Sorting Phase
# ------------------------------------------------------------------------------
# We sort by the fictional narrative year to ensure the discography is chronological
find "$SEARCH_PATH" -name "album.json" | while read album_file; do
    NARR_DATE=`jq -r '.temporalCoverage // empty' "$album_file"`
    NARR_YEAR=`echo "$NARR_DATE" | cut -c 1-4`
    # Default to far future if no date is found to push it to the bottom
    if [ -z "$NARR_YEAR" ]; then NARR_YEAR="9999"; fi
    
    album_dir=`dirname "$album_file"`
    # Only index if there is a corresponding tracks.json
    if [ -f "$album_dir/tracks.json" ]; then
        echo "$NARR_YEAR|$album_dir/tracks.json" >> "$TEMP_SORTED_ALBUMS"
    fi
done

# Sort numerically by year, then extract the file path (using process substitution so the loop executes in the main shell and preserves ERRORLEVEL state)
while read -r tracks_file; do
    
    album_dir=`dirname "$tracks_file"`
    # Context switch into the specific album directory
    pushd "$album_dir" > /dev/null
    
    ALBUM_JSON="album.json"
    ART_FILE="album-art.jpg"

    # Failsafe abort if the file disappeared mid-run
    if [ ! -f "$ALBUM_JSON" ]; then
        popd > /dev/null
        continue
    fi
    
    # --------------------------------------------------------------------------
    # 2. Metadata Extraction
    # --------------------------------------------------------------------------
    ALBUM_ARTIST=`jq -r '.byArtist.name // empty' "$ALBUM_JSON"`
    ALBUM_NAME=`jq -r '.name // empty' "$ALBUM_JSON"`
    GENRE=`jq -r '.genre // empty' "$ALBUM_JSON"`
    ALBUM_DISTRO=`jq -r '.publisher.name // "DistroKid"' "$ALBUM_JSON"`
    ALBUM_CLEARANCE=`jq -r '.conditionsOfAccess // "Cleared - Suno Commercial Premium License"' "$ALBUM_JSON"`
    NARRATIVE_DATE=`jq -r '.temporalCoverage // empty' "$ALBUM_JSON"`
    REAL_RELEASE_DATE=`jq -r '.datePublished // empty' "$ALBUM_JSON"`
    ALBUM_UPC=`jq -r '.gtin12 // .identifier // empty' "$ALBUM_JSON"`
    ALBUM_TYPE=`jq -r '.albumProductionType // "StudioAlbum"' "$ALBUM_JSON"`
    
    # Default to today if no real release date is provided
    if [ -z "$REAL_RELEASE_DATE" ]; then REAL_RELEASE_DATE=`date +"%Y-%m-%d"`; fi

    NARRATIVE_YEAR=`echo "$NARRATIVE_DATE" | cut -c 1-4`
    REAL_RELEASE_YEAR=`echo "$REAL_RELEASE_DATE" | cut -c 1-4`
    
    ALBUM_SLUG=`basename "$album_dir"`
    ARTIST_DIR_PATH=`dirname "$album_dir"`
    ARTIST_SLUG=`basename "$ARTIST_DIR_PATH"`

    # --------------------------------------------------------------------------
    # 2b. Scoped Rebuild & Overwrite Resolution (--rebuild [--artist] [--album])
    # --------------------------------------------------------------------------
    # Determine whether this specific album is targeted for a forced rebuild:
    # - Global Rebuild (`--rebuild` with no `--artist`): OVERWRITE=true for all albums.
    # - Artist Rebuild (`--rebuild --artist <slug>`): OVERWRITE=true for all albums by that artist.
    # - Single-Album Rebuild (`--rebuild --artist <slug> --album <slug>`): OVERWRITE=true ONLY for that album.
    # - Non-targeted albums during a scoped rebuild retain OVERWRITE=false so their
    #   metadata/ISRCs still populate the global catalogs (`metadata.json` & `master-catalog.json`)
    #   in ~1–2 seconds without re-running RealESRGAN, FFmpeg, or 7-Zip.
    if [ "$REBUILD" = true ]; then
        if [ -z "$TARGET_ARTIST" ]; then
            OVERWRITE=true
            ffmpeg_flag="-y"
        elif [ "$ARTIST_SLUG" == "$TARGET_ARTIST" ] && [ -z "$TARGET_ALBUM" ]; then
            OVERWRITE=true
            ffmpeg_flag="-y"
        elif [ "$ARTIST_SLUG" == "$TARGET_ARTIST" ] && [ "$ALBUM_SLUG" == "$TARGET_ALBUM" ]; then
            OVERWRITE=true
            ffmpeg_flag="-y"
        else
            OVERWRITE=false
            ffmpeg_flag="-n"
        fi
    else
        OVERWRITE=false
        ffmpeg_flag="-n"
    fi
    
    WEB_URL="/engine-room/artists/$ARTIST_SLUG/albums/$ALBUM_SLUG"
    # Create a safe filesystem name stripping punctuation and spaces
    SAFE_ALBUM_NAME=`echo "$ALBUM_NAME" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | tr ' ' '-'`
    ARCHIVE_BASE_NAME="$NARRATIVE_YEAR-$SAFE_ALBUM_NAME"
    CURRENT_DATETIME=`date +"%m-%d-%Y %I:%M:%S %p"`

    # --------------------------------------------------------------------------
    # 3. Master Discography Generation
    # --------------------------------------------------------------------------
    MASTER_DISCO_FILE="$ROOT_DIR/$SEARCH_PATH/$ARTIST_SLUG/$ARTIST_SLUG-discography-and-lyrics.md"

    # Initialize the file if it doesn't exist or is completely empty
    if [ ! -f "$MASTER_DISCO_FILE" ] || [ "$OVERWRITE" = true ]; then
        if ! grep -q "" "$MASTER_DISCO_FILE" 2>/dev/null; then
            echo "      📝 HARPER: Initializing Master Discography for $ALBUM_ARTIST..."
            echo "" > "$MASTER_DISCO_FILE"
            echo "# $ALBUM_ARTIST - Master Discography & Lore" >> "$MASTER_DISCO_FILE"
            echo "Compiled on: $CURRENT_DATETIME" >> "$MASTER_DISCO_FILE"
            echo "" >> "$MASTER_DISCO_FILE"
        fi
    fi
    
    # Print the Album Header into the markdown
    if [ "$ALBUM_TYPE" != "StudioAlbum" ]; then
        echo "# $ALBUM_NAME ($NARRATIVE_YEAR) [$ALBUM_TYPE]" >> "$MASTER_DISCO_FILE"
    else
        echo "# $ALBUM_NAME ($NARRATIVE_YEAR)" >> "$MASTER_DISCO_FILE"
    fi
    
    # --- NEW DATE METADATA BLOCK ---
    echo "* **Narrative Era:** $NARRATIVE_YEAR" >> "$MASTER_DISCO_FILE"
    echo "* **Real-World DSP Release:** $REAL_RELEASE_DATE" >> "$MASTER_DISCO_FILE"
    echo "" >> "$MASTER_DISCO_FILE"
    # -------------------------------
    
    echo "   💿 HARPER: Processing '$ALBUM_NAME' by $ALBUM_ARTIST..."

    # Resolve decoupled Vault and Master-WAV paths in /raggiesoft-vaults (kept off DigitalOcean Spaces CDN)
    export ARTIST_VAULT_DIR="$VAULTS_ROOT/$ARTIST_SLUG"
    export MASTER_WAV_DIR="$ARTIST_VAULT_DIR/master-wav"
    export ALBUM_VAULT_DIR="$ARTIST_VAULT_DIR/$ALBUM_SLUG/vault"

    # Scaffold public CDN output directory structure in /raggiesoft-assets
    mkdir -p web-mp3 streaming-services/album-art streaming-services/lyrics streaming-services/song-metadata

    # Scaffold private local vault directory structure in /raggiesoft-vaults
    mkdir -p "$ALBUM_VAULT_DIR/mp3" "$ALBUM_VAULT_DIR/ogg" "$ALBUM_VAULT_DIR/flac" "$ALBUM_VAULT_DIR/wav" "$ALBUM_VAULT_DIR/archives"

    # --------------------------------------------------------------------------
    # 4. Album Art Optimization
    # --------------------------------------------------------------------------
    UPSCALED_ART="streaming-services/album-art/$ART_FILE"
    
    # Run RealESRGAN upscale or just copy if not available
    if [ -f "$ART_FILE" ] && [ ! -f "$UPSCALED_ART" ] && [ "$METADATA_ONLY" = false ]; then
        if [ "$USE_UPSCALER" = true ]; then
            echo "      🖼️ HARPER: Upscaling album art ($ART_FILE)..."
            if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
                MODELS_PATH="$UPSCALER_BASE/windows/models"
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                MODELS_PATH="$UPSCALER_BASE/macos/models"
            else
                MODELS_PATH="$UPSCALER_BASE/ubuntu/models"
            fi
            
            # Additional args for iGPU safe mode
            UPSCALER_ARGS=""
            if [ "$IGPU_DETECTED" = true ]; then
                UPSCALER_ARGS="-t 100"
            fi
            
            "$UPSCALER_CMD" -n realesrgan-x4plus -i "$ART_FILE" -o "$UPSCALED_ART" -s 4 -m "$MODELS_PATH" -f jpg $UPSCALER_ARGS > /dev/null 2>&1
        else
            echo "      🖼️ HARPER: Copying album art (Upscaler disabled)..."
            cp "$ART_FILE" "$UPSCALED_ART"
        fi
    elif [ -f "$ART_FILE" ] && [ "$OVERWRITE" = true ]; then
        if [ "$USE_UPSCALER" = true ]; then
            echo "      🖼️ HARPER: Re-upscaling album art ($ART_FILE)..."
            if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
                MODELS_PATH="$UPSCALER_BASE/windows/models"
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                MODELS_PATH="$UPSCALER_BASE/macos/models"
            else
                MODELS_PATH="$UPSCALER_BASE/ubuntu/models"
            fi
            
            # Additional args for iGPU safe mode
            UPSCALER_ARGS=""
            if [ "$IGPU_DETECTED" = true ]; then
                UPSCALER_ARGS="-t 100"
            fi
            
            "$UPSCALER_CMD" -n realesrgan-x4plus -i "$ART_FILE" -o "$UPSCALED_ART" -s 4 -m "$MODELS_PATH" -f jpg $UPSCALER_ARGS > /dev/null 2>&1
        else
            echo "      🖼️ HARPER: Re-copying album art (Upscaler disabled)..."
            cp "$ART_FILE" "$UPSCALED_ART"
        fi
    fi

    # DistroKid rejects album art larger than ~3000px square. Downscale if necessary.
    if [ -f "$UPSCALED_ART" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS native sips utility
            CURRENT_WIDTH=`sips -g pixelWidth "$UPSCALED_ART" | tail -n1 | awk '{print $2}'`
            if [ -n "$CURRENT_WIDTH" ] && [ "$CURRENT_WIDTH" -gt 3000 ]; then
                echo "      📏 HARPER: Downscaling art from "$CURRENT_WIDTH"px to DistroKid optimal (3000px)..."
                sips -Z 3000 "$UPSCALED_ART" > /dev/null 2>&1
            fi
        elif command -v identify &> /dev/null && command -v mogrify &> /dev/null; then
            # Imagemagick fallback for Linux CI/CD environments
            CURRENT_WIDTH=`identify -format "%w" "$UPSCALED_ART" 2>/dev/null`
            if [ -n "$CURRENT_WIDTH" ] && [ "$CURRENT_WIDTH" -gt 3000 ]; then
                echo "      📏 HARPER: Downscaling art from "$CURRENT_WIDTH"px to DistroKid optimal (3000px)..."
                mogrify -resize 3000x3000\> "$UPSCALED_ART"
            fi
        fi
    fi

    # Format the FFmpeg parameter for injecting album art into track metadata
    if [ ! -f "$ART_FILE" ]; then
        export ART_FILE_PARAM=""
    else
        export ART_FILE_PARAM="-i $ART_FILE -map 0:a -map 1:v -codec:v mjpeg -disposition:v attached_pic"
    fi

    HAS_LYRICS=false
    if [ -d "lyrics" ]; then HAS_LYRICS=true; fi

    # --------------------------------------------------------------------------
    # 5. Master Read-Me Generation
    # --------------------------------------------------------------------------
    README_FILE="read-me.txt"
    {
        echo "=================================================================="
        echo "  $ALBUM_NAME ($NARRATIVE_YEAR)"
        echo "  by $ALBUM_ARTIST"
        echo "  Published by Engine Room Records"
        echo "=================================================================="
        echo "Genre: $GENRE"
        if [ -n "$ALBUM_UPC" ]; then echo "UPC / Barcode:$ALBUM_UPC"; fi
        echo "Label Website: https://engineroom.raggiesoft.com"
        echo "Album URL: https://music.raggiesoft.com/artists/$ARTIST_SLUG/$ALBUM_SLUG"
        echo ""
        echo "LICENSE & COPYRIGHT:"
        echo "This work is licensed under Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)."
        echo "Full License Details: https://corporate.raggiesoft.com/licensing"
        echo "Copyright (c) $REAL_RELEASE_YEAR Michael P. Ragsdale / RaggieSoft."
        echo ""
        echo "PRODUCTION DISCLAIMER:"
        echo "Audio Generation: Suno."
        echo "AI Elements: Vocals, Instrumentation, Composition."
        echo "Human Elements: Lyrics, Narrative Lore."
        echo "Commercial Rights Cleared via Commercial-Tier Suno Premium."
        echo ""
        echo "TRACKLIST:"
    } > "$README_FILE"

    # --------------------------------------------------------------------------
    # 6. Track Processing Loop (Sub-Module)
    # --------------------------------------------------------------------------
    declare -a PIDS=()
    ALBUM_MINTED_NEW_ISRC=false

    # Loop through the tracks array in tracks.json and spawn the track processor
    while read -r track_json; do
        source "$MODULE_DIR/04-track-processor.sh"
    done < <(jq -c 'if type == "array" then .[] else .tracks[] end' "tracks.json")

    # --------------------------------------------------------------------------
    # 7. Thread Pool Synchronization
    # --------------------------------------------------------------------------
    # Wait for all parallel background FFmpeg processes to finish before zipping
    # Array length logic rewritten safely for bash compatibility
    ARRAY_LENGTH=`echo ${#PIDS[@]}`
    if [ "$ARRAY_LENGTH" -gt 0 ]; then
        echo "      ⏳ HARPER: Waiting for background audio rendering pool to finalize..."
        for pid in "${PIDS[@]}"; do
            wait "$pid"
            EXIT_CODE=$?
            if [ $EXIT_CODE -ne 0 ]; then
                echo "🛑 HARPER FATAL ERROR: Audio processing crashed on PID $pid (ERRORLEVEL=${ERR_AUDIO_TRANSCODE_FAILED:-2})!"
                HARPER_AUDIO_ERRORS=$((HARPER_AUDIO_ERRORS + 1))
                exit "${ERR_AUDIO_TRANSCODE_FAILED:-2}"
            fi
        done
        echo "      ✅ HARPER: All multi-tier audio verified."
    fi

    # --------------------------------------------------------------------------
    # 8. Master Lyric Booklet Generation
    # --------------------------------------------------------------------------
    if [ "$HAS_LYRICS" = true ]; then
        COMBINED_LYRICS_FILE="$SAFE_ALBUM_NAME.md"
        
        if [ ! -f "$COMBINED_LYRICS_FILE" ] || [ "$OVERWRITE" = true ]; then
            echo "      📝  HARPER: Binding the master lyric booklet ($COMBINED_LYRICS_FILE)..."
            echo "" > "$COMBINED_LYRICS_FILE"
            echo "" >> "$COMBINED_LYRICS_FILE"

            # Re-read tracks.json to ensure correct ordering when appending lyrics
            jq -c 'if type == "array" then .[] else .tracks[] end' "tracks.json" | while read -r track_json_booklet; do
                FILE_BASE_BOOKLET=`echo "$track_json_booklet" | jq -r '.fileName'`
                LYRIC_MD_BOOKLET="lyrics/$FILE_BASE_BOOKLET.md"
                
                if [ -f "$LYRIC_MD_BOOKLET" ]; then
                    echo "***" >> "$COMBINED_LYRICS_FILE"
                    echo "### **$FILE_BASE_BOOKLET.md**" >> "$COMBINED_LYRICS_FILE"
                    echo "***" >> "$COMBINED_LYRICS_FILE"
                    echo "" >> "$COMBINED_LYRICS_FILE"
                    cat "$LYRIC_MD_BOOKLET" >> "$COMBINED_LYRICS_FILE"
                    echo "" >> "$COMBINED_LYRICS_FILE"
                    echo "" >> "$COMBINED_LYRICS_FILE"
                fi
            done
        else
            echo "      ⏭️  Master lyric booklet already bound! Fast-forwarding."
        fi
    fi

    # Pass execution down to the archive generator module
    source "$MODULE_DIR/05-archiver.sh"
    
    rm "$README_FILE"
    popd > /dev/null
done < <(sort -n "$TEMP_SORTED_ALBUMS" | cut -d'|' -f2)
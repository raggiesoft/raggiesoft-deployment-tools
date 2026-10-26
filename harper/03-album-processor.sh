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
# Clear out old generated Master Discography and DSP Upload Guide markdown files
# at the start of the chronological pass so each artist's booklets are freshly bound
# without duplicate sections.
echo "   🧹 HARPER: Refreshing Master Discography & DSP Upload Guides..."
find "$SEARCH_PATH" -name "*-discography-and-lyrics.md" -type f -delete
find "$SEARCH_PATH" -name "*-dsp-upload-guide.md" -type f -delete

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

    # --------------------------------------------------------------------------
    # 8b. Album-Level DSP Upload Reference Sheet Generation (DistroKid)
    # --------------------------------------------------------------------------
    # Generates `dsp-upload-sheet.md` directly inside the album folder (and mirrors
    # it to `streaming-services/dsp-upload-sheet.md`), plus appends to the artist-level
    # `$ARTIST_SLUG-dsp-upload-guide.md` rollup so the producer has a clean Artist -> Album
    # -> Track reference sheet with separated `Name` and `Version` fields ready at the
    # distributor upload screen.
    export DSP_SHEET_FILE="dsp-upload-sheet.md"
    export ARTIST_DSP_GUIDE="$ROOT_DIR/$SEARCH_PATH/$ARTIST_SLUG/$ARTIST_SLUG-dsp-upload-guide.md"

    echo "      📋 HARPER: Generating DSP Upload Reference Sheet ($DSP_SHEET_FILE)..."
    node -e '
      const fs = require("fs");
      const path = require("path");

      const albumJson = JSON.parse(fs.readFileSync("album.json", "utf8"));
      const rawTracks = JSON.parse(fs.readFileSync("tracks.json", "utf8"));
      const tracks = Array.isArray(rawTracks) ? rawTracks : (rawTracks.tracks || []);

      const artistName = (albumJson.byArtist && albumJson.byArtist.name) || process.env.ALBUM_ARTIST || "Unknown Artist";
      const albumName = albumJson.name || process.env.ALBUM_NAME || "Unknown Album";
      const albumTypeRaw = albumJson.albumProductionType || "StudioAlbum";
      const isLiveAlbum = albumTypeRaw.toLowerCase().includes("live");
      const isCompilation = albumTypeRaw.toLowerCase().includes("compilation");
      const isSoundtrack = albumTypeRaw.toLowerCase().includes("soundtrack");
      const releaseTypeLabel = isLiveAlbum
        ? "Live Album"
        : isCompilation
          ? "Compilation / Anthology"
          : isSoundtrack
            ? "Soundtrack Album"
            : "Studio Album";

      const genre = Array.isArray(albumJson.genre) ? albumJson.genre.join(", ") : (albumJson.genre || "");
      const narrativeDate = albumJson.temporalCoverage || "";
      const realReleaseDate = albumJson.datePublished || process.env.REAL_RELEASE_DATE || "";
      const upc = albumJson.gtin12 || albumJson.identifier || "";
      const dspExempt = Boolean(albumJson.dspExempt);
      const dspNotice = albumJson.dspNotice || "";
      const albumVaultDir = process.env.ALBUM_VAULT_DIR || "vault";
      const masterWavDir = process.env.MASTER_WAV_DIR || "../../master-wav";

      function parseDspTitleAndVersion(rawTitle, explicitVersion) {
        let title = (rawTitle || "").trim();
        const versions = [];
        const featured = [];

        if (explicitVersion && String(explicitVersion).trim()) {
          versions.push(String(explicitVersion).trim());
        }

        // 1. Extract bracketed descriptors: [Full Suite], [Radio Edit], [Japanese Version], [English Version]
        title = title.replace(/\s*\[([^\]]+)\]/g, (_, inner) => {
          const val = inner.trim();
          if (val && !versions.includes(val)) versions.push(val);
          return "";
        });

        // 2. Extract parenthetical version/demo/mix/live/edit/featured descriptors
        title = title.replace(/\s*\(([^)]+)\)/g, (fullMatch, inner) => {
          const cleanInner = inner.trim();
          const lower = cleanInner.toLowerCase();

          // Handle featured artist or combined mix + featured artist
          if (lower.includes("feat.") || lower.includes("ft.")) {
            const parts = cleanInner.split(/\s*(?:—|--|-|,)?\s*(?:feat\.|ft\.)\s*/i);
            if (parts[0] && parts[0].trim() && !versions.includes(parts[0].trim())) {
              versions.push(parts[0].trim());
            }
            if (parts[1] && parts[1].trim()) {
              featured.push(parts[1].trim());
            }
            return "";
          }

          if (
            lower.startsWith("live") ||
            lower.includes("demo") ||
            lower.includes("mix") ||
            lower.includes("sketch") ||
            lower.includes("alternate") ||
            lower.includes("radio edit") ||
            lower === "edit" ||
            lower.endsWith(" edit") ||
            lower.includes("full suite") ||
            lower.includes("b-side") ||
            lower.includes("extended") ||
            lower.includes("remaster") ||
            lower.includes("version") ||
            lower === "instrumental" ||
            /^\d{4}\s+studio$/i.test(cleanInner)
          ) {
            if (!versions.includes(cleanInner)) versions.push(cleanInner);
            return "";
          }

          return fullMatch;
        });

        title = title.trim();

        // 3. On Live Albums, DistroKid requires the live concert identifier
        // in the Version field rather than the main song title.
        if (isLiveAlbum && !versions.some((v) => v.toLowerCase().includes("live"))) {
          versions.unshift(albumName);
        }

        const versionStr = versions.length > 0 ? versions.join(" - ") : "";
        const taggedTitle = versionStr ? `${title} (${versionStr})` : title;

        return {
          name: title,
          version: versionStr || "None (Leave Blank on DSP)",
          taggedTitle,
          featured: featured.length > 0 ? featured.join(", ") : ""
        };
      }

      const discNumbers = new Set(tracks.map((t) => t.disc || 1));
      const isMultiDisc = discNumbers.size > 1;

      let readyCount = 0;
      const trackEntries = tracks.map((t, idx) => {
        const parsed = parseDspTitleAndVersion(t.title || "", t.version || "");
        const fileBase = t.fileName || `${t.disc || 1}-${String(t.track || idx + 1).padStart(2, "0")}`;
        const masterRel = t.masterWavPath || "";
        const sourceWavPath = masterRel ? path.join(masterWavDir, `${masterRel}.wav`) : "";
        const vaultWavPath = path.join(albumVaultDir, "wav", `${fileBase}.wav`);
        const hasAudioMaster = Boolean(
          (sourceWavPath && fs.existsSync(sourceWavPath)) ||
          (vaultWavPath && fs.existsSync(vaultWavPath))
        );
        if (hasAudioMaster) readyCount += 1;

        const cleanLyricsPath = `streaming-services/lyrics/${fileBase}.txt`;
        let isInstrumental = false;
        if (fs.existsSync(cleanLyricsPath)) {
          const txt = fs.readFileSync(cleanLyricsPath, "utf8").trim();
          isInstrumental = txt.length === 0;
        } else if (fs.existsSync(`lyrics/${fileBase}.md`)) {
          const md = fs.readFileSync(`lyrics/${fileBase}.md`, "utf8");
          isInstrumental = !md.includes("**LYRICS:**");
        } else {
          isInstrumental = true;
        }

        return {
          overallNum: idx + 1,
          disc: t.disc || 1,
          trackNum: t.track || idx + 1,
          rawTitle: parsed.taggedTitle,
          name: parsed.name,
          version: parsed.version,
          taggedTitle: parsed.taggedTitle,
          featured: parsed.featured,
          isrc: (t.isrc || "").trim() || "Pending (Auto-mints QTAHP code when WAV is in master-wav)",
          duration: (t.duration || "").trim() || "In Studio",
          hasAudioMaster,
          vaultWavPath,
          cleanLyricsPath: fs.existsSync(cleanLyricsPath) ? cleanLyricsPath : `lyrics/${fileBase}.md`,
          isInstrumental
        };
      });

      const lines = [];
      lines.push(`# ${artistName}`);
      lines.push(`## ${albumName}`);
      lines.push("");
      lines.push("> **DSP Upload Quick-Reference Sheet (DistroKid)**");
      lines.push("> Designed for side-by-side use on the distributor upload screen. All version, live venue, demo, mix, and edit suffixes have been stripped from `Name` and placed into `Version` to satisfy strict DSP title validation.");
      lines.push("");
      lines.push("### Album-Level Upload Settings");
      lines.push(`* **Artist / Band Name:** \`${artistName}\``);
      lines.push(`* **Album Title:** \`${albumName}\``);
      lines.push(`* **Release Type:** \`${releaseTypeLabel}\` (\`${albumTypeRaw}\`)`);
      lines.push(`* **Total Tracks:** \`${tracks.length}\` (\`${readyCount}\` WAV Masters Ready / \`${tracks.length - readyCount}\` In Studio)`);
      lines.push(`* **Record Label:** \`Engine Room Records\``);
      lines.push(`* **Primary Genre:** \`${genre}\``);
      lines.push(`* **In-Universe Release Date:** \`${narrativeDate || "N/A"}\``);
      lines.push(`* **Real-World DSP Release Date:** \`${realReleaseDate || "TBD"}\``);
      lines.push(`* **Album UPC / GTIN-12:** \`${upc || "None (Use Distributor-Assigned UPC)"}\``);
      if (dspExempt) {
        lines.push(`* **DSP Exemption Status:** \`EXEMPT FROM COMMERCIAL DSPs\` ${dspNotice ? `— *${dspNotice}*` : ""}`);
      }
      lines.push(`* **3000×3000 Cover Art File:** \`streaming-services/album-art/album-art.jpg\``);
      lines.push(`* **Songwriter / Lyricist (Real Human Name):** \`Michael P. Ragsdale\``);
      lines.push(`* **P-Line & C-Line (\`℗\` & \`©\`):** \`${(realReleaseDate || "2026").slice(0, 4)} Engine Room Records / Michael P. Ragsdale\``);
      lines.push(`* **AI Disclosure:** \`Yes — Music & Audio (Human-Authored Lyrics & Narrative Lore)\``);
      lines.push(`* **Content ID / Social Media Pack:** \`DO NOT SELECT / LEAVE UNCHECKED\` *(Zero Content-ID Ambush Guarantee)*`);
      lines.push("");
      lines.push("---");
      lines.push("");
      lines.push(`### Songs (${tracks.length} Tracks)`);
      lines.push("");

      for (const item of trackEntries) {
        const headingPrefix = isMultiDisc
          ? `${item.overallNum}. [Disc ${item.disc} • Track ${item.trackNum}] ${item.name}`
          : `${item.trackNum}. ${item.name}`;
        lines.push(headingPrefix);
        lines.push(`* **Name:** ${item.name}`);
        lines.push(`* **Version:** ${item.version}`);
        lines.push(`* **ID3 / Vorbis Tagged Title:** \`${item.taggedTitle}\``);
        if (item.featured) {
          lines.push(`* **Featured Artist:** ${item.featured}`);
        }
        lines.push(`* **ISRC:** ${item.isrc}`);
        lines.push(`* **Duration:** ${item.duration} • **Instrumental:** ${item.isInstrumental ? "Yes" : "No"} • **Explicit:** No`);
        lines.push(`* **Songwriter (Lyricist):** Michael P. Ragsdale`);
        lines.push(`* **WAV File:** \`${item.vaultWavPath}\` ${item.hasAudioMaster ? "(✅ Ready)" : "(⏳ In Studio)"}`);
        if (!item.isInstrumental) {
          lines.push(`* **Clean DSP Lyrics:** \`${item.cleanLyricsPath}\``);
        }
        lines.push("");
      }

      const fullContent = lines.join("\n");
      fs.writeFileSync("dsp-upload-sheet.md", fullContent, "utf8");
      if (fs.existsSync("streaming-services")) {
        fs.writeFileSync("streaming-services/dsp-upload-sheet.md", fullContent, "utf8");
      }

      // Append concise Artist -> Album -> Track section to the artist-level rollup guide
      const artistGuidePath = process.env.ARTIST_DSP_GUIDE;
      if (artistGuidePath) {
        const guideLines = [];
        if (!fs.existsSync(artistGuidePath) || fs.readFileSync(artistGuidePath, "utf8").trim().length === 0) {
          guideLines.push(`# ${artistName}`);
          guideLines.push("");
          guideLines.push("> **Master DSP Upload Reference Guide (DistroKid)**");
          guideLines.push("> Chronological `Artist -> Album -> Track` upload reference sheet generated by Harper.");
          guideLines.push("");
        }
        guideLines.push(`## ${albumName} (${(narrativeDate || "").slice(0, 4) || "TBD"}) — ${releaseTypeLabel}`);
        guideLines.push(`* **Album Folder:** \`${path.basename(process.cwd())}\` • **UPC:** \`${upc || "None"}\` • **Genre:** \`${genre}\``);
        guideLines.push("");
        for (const item of trackEntries) {
          const numLabel = isMultiDisc ? `${item.overallNum} (D${item.disc}-T${item.trackNum})` : `${item.trackNum}`;
          guideLines.push(`${numLabel}. ${item.name}`);
          guideLines.push(`* Name: ${item.name}`);
          guideLines.push(`* Version: ${item.version}`);
          guideLines.push(`* ID3 / Vorbis Tag: ${item.taggedTitle}`);
          if (item.featured) {
            guideLines.push(`* Featured Artist: ${item.featured}`);
          }
          guideLines.push(`* ISRC: ${item.isrc}`);
          guideLines.push("");
        }
        guideLines.push("---");
        guideLines.push("");
        fs.appendFileSync(artistGuidePath, guideLines.join("\n"), "utf8");
      }
    '

    # Pass execution down to the archive generator module
    source "$MODULE_DIR/05-archiver.sh"
    
    rm "$README_FILE"
    popd > /dev/null
done < <(sort -n "$TEMP_SORTED_ALBUMS" | cut -d'|' -f2)
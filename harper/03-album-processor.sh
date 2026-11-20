#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 03: ALBUM PROCESSOR (`harper/03-album-processor.sh`)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Module 03 is Harper's outer loop! It visits every album across all Engine
#   Room Records artists in chronological in-story order (`temporalCoverage`)
#   and coordinates the per-album assembly line:
#     1. Cleans stale `*-discography-and-lyrics.md` and `*-dsp-upload-guide.md`
#        rollups so they rebuild cleanly in chronological order without duplicates.
#     2. Reads `album.json` via `jq` and decides whether `OVERWRITE` applies to
#        this specific album (making `--artist` / `--album` scoped rebuilds fast!).
#     3. Upscales `album-art.jpg` via Real-ESRGAN (4x) and caps it at `3000x3000`
#        pixels (`sips` on macOS / `mogrify` on Linux) to satisfy DistroKid's upload cap.
#     4. Loops through `tracks.json`, sourcing `04-track-processor.sh` for each song,
#        and waits (`wait "$pid"`) for all background FFmpeg encoders to finish.
#     5. Binds the combined Markdown lyric booklet (`<safe-album-name>.md`), runs
#        an inline Node.js helper to split song `Name` vs. `Version` for DistroKid
#        (`dsp-upload-sheet.md`), and sources `05-archiver.sh` to pack the 6 ZIP/7z tiers!
#
# BASH PROCESS SUBSTITUTION (`done < <(...)`) — CRITICAL 100-LEVEL CONCEPT:
#   Look at the bottom of the main loop (`done < <(sort -n ...)`).
#   In Bash, if you write `sort ... | while read ...; do ... done`, the pipe `|`
#   runs the `while` loop inside a **child subshell**, meaning any changes to
#   `HARPER_AUDIO_ERRORS` or `HARPER_ARCHIVE_ERRORS` vanish when the loop ends!
#   Writing `while read ...; do ... done < <(sort ...)` ("process substitution")
#   feeds `sort`'s output into the loop WITHOUT creating a subshell for the loop body!
# ==============================================================================

echo "   🔍 HARPER: Indexing vault chronologically by Narrative Year..."
TEMP_SORTED_ALBUMS="temp_sorted_albums.txt"
> "$TEMP_SORTED_ALBUMS"

# --- MASTER DISCOGRAPHY CLEANUP BLOCK ---
# Clear out old generated Master Discography and DSP Upload Guide markdown files
# at the start of the chronological pass so each artist's booklets are freshly bound
# without duplicate sections (`find ... -delete` deletes matching files in one pass).
echo "   🧹 HARPER: Refreshing Master Discography & DSP Upload Guides..."
find "$SEARCH_PATH" -name "*-discography-and-lyrics.md" -type f -delete
find "$SEARCH_PATH" -name "*-dsp-upload-guide.md" -type f -delete

# ------------------------------------------------------------------------------
# 1. Chronological Sorting Phase
# ------------------------------------------------------------------------------
# Collect `NARR_YEAR|path/to/tracks.json` lines so `sort -n` orders albums from oldest story year to newest.
# (Note: Backticks `` `cmd` `` are classic Bourne-shell command substitution, equivalent to `$(cmd)`.)
find "$SEARCH_PATH" -name "album.json" | while read album_file; do
    NARR_DATE=`jq -r '.temporalCoverage // empty' "$album_file"`
    NARR_YEAR=`echo "$NARR_DATE" | cut -c 1-4`
    # Default to sentinel year `9999` if no date is found so undated items sort last
    if [ -z "$NARR_YEAR" ]; then NARR_YEAR="9999"; fi
    
    album_dir=`dirname "$album_file"`
    # Only index valid album directories that also contain a `tracks.json` manifest
    if [ -f "$album_dir/tracks.json" ]; then
        echo "$NARR_YEAR|$album_dir/tracks.json" >> "$TEMP_SORTED_ALBUMS"
    fi
done

# Sort numerically (`-n`) by year, strip the `YEAR|` prefix (`cut -d'|' -f2` keeps field #2),
# and iterate in the main shell via process substitution (`< <(...)`):
while read -r tracks_file; do
    
    album_dir=`dirname "$tracks_file"`
    # `pushd` switches our working directory into `$album_dir` and pushes the old
    # directory onto a stack so `popd` at the end of the loop always returns cleanly!
    pushd "$album_dir" > /dev/null
    
    ALBUM_JSON="album.json"
    ART_FILE="album-art.jpg"

    # Failsafe guard if `album.json` disappeared mid-run
    if [ ! -f "$ALBUM_JSON" ]; then
        popd > /dev/null
        continue
    fi
    
    # --------------------------------------------------------------------------
    # 2. Metadata Extraction (`jq -r` Raw JSON Queries with `//` Fallbacks)
    # --------------------------------------------------------------------------
    ALBUM_ARTIST=`jq -r '.byArtist.name // empty' "$ALBUM_JSON"`
    ALBUM_NAME=`jq -r '.name // empty' "$ALBUM_JSON"`
    GENRE=`jq -r '.genre // empty' "$ALBUM_JSON"`
    ALBUM_DISTRO=`jq -r '.publisher.name // "DistroKid"' "$ALBUM_JSON"`
    ALBUM_CLEARANCE=`jq -r '.conditionsOfAccess // "Cleared - Suno Commercial Premium License"' "$ALBUM_JSON"`
    NARRATIVE_DATE=`jq -r '.temporalCoverage // empty' "$ALBUM_JSON"`
    REAL_RELEASE_DATE=`jq -r '.datePublished // empty' "$ALBUM_JSON"`
    # `.gtin12 // .identifier // empty` checks `gtin12` first, then `identifier`, then empty string
    ALBUM_UPC=`jq -r '.gtin12 // .identifier // empty' "$ALBUM_JSON"`
    ALBUM_TYPE=`jq -r '.albumProductionType // "StudioAlbum"' "$ALBUM_JSON"`
    
    # Default to today (`YYYY-MM-DD`) if no real-world release date is provided
    if [ -z "$REAL_RELEASE_DATE" ]; then REAL_RELEASE_DATE=`date +"%Y-%m-%d"`; fi

    NARRATIVE_YEAR=`echo "$NARRATIVE_DATE" | cut -c 1-4`
    REAL_RELEASE_YEAR=`echo "$REAL_RELEASE_DATE" | cut -c 1-4`
    
    ALBUM_SLUG=`basename "$album_dir"`
    ARTIST_DIR_PATH=`dirname "$album_dir"`
    ARTIST_SLUG=`basename "$ARTIST_DIR_PATH"`

    # --------------------------------------------------------------------------
    # 2b. Scoped Rebuild & Overwrite Resolution (--rebuild [--artist] [--album])
    # --------------------------------------------------------------------------
    # Why Harper still loops through non-targeted albums with `OVERWRITE=false`:
    # Because `06-finalize.sh` rebuilds the global `metadata.json` and `master-catalog.json`
    # across ALL artists! Setting `OVERWRITE=false` on non-targeted albums lets them
    # contribute their JSON rows in milliseconds while skipping Real-ESRGAN, FFmpeg, and 7-Zip!
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
    # Build a URL/filename-safe slug via Unix `tr` ("translate characters"):
    #   1. `tr '[:upper:]' '[:lower:]'` -> lowercase all letters
    #   2. `tr -d '[:punct:]'`          -> delete (`-d`) punctuation marks
    #   3. `tr ' ' '-'`                 -> turn spaces into hyphens
    SAFE_ALBUM_NAME=`echo "$ALBUM_NAME" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | tr ' ' '-'`
    ARCHIVE_BASE_NAME="$NARRATIVE_YEAR-$SAFE_ALBUM_NAME"
    CURRENT_DATETIME=`date +"%m-%d-%Y %I:%M:%S %p"`

    # --------------------------------------------------------------------------
    # 3. Master Discography Generation (`<artist>-discography-and-lyrics.md`)
    # --------------------------------------------------------------------------
    MASTER_DISCO_FILE="$SEARCH_PATH/$ARTIST_SLUG/$ARTIST_SLUG-discography-and-lyrics.md"

    # Write the top-of-booklet artist title header only once (when the file doesn't exist or is 0 lines)
    if [ ! -f "$MASTER_DISCO_FILE" ] || [ "$OVERWRITE" = true ]; then
        if ! grep -q "" "$MASTER_DISCO_FILE" 2>/dev/null; then
            echo "      📝 HARPER: Initializing Master Discography for $ALBUM_ARTIST..."
            echo "" > "$MASTER_DISCO_FILE"
            echo "# $ALBUM_ARTIST - Master Discography & Lore" >> "$MASTER_DISCO_FILE"
            echo "Compiled on: $CURRENT_DATETIME" >> "$MASTER_DISCO_FILE"
            echo "" >> "$MASTER_DISCO_FILE"
        fi
    fi
    
    # Append (`>>`) this album's section heading into the artist's Master Discography
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

    # Resolve decoupled Vault and Master-WAV paths in `/raggiesoft-vaults` (kept off DigitalOcean Spaces CDN)
    export ARTIST_VAULT_DIR="$VAULTS_ROOT/$ARTIST_SLUG"
    export MASTER_WAV_DIR="$ARTIST_VAULT_DIR/master-wav"
    export ALBUM_VAULT_DIR="$ARTIST_VAULT_DIR/$ALBUM_SLUG/vault"

    # Scaffold public CDN output folders (`mkdir -p` creates nested folders idempotently)
    mkdir -p web-mp3 streaming-services/album-art streaming-services/lyrics streaming-services/song-metadata

    # Scaffold private local vault folders in `/raggiesoft-vaults`
    mkdir -p "$ALBUM_VAULT_DIR/mp3" "$ALBUM_VAULT_DIR/ogg" "$ALBUM_VAULT_DIR/flac" "$ALBUM_VAULT_DIR/wav" "$ALBUM_VAULT_DIR/archives"

    # --------------------------------------------------------------------------
    # 4. Album Art Optimization (Real-ESRGAN 4x Upscale -> 3000px DistroKid Cap)
    # --------------------------------------------------------------------------
    UPSCALED_ART="streaming-services/album-art/$ART_FILE"
    
    # Upscale raw `album-art.jpg` (`-s 4` = 4x scale, `-n realesrgan-x4plus` neural model) when missing or overwriting
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

    # DistroKid & Apple Music optimal cover spec is `3000x3000` (4x upscaling a 1024px image produces 4096px).
    # On macOS, Apple's built-in `sips -Z 3000` resizes the longest edge down to 3000px while keeping aspect ratio!
    if [ -f "$UPSCALED_ART" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            CURRENT_WIDTH=`sips -g pixelWidth "$UPSCALED_ART" | tail -n1 | awk '{print $2}'`
            if [ -n "$CURRENT_WIDTH" ] && [ "$CURRENT_WIDTH" -gt 3000 ]; then
                echo "      📏 HARPER: Downscaling art from "$CURRENT_WIDTH"px to DistroKid optimal (3000px)..."
                sips -Z 3000 "$UPSCALED_ART" > /dev/null 2>&1
            fi
        elif command -v identify &> /dev/null && command -v mogrify &> /dev/null; then
            # ImageMagick fallback on Linux (`3000x3000\>` means "shrink only if larger than 3000px")
            CURRENT_WIDTH=`identify -format "%w" "$UPSCALED_ART" 2>/dev/null`
            if [ -n "$CURRENT_WIDTH" ] && [ "$CURRENT_WIDTH" -gt 3000 ]; then
                echo "      📏 HARPER: Downscaling art from "$CURRENT_WIDTH"px to DistroKid optimal (3000px)..."
                mogrify -resize 3000x3000\> "$UPSCALED_ART"
            fi
        fi
    fi

    # Prepare `$ART_FILE_PARAM` for `02-audio-engine.sh`:
    #   - `-i album-art.jpg` : Adds the JPEG as FFmpeg input #1 (the WAV is input #0).
    #   - `-map 0:a`         : Maps the audio stream from input #0.
    #   - `-map 1:v`         : Maps the image ("video") stream from input #1.
    #   - `-codec:v mjpeg -disposition:v attached_pic`: Marks the JPEG as embedded album cover art!
    if [ ! -f "$ART_FILE" ]; then
        export ART_FILE_PARAM=""
    else
        export ART_FILE_PARAM="-i $ART_FILE -map 0:a -map 1:v -codec:v mjpeg -disposition:v attached_pic"
    fi

    HAS_LYRICS=false
    if [ -d "lyrics" ]; then HAS_LYRICS=true; fi

    HAS_SUNO_PROMPTS=false
    if [ -d "suno-prompts" ]; then HAS_SUNO_PROMPTS=true; fi

    # --------------------------------------------------------------------------
    # 5. Master Read-Me Generation (`read-me.txt` bundled into all 6 ZIP/7z archives)
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
        echo "PRODUCTION DISCLAIMER & CC BY-SA 4.0 RECREATION PROMPTS:"
        echo "Audio Generation: Suno."
        echo "AI Elements: Vocals, Instrumentation, Composition."
        echo "Human Elements: Lyrics, Narrative Lore."
        echo "Commercial Rights Cleared via Commercial-Tier Suno Premium."
        echo "Open-Culture Recreation (/suno-prompts/): Because this release is licensed under CC BY-SA 4.0,"
        echo "each song's Suno style prompt, exclusions, 75% Cover Audio Influence settings, and structural"
        echo "lyric cues are packaged in the /suno-prompts/ folder so others can study or recreate them."
        echo ""
        echo "TRACKLIST:"
    } > "$README_FILE"

    # --------------------------------------------------------------------------
    # 6. Track Processing Loop (Sources `04-track-processor.sh` per Song)
    # --------------------------------------------------------------------------
    # `declare -a PIDS=()` initializes an empty indexed array of background FFmpeg Process IDs (`$!`).
    declare -a PIDS=()
    ALBUM_MINTED_NEW_ISRC=false

    # `jq -c` emits each track object compacted onto a single line so `while read -r track_json`
    # receives one complete track JSON object per iteration (again using `< <(...)` process substitution!).
    while read -r track_json; do
        source "$MODULE_DIR/04-track-processor.sh"
    done < <(jq -c 'if type == "array" then .[] else .tracks[] end' "tracks.json")

    # --------------------------------------------------------------------------
    # 7. Thread Pool Synchronization ("Barrier Wait" Before Zipping)
    # --------------------------------------------------------------------------
    # `04-track-processor.sh` launched FFmpeg encoders asynchronously in the background (`&`).
    # We MUST `wait "$pid"` on every background Process ID in `${PIDS[@]}` before `05-archiver.sh`
    # zips the folder—otherwise 7-Zip would archive half-written audio files!
    ARRAY_LENGTH=`echo ${#PIDS[@]}`
    if [ "$ARRAY_LENGTH" -gt 0 ]; then
        echo "      ⏳ HARPER: Waiting for background audio rendering pool to finalize..."
        for pid in "${PIDS[@]}"; do
            wait "$pid"
            # `$?` captures the exact return code of `press_audio_formats` from that background PID!
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
    # 8. Master Lyric Booklet Generation (`<safe-album-name>.md`)
    # --------------------------------------------------------------------------
    if [ "$HAS_LYRICS" = true ]; then
        COMBINED_LYRICS_FILE="$SAFE_ALBUM_NAME.md"
        
        if [ ! -f "$COMBINED_LYRICS_FILE" ] || [ "$OVERWRITE" = true ]; then
            echo "      📝  HARPER: Binding the master lyric booklet ($COMBINED_LYRICS_FILE)..."
            echo "" > "$COMBINED_LYRICS_FILE"
            echo "" >> "$COMBINED_LYRICS_FILE"

            # Re-read `tracks.json` in exact album tracklist order and concatenate each `lyrics/<fileName>.md`
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
    # WHY THIS INLINE NODE.JS SCRIPT (`node -e '...'`) EXISTS:
    #   Commercial DSPs (Apple Music / Spotify via DistroKid) enforce strict title formatting:
    #   parenthetical/bracketed version tags like `(Live in Norfolk)`, `[Radio Edit]`, `(Demo)`,
    #   or `(feat. ...)` MUST be stripped out of the main song `Name` field and entered into
    #   DistroKid's separate `Version` / `Featured Artist` boxes—especially on Live Albums!
    #   This inline Node.js script parses `album.json` + `tracks.json`, separates `Name` from
    #   `Version` via regexes, checks whether each WAV master and clean lyric `.txt` is ready,
    #   writes `dsp-upload-sheet.md` (and `streaming-services/dsp-upload-sheet.md`), and appends
    #   an album summary to the artist-level `$ARTIST_SLUG-dsp-upload-guide.md`.
    export DSP_SHEET_FILE="dsp-upload-sheet.md"
    export ARTIST_DSP_GUIDE="$SEARCH_PATH/$ARTIST_SLUG/$ARTIST_SLUG-dsp-upload-guide.md"

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

    # Pass execution down to `05-archiver.sh` to bundle all 6 ZIP / `.7z` download packages
    source "$MODULE_DIR/05-archiver.sh"
    
    # Remove the temporary root `read-me.txt` now that it has been copied into all 6 archives,
    # and `popd` back out of `$album_dir` ready for the next album!
    rm "$README_FILE"
    popd > /dev/null
done < <(sort -n "$TEMP_SORTED_ALBUMS" | cut -d'|' -f2)
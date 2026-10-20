#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 04: TRACK PROCESSOR
# ==============================================================================
# Architecture & Purpose:
# Sourced in a loop by `03-album-processor.sh`. Processes a single track JSON 
# object to generate metadata sheets, append to the master discography, sanitize 
# lyrics for DSP ingestion, isolate vocals, generate VTT sync files, and spawn 
# parallel background audio encoding tasks.
#
# Key Operations:
# 1. Parses JSON for track details (Title, Disc, Number, ISRC, etc.).
# 2. Stamps Broadcast Wave Format (BWF) metadata into local master copy.
# 3. Formats and writes the DistroKid quick-copy metadata sheet.
# 4. Scrubs markdown tags from lyrics to create pure text for DSP upload.
# 5. Executes AI vocal isolation (Demucs) and forced alignment (WhisperX) for VTTs.
# 6. Spawns `press_audio_formats` asynchronously for multi-tier rendering.
#
# Maintenance Notes:
# - `$track_json` must be defined in the parent shell loop prior to sourcing.
# - Runs `demucs` and `whisperx` sequentially to prevent GPU/CPU OOM crashes.
# - Leverages `jobs -p` logic to throttle parallel FFmpeg spawns to `$MAX_JOBS`.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Metadata Extraction
# ------------------------------------------------------------------------------
FILE_BASE=`echo "$track_json" | jq -r '.fileName'`
TITLE=`echo "$track_json" | jq -r '.title'`
DISC_NUM=`echo "$track_json" | jq -r '.disc // 1'`
TRACK_NUM=`echo "$track_json" | jq -r '.track'`
SUITE_NAME=`echo "$track_json" | jq -r '.suiteName // empty'`
SUITE_TRACK=`echo "$track_json" | jq -r '.suiteTrack // empty'`

# Build tracklist entry for the album read-me
if [ -n "$SUITE_NAME" ]; then
    if [ "$SUITE_TRACK" == "1" ]; then
        echo "" >> "$README_FILE"
        echo "  --- $SUITE_NAME ---" >> "$README_FILE"
    fi
    echo "  $TRACK_NUM.$TITLE" >> "$README_FILE"
else
    echo "  $TRACK_NUM.$TITLE" >> "$README_FILE"
fi

echo "      🎙️  HARPER: Checking Track $TRACK_NUM - '$TITLE'..."

# Append to the Master Discography markdown
echo "## $TITLE" >> "$MASTER_DISCO_FILE"

LYRIC_MD_PATH="lyrics/$FILE_BASE.md"

if [ -f "$LYRIC_MD_PATH" ]; then
    # Convert internal syntax tags to standard markdown headers
    sed -e 's/\*\*LORE NOTE:\*\*/### Lore/' \
        -e 's/\*\*LYRICS:\*\*/### Lyrics/' \
        "$LYRIC_MD_PATH" >> "$MASTER_DISCO_FILE"
    echo "" >> "$MASTER_DISCO_FILE"
else
    echo "*(Instrumental / Structure-Only Track)*" >> "$MASTER_DISCO_FILE"
    echo "" >> "$MASTER_DISCO_FILE"
fi

MASTER_WAV_PATH=`echo "$track_json" | jq -r '.masterWavPath // empty'`
ISRC_CODE=`echo "$track_json" | jq -r '.isrc // empty'`
DSP_STATUS_OVERRIDE=`echo "$track_json" | jq -r '.dspStatus // empty'`

# Resolve Master WAV path early so we know if the recording exists on disk
MASTER_DIR="${MASTER_WAV_DIR:-$VAULTS_ROOT/$ARTIST_SLUG/master-wav}"
SOURCE_WAV="$MASTER_DIR/$MASTER_WAV_PATH.wav"
LOCAL_WAV="${ALBUM_VAULT_DIR:-vault}/wav/$FILE_BASE.wav"

# ------------------------------------------------------------------------------
# 1b. Official US ISRC Agency Auto-Minter (Prefix: QTAHP • Registrant ID: 185611)
# ------------------------------------------------------------------------------
# If a completed sound recording ($SOURCE_WAV exists on disk) does not yet have
# an ISRC in `tracks.json`:
# 1. First check if the identical recording (`$ARTIST_SLUG|$MASTER_WAV_PATH`)
#    already has an ISRC assigned on another album/compilation; if so, inherit it
#    to obey the US ISRC Agency Single-ISRC-Per-Recording rule.
# 2. Otherwise, mint the next sequential `QTAHP<YY><NNNNN>` code, persist it
#    directly into `tracks.json`, and register it in `$TEMP_WAV_ISRC_MAP`.
MINTED_NEW_ISRC=false
if [ -z "$ISRC_CODE" ] || [ "$ISRC_CODE" == "null" ]; then
    ISRC_CODE=""
    if [ -n "$MASTER_WAV_PATH" ] && [ -f "$TEMP_WAV_ISRC_MAP" ]; then
        EXISTING_WAV_ISRC=$(awk -F'\t' -v key="$ARTIST_SLUG|$MASTER_WAV_PATH" '$1 == key {print $2; exit}' "$TEMP_WAV_ISRC_MAP")
        if [ -n "$EXISTING_WAV_ISRC" ]; then
            ISRC_CODE="$EXISTING_WAV_ISRC"
            MINTED_NEW_ISRC=true
            ALBUM_MINTED_NEW_ISRC=true
            echo "      🔗 HARPER: Linked existing recording ISRC $ISRC_CODE for shared master '$MASTER_WAV_PATH'"
            jq --arg isrc "$ISRC_CODE" --arg file "$FILE_BASE" \
              'if type == "array" then map(if .fileName == $file then .isrc = $isrc else . end) else .tracks |= map(if .fileName == $file then .isrc = $isrc else . end) end' \
              tracks.json > tracks.json.tmp && mv tracks.json.tmp tracks.json
        fi
    fi

    if [ -z "$ISRC_CODE" ] && [ -z "$ALBUM_UPC" ] && [ -n "$MASTER_WAV_PATH" ] && [ -f "$SOURCE_WAV" ]; then
        CURR_SEQ=$(cat "$TEMP_ISRC_COUNTER_FILE" 2>/dev/null || echo "0")
        NEXT_SEQ=$((CURR_SEQ + 1))
        echo "$NEXT_SEQ" > "$TEMP_ISRC_COUNTER_FILE"
        ISRC_CODE=$(printf "%s%s%05d" "${ISRC_REGISTRANT_PREFIX:-QTAHP}" "${ISRC_YEAR_SUFFIX:-26}" "$NEXT_SEQ")
        MINTED_NEW_ISRC=true
        ALBUM_MINTED_NEW_ISRC=true
        printf "%s|%s\t%s\n" "$ARTIST_SLUG" "$MASTER_WAV_PATH" "$ISRC_CODE" >> "$TEMP_WAV_ISRC_MAP"
        echo "      🏷️  HARPER: Minted Official US ISRC Agency Code: $ISRC_CODE ($TITLE)"
        jq --arg isrc "$ISRC_CODE" --arg file "$FILE_BASE" \
          'if type == "array" then map(if .fileName == $file then .isrc = $isrc else . end) else .tracks |= map(if .fileName == $file then .isrc = $isrc else . end) end' \
          tracks.json > tracks.json.tmp && mv tracks.json.tmp tracks.json
    fi
fi

# ------------------------------------------------------------------------------
# 2. Engine Room Records Internal Catalog Routing
# ------------------------------------------------------------------------------
# Assign internal catalog prefixes based on artist persona
case "$ALBUM_ARTIST" in
    "The Stardust Engine") ROSTER_PREFIX="ERR-001" ;;
    "Fractured Prisms") ROSTER_PREFIX="ERR-002" ;;
    "The Paper Wall"|"Mirage") ROSTER_PREFIX="ERR-003" ;;
    "Firelight") ROSTER_PREFIX="ERR-004" ;;
    "The Arctic Symphony Project"|"The Winter Palace") ROSTER_PREFIX="ERR-005" ;;
    "Crimson Node") ROSTER_PREFIX="ERR-006" ;;
    "Mana Canvas") ROSTER_PREFIX="ERR-007" ;;
    "The Hoshizora Ensemble") ROSTER_PREFIX="ERR-008" ;;
    *) ROSTER_PREFIX="ERR-999" ;;
esac

FORMATTED_TRACK=`printf "%d%02d" "$DISC_NUM" "$TRACK_NUM"`
ERR_ID="$ROSTER_PREFIX-$NARRATIVE_YEAR-$FORMATTED_TRACK"

# Evaluate global release status
if [ "$ALBUM_DISTRO" == "Internal Vault" ] || [ "$DSP_STATUS_OVERRIDE" == "vault" ]; then
    RELEASE_STATUS="Vault Exclusive"
elif [ -n "$ISRC_CODE" ] && [ "$ISRC_CODE" != "null" ]; then
    RELEASE_STATUS="Released"
else
    RELEASE_STATUS="Pending DSP"
fi

# Append flat record to the temporary search catalog JSONL
jq -n -c \
    --arg err_id "$ERR_ID" \
    --arg isrc "$ISRC_CODE" \
    --arg upc "$ALBUM_UPC" \
    --arg title "$TITLE" \
    --arg artist "$ALBUM_ARTIST" \
    --arg slug "$ARTIST_SLUG" \
    --arg album "$ALBUM_NAME" \
    --arg album_type "$ALBUM_TYPE" \
    --arg album_slug "$ALBUM_SLUG" \
    --arg track_slug "$FILE_BASE" \
    --arg r_date "$REAL_RELEASE_DATE" \
    --arg status "$RELEASE_STATUS" \
    --arg owner "Michael P. Ragsdale / RaggieSoft" \
    --arg distro "$ALBUM_DISTRO" \
    --arg ai "$ALBUM_CLEARANCE" \
    --arg vocals "Synthetic / Non-Cloned" \
    '{
        err_id: $err_id, 
        isrc: $isrc, 
        albumUPC: $upc,
        trackTitle: $title, 
        albumTitle: $album, 
        albumProductionType: $album_type,
        artistPersona: $artist,
        artistSlug: $slug,
        albumSlug: $album_slug,
        trackSlug: $track_slug,
        legalOwner: $owner, 
        distributor: $distro, 
        aiClearance: $ai, 
        vocalType: $vocals, 
        realReleaseDate: $r_date, 
        status: $status
    }' >> "$ROOT_DIR/$TEMP_CATALOG_INDEX"

# ------------------------------------------------------------------------------
# 3. Master Audio Verification & BWF Stamping
# ------------------------------------------------------------------------------
MASTER_DIR="${MASTER_WAV_DIR:-$VAULTS_ROOT/$ARTIST_SLUG/master-wav}"
SOURCE_WAV="$MASTER_DIR/$MASTER_WAV_PATH.wav"
LOCAL_WAV="${ALBUM_VAULT_DIR:-vault}/wav/$FILE_BASE.wav"
RUNTIME=""

if [ ! -f "$SOURCE_WAV" ]; then 
    echo "         ⚠️  WHOA! Master tape missing from central vault: $SOURCE_WAV"
else
    # Extract track duration programmatically for JSON updates
    RUNTIME=`ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_WAV" | awk '{printf "%d:%02d\n", $1/60, $1%60}'`
    echo "      ⏱️  HARPER: Track runtime clocked at $RUNTIME"

        if [ "$METADATA_ONLY" = false ] || [ "$MINTED_NEW_ISRC" = true ]; then
        if [ ! -f "$LOCAL_WAV" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
            echo "         -> 💾 Stamping BWF Metadata (ISRC: $ISRC_CODE) and pulling $MASTER_WAV_PATH to $LOCAL_WAV..."
            mkdir -p "${ALBUM_VAULT_DIR:-vault}/wav"
            
            # Replaces the standard cp command with a lossless FFmpeg metadata pass
            # Stuffs metadata directly into the RIFF INFO and BEXT chunks of the WAV
            ffmpeg -nostdin -hide_banner -loglevel error -y -i "$SOURCE_WAV" -write_bext 1 \
            -metadata title="$TITLE" \
            -metadata artist="$ALBUM_ARTIST" \
            -metadata album="$ALBUM_NAME" \
            -metadata date="$REAL_RELEASE_YEAR" \
            -metadata track="$TRACK_NUM" \
            -metadata genre="$GENRE" \
            -metadata publisher="Engine Room Records" \
            -metadata copyright="CC BY-SA 4.0 - $REAL_RELEASE_YEAR Michael P. Ragsdale / RaggieSoft" \
            -metadata comment="Audio Generation: Suno. AI Elements: Vocals, Instrumentation, Composition. Human Elements: Lyrics, Narrative Lore. License: CC BY-SA 4.0. Commercial Rights Cleared." \
            -metadata ISRC="$ISRC_CODE" \
            -c copy "$LOCAL_WAV"
        fi
    fi

fi

# Store the updated runtime in the live tracks.json directly to prevent race conditions
if [ -n "$RUNTIME" ]; then
    jq --arg rt "$RUNTIME" --arg file "$FILE_BASE" \
      'if type == "array" then map(if .fileName == $file then .duration = $rt else . end) else .tracks |= map(if .fileName == $file then .duration = $rt else . end) end' \
      tracks.json > tracks.json.tmp && mv tracks.json.tmp tracks.json
fi

WAV_FILE="$LOCAL_WAV"
LYRICS_CONTENT=""
if [ -f "lyrics/$FILE_BASE.md" ]; then LYRICS_CONTENT=`cat "lyrics/$FILE_BASE.md"`; fi

# Append data to the global search index payload
jq -n -c \
    --arg id "$FILE_BASE" \
    --arg title "$TITLE" \
    --arg artist "$ALBUM_ARTIST" \
    --arg album "$ALBUM_NAME" \
    --arg url "$WEB_URL" \
    --arg type "track" \
    --arg content "$LYRICS_CONTENT" \
    '{id: $id, title:$title, artist: $artist, album:$album, url: $url, type:$type, content: $content}' >> "$ROOT_DIR/$TEMP_SEARCH_INDEX"

# ------------------------------------------------------------------------------
# 4. DistroKid Release Sheet Generation
# ------------------------------------------------------------------------------
METADATA_MD="streaming-services/song-metadata/$FILE_BASE.md"

if [ -z "$ALBUM_UPC" ]; then
    UPC_PRINT="None"
else
    UPC_PRINT="$ALBUM_UPC"
fi

if [ ! -f "$METADATA_MD" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
    echo "         -> 📋 Drafting DistroKid-Optimized Metadata sheet..."
    cat << EOF > "$METADATA_MD"
# $TITLE - DistroKid Quick-Copy Sheet

## 1. DistroKid Upload Form Data
* **Track Title:** $TITLE
* **Primary Artist:** $ALBUM_ARTIST
* **Genre:** $GENRE
* **Real-World DSP Release Date:** $REAL_RELEASE_DATE
* **Already got an ISRC code? (US ISRC Prefix QTAHP):** $ISRC_CODE

**DistroKid AI Credits Questionnaire:**
* **Did AI generate any part of this track?** Yes
* **Which parts?**
  * [ ] **The lyrics** *(Leave blank - Human authored)*
  * [x] **The music** *(AI composed the melody/arrangement)*
  * [x] **All of the audio** *(Everything the listener hears is AI-generated)*
* **Artist Identity:** AI Persona

**DistroKid Extras / Add-Ons Policy (CRITICAL — DO NOT OPT IN TO CONTENT ID):**
* [ ] **Social Media Pack (\$14.95/yr + 20% platform ad revenue):** **LEAVE UNCHECKED / DO NOT SELECT**
  * *Why:* Enrolling in YouTube Content ID, TikTok music ID recognition, or Meta Rights Manager (Instagram/Facebook) triggers automated copyright claims and demonetization against independent creators legally using our music under **CC BY-SA 4.0** and enterprise clients holding a **Direct Commercial Non-Exclusive Sync License**.

## 2. DistroKid Credits Dashboard (distrokid.com/credits)
*DistroKid requires a real human name for all songwriter credits.*
* **Songwriter (Required):** Michael P. Ragsdale
* **Songwriter Role:** Lyricist
* **Musician / Producer:** AI-Generated (Vocals & Instrumentation)

## 3. Internal Catalog Information
* **Engine Room ID:** $ERR_ID
* **ISRC:** $ISRC_CODE
* **US ISRC Agency Registrant:** Michael Ragsdale (Registrant ID: 185611 • Prefix: QTAHP • dsp.operations@engineroom-records.com)
* **Album UPC / GTIN-12:** $UPC_PRINT
* **Track Length:** $RUNTIME
* **Fictional Narrative Release Date:** $NARRATIVE_DATE
* **Master File Located At:** ../../vault/wav/$FILE_BASE.wav

## 4. Rights, Tri-License Architecture & Clearances
* **Commercial Rights:** 100% cleared via commercial-tier Suno Premium.
* **Tri-License Model:**
  1. **CC BY-SA 4.0 International:** Open-culture sharing & remixing with attribution to *Michael P. Ragsdale / Engine Room Records / RaggieSoft Media*.
  2. **Standard DSP Consumer License:** Personal streaming via Apple Music, Spotify, YouTube Music, Amazon Music, TIDAL, Pandora, Qobuz, and The Listening Room.
  3. **Direct Commercial Non-Exclusive Sync License:** Available via \`https://raggiesoft.com/raggiesoft-media/licensing/commercial\` for commercial productions waiving ShareAlike copyleft terms.
* **Automated Content ID / Rights Manager:** Strictly opted out (Zero Content-ID Ambush Guarantee).
* **Impersonation:** NONE. Synthetic vocals only.
EOF
else
    echo "         ⏭️  DSP Metadata sheet already exists! Fast-forwarding."
fi

# ------------------------------------------------------------------------------
# 5. DSP Lyrics Scrubbing
# ------------------------------------------------------------------------------
# DistroKid and Apple Music reject lyrics containing structural tags or formatting
LYRIC_MD="lyrics/$FILE_BASE.md"
LYRIC_TXT="streaming-services/lyrics/$FILE_BASE.txt"

if [ -f "$LYRIC_MD" ]; then
    if [ ! -f "$LYRIC_TXT" ] || [ "$OVERWRITE" = true ]; then
        echo "         -> 📝 Scrubbing Lyrics for DSP delivery..."
        # Regular expression matching standard structural tags like [Chorus], (Verse 1), etc.
        REGEX_STRUCT="([Vv]erse|[Cc]horus|[Bb]ridge|[Ii]ntro|[Oo]utro|[Hh]ook|[Pp]re-?[Cc]horus|[Ii]nterlude|[Ss]olo)([[:space:]]*[0-9]+)?(:)?"
        
        # Pipeline: Strip headers -> Strip brackets -> Strip parenthesis -> Strip bare tags ->
        # Strip markdown bold/italics -> Strip trailing punctuation -> Collapse blank lines.
        sed '1,/\*\*LYRICS:\*\*/d' "$LYRIC_MD" | \
        sed -E '/^[[:space:]]*[[](.*)[]][[:space:]]*$/d' | \
        sed -E '/^[[:space:]]*[(](.*)[)][[:space:]]*$/d' | \
        sed -E "/^[[:space:]]*$REGEX_STRUCT[[:space:]]*$/d" | \
        sed -E 's/\*\*//g' | sed -E 's/__//g' | sed -E 's/\*//g' | sed -E 's/_//g' | \
        sed -E 's/[.,?!;:]+[[:space:]]*$//' | \
        cat -s | sed '/^[[:space:]]*$/{N;/^\n$/D;}' > "$LYRIC_TXT"
    else
        echo "         ⏭️  DSP Lyrics already clean! Fast-forwarding."
    fi
    
    # --------------------------------------------------------------------------
    # 6. WhisperX Auto-Alignment (VTT Generation)
    # --------------------------------------------------------------------------
    LYRIC_VTT="streaming-services/lyrics/$FILE_BASE.vtt"
    SOURCE_VTT="lyrics/$FILE_BASE.vtt"
    
    if [ -f "$LYRIC_TXT" ] && [ -f "$WAV_FILE" ] && [ "$NO_VTT" = false ]; then
        
        # Check if the user placed a manual VTT in the source lyrics/ folder
        if [ -f "$SOURCE_VTT" ] && grep -q "SYNC_TYPE: HUMAN_VERIFIED" "$SOURCE_VTT"; then
            echo "         🛡️   Human-Verified source VTT detected! Copying directly and skipping WhisperX."
            cp "$SOURCE_VTT" "$LYRIC_VTT"
        else
            # Check if there's already a verified one in the build folder to protect it
            IS_HUMAN_VERIFIED=false
            if [ -f "$LYRIC_VTT" ] && grep -q "SYNC_TYPE: HUMAN_VERIFIED" "$LYRIC_VTT"; then
                IS_HUMAN_VERIFIED=true
            fi
            
            if [ "$IS_HUMAN_VERIFIED" = true ]; then
                echo "         🛡️   Human-Verified VTT detected in build folder! Protecting from WhisperX overwrite."
            elif [ ! -f "$LYRIC_VTT" ] || [ "$OVERWRITE" = true ]; then
            echo "         -> 🤖 Running Demucs Vocal Isolation & Whisper VTT Forced Alignment..."
            
            # Run HuggingFace completely offline to prevent rate-limiting and token warnings for both Demucs and Whisper
            export HF_HUB_OFFLINE=1
            
            # Step A: Vocal Isolation (MPS Accelerated via PyTorch)
            PYTHONWARNINGS="ignore" demucs --two-stems=vocals -o demucs_out "$WAV_FILE"
            VOCALS_STEM="demucs_out/htdemucs/$FILE_BASE/vocals.wav"
            
            if [ -f "$VOCALS_STEM" ]; then
                # Step B: Forced Alignment 
                PYTHONWARNINGS="ignore" whisperx "$VOCALS_STEM" \
                    --output_dir lyrics \
                    --output_format vtt \
                    --model large-v2 \
                    --compute_type int8 \
                    --language en \
                    --max_line_width 40 \
                    --max_line_count 1
                
                # whisperx outputs as vocals.vtt based on the stem filename
                if [ -f "lyrics/vocals.vtt" ]; then
                    mv "lyrics/vocals.vtt" "$SOURCE_VTT"
                    cp "$SOURCE_VTT" "$LYRIC_VTT"
                fi
                
                # Step C: Studio Cleanup
                rm -rf demucs_out
            else
                echo "         ⚠️  Demucs failed to isolate vocals."
            fi
        else
            echo "         ⏭️  DSP VTT already generated! Fast-forwarding."
        fi
        fi
    fi

fi

# ------------------------------------------------------------------------------
# 7. Asynchronous Audio Generation Spawning
# ------------------------------------------------------------------------------
if [ "$METADATA_ONLY" = false ] || [ "$MINTED_NEW_ISRC" = true ]; then
    if [ -f "$WAV_FILE" ]; then
        echo "         -> 🎚️ Pressing Multi-Tier Audio (Parallelized, ISRC: $ISRC_CODE)..."
        # Run in background to drastically speed up processing
        press_audio_formats "$WAV_FILE" "$FILE_BASE" "$TITLE" "$ALBUM_ARTIST" "$ALBUM_NAME" "$REAL_RELEASE_YEAR" "$TRACK_NUM" "$DISC_NUM" "$GENRE" "$ISRC_CODE" &
        # Capture PID for parent shell synchronization
        PIDS+=($!)
        
        # Throttle concurrent jobs to prevent CPU starvation and memory exhaustion
        CURRENT_JOBS=`jobs -p | wc -l`
        while [ "$CURRENT_JOBS" -ge "$MAX_JOBS" ]; do
            wait -n
            CURRENT_JOBS=`jobs -p | wc -l`
        done
    else
        echo "         ⏭️  Audio source missing. Skipping FFmpeg encoding for $TITLE."
    fi
else
    echo "         ⏭️  Metadata-Only mode active. Skipping audio encoding."
fi
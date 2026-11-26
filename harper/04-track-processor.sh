#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 04: TRACK PROCESSOR (`harper/04-track-processor.sh`)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Module 04 is Harper's inner loop—sourced once for EVERY single song in
#   `tracks.json`! For each song (`$track_json`), it performs 7 studio jobs:
#     1. Extracts `fileName`, `title`, `version`, `disc`, `track`, and appends
#        the song to `read-me.txt` and the artist's Master Discography Markdown.
#     2. Auto-mints an Official US ISRC (`QTAHP` + `YY` + `NNNNN`) when a song's
#        master WAV exists on disk without an ISRC—inheriting any existing ISRC
#        if the exact same `masterWavPath` was already released on another album!
#     3. Assigns an internal Engine Room Records ID (`ERR-001..ERR-008`) and
#        appends a JSON-Lines row to `temp_catalog_index.jsonl`.
#     4. Measures exact `M:SS` track runtime via `ffprobe`, saves it back into
#        `tracks.json`, and stamps **Broadcast Wave Format (BWF)** RIFF/BEXT
#        headers into `$ALBUM_VAULT_DIR/wav/<fileName>.wav` via `-c copy` (zero
#        audio re-encoding—100% lossless bit-stream copy!).
#     5. Generates a per-song DistroKid Quick-Copy sheet (`song-metadata/<file>.md`).
#     6. Scrubs Markdown/structural tags (`[Chorus]`, `(Verse 1)`) out of
#        `lyrics/<file>.md` using `sed -E` to produce clean plain-text DSP lyrics,
#        and keeps `NOTE SYNC_TYPE: HUMAN_VERIFIED` `.vtt` timed lyrics synced 1:1.
#     7. Spawns `press_audio_formats` asynchronously (`&`) up to `$MAX_JOBS` workers!
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Metadata Extraction & Version-Aware Tag Title Construction
# ------------------------------------------------------------------------------
# `TITLE` holds the clean base song name from `.title` in `tracks.json` (used for
# the DSP `Name` field). `VERSION_INFO` holds the optional `.version` string
# (e.g. "Live in Norfolk", "Corporate Demo", "Full Suite"). When `VERSION_INFO`
# is present, `TAG_TITLE` renders as `"$TITLE ($VERSION_INFO)"` for ID3 tags,
# Vorbis Comments, BWF WAV headers, and human-readable tracklists.
FILE_BASE=`echo "$track_json" | jq -r '.fileName'`
TITLE=`echo "$track_json" | jq -r '.title'`
VERSION_INFO=`echo "$track_json" | jq -r '.version // empty'`
if [ -n "$VERSION_INFO" ] && [ "$VERSION_INFO" != "null" ]; then
    TAG_TITLE="$TITLE ($VERSION_INFO)"
else
    VERSION_INFO=""
    TAG_TITLE="$TITLE"
fi
DISC_NUM=`echo "$track_json" | jq -r '.disc // 1'`
TRACK_NUM=`echo "$track_json" | jq -r '.track'`
SUITE_NAME=`echo "$track_json" | jq -r '.suiteName // empty'`
SUITE_TRACK=`echo "$track_json" | jq -r '.suiteTrack // empty'`

# Append tracklist line to `read-me.txt` (inserting a `--- Suite Name ---` banner before multi-part rock opera suites)
if [ -n "$SUITE_NAME" ]; then
    if [ "$SUITE_TRACK" == "1" ]; then
        echo "" >> "$README_FILE"
        echo "  --- $SUITE_NAME ---" >> "$README_FILE"
    fi
    echo "  $TRACK_NUM.$TAG_TITLE" >> "$README_FILE"
else
    echo "  $TRACK_NUM.$TAG_TITLE" >> "$README_FILE"
fi

echo "      🎙️  HARPER: Checking Track $TRACK_NUM - '$TAG_TITLE'..."

# Append song heading and converted lore/lyrics to the artist's Master Discography Markdown
echo "## $TAG_TITLE" >> "$MASTER_DISCO_FILE"

LYRIC_MD_PATH="lyrics/$FILE_BASE.md"

if [ -f "$LYRIC_MD_PATH" ]; then
    # `sed -e 's/find/replace/'` ("stream editor") converts bold markers into clean `###` Markdown subheadings
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

# Resolve Master WAV source path (`/raggiesoft-vaults/.../master-wav/...`) vs. album vault WAV destination
MASTER_DIR="${MASTER_WAV_DIR:-$VAULTS_ROOT/$ARTIST_SLUG/master-wav}"
SOURCE_WAV="$MASTER_DIR/$MASTER_WAV_PATH.wav"
LOCAL_WAV="${ALBUM_VAULT_DIR:-vault}/wav/$FILE_BASE.wav"

# ------------------------------------------------------------------------------
# 1b. Official US ISRC Agency Auto-Minter (Prefix: QTAHP • Registrant ID: 185611)
# ------------------------------------------------------------------------------
# ATOMIC JSON UPDATE PATTERN (`jq ... tracks.json > tracks.json.tmp && mv tracks.json.tmp tracks.json`):
#   In Unix shells, NEVER write `jq ... tracks.json > tracks.json`! The shell opens
#   `> tracks.json` and wipes it to 0 bytes BEFORE `jq` even starts reading it!
#   Writing to `tracks.json.tmp` first and atomically renaming (`mv`) once `jq`
#   exits `0` (`&&`) guarantees `tracks.json` can never be corrupted!
MINTED_NEW_ISRC=false
if [ -z "$ISRC_CODE" ] || [ "$ISRC_CODE" == "null" ]; then
    ISRC_CODE=""
    # Step A: Check `$TEMP_WAV_ISRC_MAP` via `awk -F'\t'` (tab-delimited lookup) to see if this
    # exact recording (`$ARTIST_SLUG|$MASTER_WAV_PATH`) already has an ISRC on another release!
    if [ -n "$MASTER_WAV_PATH" ] && [ -f "$TEMP_WAV_ISRC_MAP" ]; then
        EXISTING_WAV_ISRC=$(awk -F'\t' -v key="$ARTIST_SLUG|$MASTER_WAV_PATH" '$1 == key {print $2; exit}' "$TEMP_WAV_ISRC_MAP")
        if [ -n "$EXISTING_WAV_ISRC" ]; then
            ISRC_CODE="$EXISTING_WAV_ISRC"
            MINTED_NEW_ISRC=true
            ALBUM_MINTED_NEW_ISRC=true
            echo "      🔗 HARPER: Linked existing recording ISRC $ISRC_CODE for shared master '$MASTER_WAV_PATH'"
            # Atomically update `tracks.json` via a `.tmp` file + `mv` (because reading and writing
            # the same file in one pipeline `jq ... tracks.json > tracks.json` would truncate it to 0 bytes!):
            jq --arg isrc "$ISRC_CODE" --arg file "$FILE_BASE" \
              'if type == "array" then map(if .fileName == $file then .isrc = $isrc else . end) else .tracks |= map(if .fileName == $file then .isrc = $isrc else . end) end' \
              tracks.json > tracks.json.tmp && mv tracks.json.tmp tracks.json
        fi
    fi

    # Step B: If brand-new recording (`-f "$SOURCE_WAV"`) and album is not locked to a pre-existing UPC:
    # `[ -s "$TEMP_ISRC_GAPS_FILE" ]` checks if the gaps file is non-empty (`-s` = file size > 0 bytes).
    # `head -n 1` pops the first gap number, and `tail -n +2` keeps line 2 onward!
    if [ -z "$ISRC_CODE" ] && [ -z "$ALBUM_UPC" ] && [ -n "$MASTER_WAV_PATH" ] && [ -f "$SOURCE_WAV" ]; then
        if [ -s "$TEMP_ISRC_GAPS_FILE" ]; then
            # Pop the lowest unassigned sequential gap integer first to maintain a 100% contiguous QTAHP ledger
            NEXT_SEQ=$(head -n 1 "$TEMP_ISRC_GAPS_FILE" | tr -d '[:space:]')
            tail -n +2 "$TEMP_ISRC_GAPS_FILE" > "${TEMP_ISRC_GAPS_FILE}.tmp" && mv "${TEMP_ISRC_GAPS_FILE}.tmp" "$TEMP_ISRC_GAPS_FILE"
            ISRC_MINT_MODE="Backfilled Gap"
        else
            # No unassigned gaps remain; increment past the highest allocated sequential designation
            CURR_SEQ=$(cat "$TEMP_ISRC_COUNTER_FILE" 2>/dev/null || echo "0")
            NEXT_SEQ=$((CURR_SEQ + 1))
            echo "$NEXT_SEQ" > "$TEMP_ISRC_COUNTER_FILE"
            ISRC_MINT_MODE="Minted Sequential"
        fi
        ISRC_CODE=$(printf "%s%s%05d" "${ISRC_REGISTRANT_PREFIX:-QTAHP}" "${ISRC_YEAR_SUFFIX:-26}" "$NEXT_SEQ")
        MINTED_NEW_ISRC=true
        ALBUM_MINTED_NEW_ISRC=true
        printf "%s|%s\t%s\n" "$ARTIST_SLUG" "$MASTER_WAV_PATH" "$ISRC_CODE" >> "$TEMP_WAV_ISRC_MAP"
        echo "      🏷️  HARPER: ${ISRC_MINT_MODE} Official US ISRC Agency Code: $ISRC_CODE ($TAG_TITLE)"
        jq --arg isrc "$ISRC_CODE" --arg file "$FILE_BASE" \
          'if type == "array" then map(if .fileName == $file then .isrc = $isrc else . end) else .tracks |= map(if .fileName == $file then .isrc = $isrc else . end) end' \
          tracks.json > tracks.json.tmp && mv tracks.json.tmp tracks.json
    fi
fi

# ------------------------------------------------------------------------------
# 2. Engine Room Records Internal Catalog Routing (`ERR-001` .. `ERR-008`)
# ------------------------------------------------------------------------------
# Maps each fictional band on the Engine Room Records roster to its permanent label catalog prefix:
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

# `jq -n -c --arg key "$val" '{...}'` constructs a brand-new (`-n` = null input) JSON object
# safely escaping quotes/unicode in every `--arg` variable, compacted onto 1 line (`-c`) for `.jsonl`!
jq -n -c \
    --arg err_id "$ERR_ID" \
    --arg isrc "$ISRC_CODE" \
    --arg upc "$ALBUM_UPC" \
    --arg title "$TITLE" \
    --arg version "$VERSION_INFO" \
    --arg tag_title "$TAG_TITLE" \
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
        trackVersion: $version,
        taggedTitle: $tag_title,
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
# 3. Master Audio Verification & Lossless Broadcast Wave Format (BWF) Stamping
# ------------------------------------------------------------------------------
MASTER_DIR="${MASTER_WAV_DIR:-$VAULTS_ROOT/$ARTIST_SLUG/master-wav}"
SOURCE_WAV="$MASTER_DIR/$MASTER_WAV_PATH.wav"
LOCAL_WAV="${ALBUM_VAULT_DIR:-vault}/wav/$FILE_BASE.wav"
RUNTIME=""

if [ ! -f "$SOURCE_WAV" ]; then 
    echo "         ⚠️  WHOA! Master tape missing from central vault: $SOURCE_WAV"
else
    # `ffprobe` reads the exact floating-point duration in seconds (e.g., `245.32`), and `awk`
    # divides by 60 (`$1/60`) + modulo 60 (`$1%60`) to format `"4:05"`!
    RUNTIME=`ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$SOURCE_WAV" | awk '{printf "%d:%02d\n", $1/60, $1%60}'`
    echo "      ⏱️  HARPER: Track runtime clocked at $RUNTIME"

        if [ "$METADATA_ONLY" = false ] || [ "$MINTED_NEW_ISRC" = true ]; then
        if [ ! -f "$LOCAL_WAV" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
            echo "         -> 💾 Stamping BWF Metadata (ISRC: $ISRC_CODE, Title: '$TAG_TITLE') and pulling $MASTER_WAV_PATH to $LOCAL_WAV..."
            mkdir -p "${ALBUM_VAULT_DIR:-vault}/wav"
            
            # HOW BROADCAST WAVE FORMAT (`-write_bext 1` + `-c copy`) WORKS:
            #   Standard `.wav` files often lack artist/ISRC metadata, so Broadcast Wave
            #   Format (EBU Tech 3285) adds a `bext` + RIFF `INFO` header chunk inside the WAV.
            #   Passing `-c copy` ("stream copy") tells FFmpeg NOT to re-encode the audio
            #   samples at all—it copies 100% of the raw PCM audio bytes untouched while
            #   writing the BWF/ISRC header in milliseconds!
            ffmpeg -nostdin -hide_banner -loglevel error -y -i "$SOURCE_WAV" -write_bext 1 \
            -metadata title="$TAG_TITLE" \
            -metadata artist="$ALBUM_ARTIST" \
            -metadata album="$ALBUM_NAME" \
            -metadata date="$REAL_RELEASE_YEAR" \
            -metadata track="$TRACK_NUM" \
            -metadata genre="$GENRE" \
            -metadata publisher="Engine Room Records" \
            -metadata copyright="CC BY-SA 4.0 - $REAL_RELEASE_YEAR Michael P. Ragsdale / RaggieSoft" \
            -metadata comment="Audio Generation: Suno. AI Elements: Vocals, Instrumentation, Composition. Human Elements: Lyrics, Narrative Lore. License: CC BY-SA 4.0. Commercial Rights Cleared." \
            -metadata ISRC="$ISRC_CODE" \
            -c copy "$LOCAL_WAV" || HARPER_AUDIO_ERRORS=$((HARPER_AUDIO_ERRORS + 1))
        fi
    fi

fi

# Persist clocked `M:SS` runtime back into `tracks.json` atomically
if [ -n "$RUNTIME" ]; then
    jq --arg rt "$RUNTIME" --arg file "$FILE_BASE" \
      'if type == "array" then map(if .fileName == $file then .duration = $rt else . end) else .tracks |= map(if .fileName == $file then .duration = $rt else . end) end' \
      tracks.json > tracks.json.tmp && mv tracks.json.tmp tracks.json
fi

WAV_FILE="$LOCAL_WAV"
LYRICS_CONTENT=""
if [ -f "lyrics/$FILE_BASE.md" ]; then LYRICS_CONTENT=`cat "lyrics/$FILE_BASE.md"`; fi

# Append track search record to `temp_search_index.jsonl` (slurped into `metadata.json` by `06-finalize.sh`)
jq -n -c \
    --arg id "$FILE_BASE" \
    --arg title "$TAG_TITLE" \
    --arg artist "$ALBUM_ARTIST" \
    --arg album "$ALBUM_NAME" \
    --arg url "$WEB_URL" \
    --arg type "track" \
    --arg content "$LYRICS_CONTENT" \
    '{id: $id, title:$title, artist: $artist, album:$album, url: $url, type:$type, content: $content}' >> "$ROOT_DIR/$TEMP_SEARCH_INDEX"

# ------------------------------------------------------------------------------
# 4. DistroKid Release Sheet Generation (`cat << EOF` Unquoted Heredoc)
# ------------------------------------------------------------------------------
# Note how `cat << EOF > "$METADATA_MD"` uses an UNQUOTED `EOF` delimiter:
# unlike `<< 'PYEOF'` (single-quoted, literal text), unquoted `<< EOF` tells Bash
# to substitute `$TITLE`, `$ISRC_CODE`, etc. directly into the Markdown template
# while escaping literal dollar signs as `\$14.95`!
METADATA_MD="streaming-services/song-metadata/$FILE_BASE.md"

if [ -z "$ALBUM_UPC" ]; then
    UPC_PRINT="None"
else
    UPC_PRINT="$ALBUM_UPC"
fi

if [ ! -f "$METADATA_MD" ] || [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ]; then
    echo "         -> 📋 Drafting DistroKid Metadata sheet..."
    cat << EOF > "$METADATA_MD"
# $TAG_TITLE - DistroKid Quick-Copy Sheet

## 1. Distributor Upload Form Data
* **Track Title (Name):** $TITLE
* **Version:** ${VERSION_INFO:-None (Leave Blank on DSP)}
* **ID3 / Vorbis Tagged Title:** $TAG_TITLE
* **Primary Artist:** $ALBUM_ARTIST
* **Genre:** $GENRE
* **Real-World DSP Release Date:** $REAL_RELEASE_DATE
* **Already got an ISRC code? (US ISRC Prefix QTAHP):** $ISRC_CODE

**DistroKid Store Selection Policy (EXCLUDE ANTI-AI STORES):**
* [ ] **Tidal:** **UNCHECK / DO NOT DELIVER** *(Catalog pulled Nov 25, 2026 ahead of Dec 9, 2026 AI ban)*
* [ ] **Beatport:** **LEAVE UNCHECKED / DO NOT DELIVER** *(Prohibits generative-AI audio)*
* [ ] **Any other store refusing properly disclosed AI music:** **UNCHECK**

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
  2. **Standard DSP Consumer License:** Personal streaming via Apple Music, Spotify, YouTube Music, Amazon Music, Pandora, Qobuz, and The Listening Room.
  3. **Direct Commercial Non-Exclusive Sync License:** Available via \`https://raggiesoft.com/raggiesoft-media/licensing/commercial\` for commercial productions waiving ShareAlike copyleft terms.
* **Automated Content ID / Rights Manager:** Strictly opted out (Zero Content-ID Ambush Guarantee).
* **Impersonation:** NONE. Synthetic vocals only.
EOF
else
    echo "         ⏭️  DSP Metadata sheet already exists! Fast-forwarding."
fi

# ------------------------------------------------------------------------------
# 5. DSP Plain-Text Lyrics Scrubbing (`sed -E` Multi-Stage Pipeline)
# ------------------------------------------------------------------------------
# Apple Music, Musixmatch, and DistroKid reject lyrics containing `[Verse 1]`,
# `(Guitar Solo)`, Markdown `**bold**`, or trailing periods/commas at the ends of lines!
# This Unix pipeline chains `sed` ("stream editor") filters left-to-right via `|`:
#   1. `sed '1,/\*\*LYRICS:\*\*/d'` : Deletes everything from line 1 through `**LYRICS:**` (stripping the Lore Note!).
#   2. `sed -E '/^...[[].*[]]...$/d'`: Deletes standalone `[Chorus]` / `[Guitar Solo]` cue lines.
#   3. `sed -E '/^...[(].*[)]...$/d'`: Deletes standalone `(Backing Vocals)` parenthetical lines.
#   4. `sed -E "/^...$REGEX_STRUCT...$/d"`: Deletes bare `Verse 1:` / `Bridge` headers.
#   5. `s/\*\*//g` .. `s/_//g`       : Strips Markdown bold/italic markers.
#   6. `s/[.,?!;:]+[[:space:]]*$//`  : Strips end-of-line punctuation per Apple Music lyric style rules.
#   7. `cat -s`                      : Squeezes multiple consecutive blank lines into single stanza breaks!
LYRIC_MD="lyrics/$FILE_BASE.md"
LYRIC_TXT="streaming-services/lyrics/$FILE_BASE.txt"

if [ -f "$LYRIC_MD" ]; then
    if [ ! -f "$LYRIC_TXT" ] || [ "$OVERWRITE" = true ]; then
        echo "         -> 📝 Scrubbing Lyrics for DSP delivery..."
        REGEX_STRUCT="([Vv]erse|[Cc]horus|[Bb]ridge|[Ii]ntro|[Oo]utro|[Hh]ook|[Pp]re-?[Cc]horus|[Ii]nterlude|[Ss]olo)([[:space:]]*[0-9]+)?(:)?"
        
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
    # 6. WebVTT Verification & Google Gemini Multimodal Audio-to-VTT Queue
    #    (WhisperX & Demucs Permanently Retired in Favor of Google Gemini)
    # --------------------------------------------------------------------------
    # HOW WEBVTT (`.vtt`) TIMED LYRICS WORK:
    #   The Listening Room (`music.raggiesoft.com`) highlights lyrics line-by-line
    #   in sync with song playback using standard HTML5 **WebVTT** files stamped with
    #   `NOTE SYNC_TYPE: HUMAN_VERIFIED` (authored by Google Gemini listening directly
    #   to 60–90s audio slices, or via `./studio.sh`).
    #   - If `lyrics/$FILE_BASE.vtt` exists, copy it forward to `streaming-services/lyrics/`.
    #   - If only `streaming-services/lyrics/$FILE_BASE.vtt` exists, back-sync it to `lyrics/`.
    #   - If NEITHER exists yet on a vocal song with audio (`-s "$LYRIC_TXT"` = non-empty lyrics),
    #     append `$ARTIST_SLUG/$ALBUM_SLUG/$FILE_BASE` to `$TEMP_GEMINI_VTT_QUEUE` so `06-finalize.sh`
    #     alerts the producer!
    LYRIC_VTT="streaming-services/lyrics/$FILE_BASE.vtt"
    SOURCE_VTT="lyrics/$FILE_BASE.vtt"

    if [ -f "$SOURCE_VTT" ]; then
        echo "         🛡️   Gemini-Verified source VTT detected ($SOURCE_VTT)! Syncing to streaming-services/lyrics/."
        cp "$SOURCE_VTT" "$LYRIC_VTT"
    elif [ -f "$LYRIC_VTT" ]; then
        echo "         🛡️   Existing VTT detected in build folder ($LYRIC_VTT)! Back-syncing to lyrics/."
        cp "$LYRIC_VTT" "$SOURCE_VTT"
    elif [ -s "$LYRIC_TXT" ] && { [ -f "$WAV_FILE" ] || [ -f "$SOURCE_WAV" ]; } && [ "$NO_VTT" = false ]; then
        echo "         ✨  HARPER -> GEMINI VTT QUEUE: '$TAG_TITLE' ($FILE_BASE) has audio + lyrics and is ready for Google Gemini Multimodal VTT alignment."
        if [ -n "${TEMP_GEMINI_VTT_QUEUE:-}" ]; then
            echo "$ARTIST_SLUG/$ALBUM_SLUG/$FILE_BASE" >> "$TEMP_GEMINI_VTT_QUEUE"
        fi
    fi

fi

# ------------------------------------------------------------------------------
# 7. Asynchronous Audio Generation Spawning (Parallel Worker Pool)
# ------------------------------------------------------------------------------
# HOW BASH BACKGROUND JOBS (`&`, `$!`, `jobs -p`, `wait -n`) WORK:
#   - Putting `&` at the end of `press_audio_formats ... &` launches that function
#     in a parallel background subshell so this loop immediately moves on to the next track!
#   - `$!` holds the OS Process ID (PID) of the background job just launched; `PIDS+=($!)`
#     saves it so `03-album-processor.sh` can verify exit codes at the end of the album.
#   - `jobs -p | wc -l` counts how many background jobs are currently active right now;
#     if we hit `$MAX_JOBS` (e.g., 8 cores), `wait -n` pauses ONLY until the *next* single
#     finishing worker frees up a slot!
if [ "$METADATA_ONLY" = false ] || [ "$MINTED_NEW_ISRC" = true ]; then
    if [ -f "$WAV_FILE" ]; then
        VAULT_CHECK_DIR="${ALBUM_VAULT_DIR:-vault}"
        if [ "$OVERWRITE" = true ] || [ "$MINTED_NEW_ISRC" = true ] || \
           [ ! -f "web-mp3/$FILE_BASE.mp3" ] || \
           [ ! -f "$VAULT_CHECK_DIR/mp3/$FILE_BASE.mp3" ] || \
           [ ! -f "$VAULT_CHECK_DIR/ogg/$FILE_BASE.ogg" ] || \
           [ ! -f "$VAULT_CHECK_DIR/flac/$FILE_BASE.flac" ]; then
            echo "         -> 🎚️ Pressing Multi-Tier Audio (Parallelized, ISRC: $ISRC_CODE, Tagged Title: '$TAG_TITLE')..."
            press_audio_formats "$WAV_FILE" "$FILE_BASE" "$TAG_TITLE" "$ALBUM_ARTIST" "$ALBUM_NAME" "$REAL_RELEASE_YEAR" "$TRACK_NUM" "$DISC_NUM" "$GENRE" "$ISRC_CODE" &
            PIDS+=($!)
            
            # Throttle concurrent jobs to `$MAX_JOBS` so we never starve CPU/RAM
            CURRENT_JOBS=`jobs -p | wc -l`
            while [ "$CURRENT_JOBS" -ge "$MAX_JOBS" ]; do
                wait -n
                CURRENT_JOBS=`jobs -p | wc -l`
            done
        else
            echo "         ⏭️  Multi-tier audio already pressed! Fast-forwarding."
        fi
    else
        echo "         ⏭️  Audio source missing. Skipping FFmpeg encoding for $TITLE."
    fi
else
    echo "         ⏭️  Metadata-Only mode active. Skipping audio encoding."
fi
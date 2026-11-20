#!/usr/bin/env bash
# ==============================================================================
# HARPER MODULE 06: FINALIZE (`harper/06-finalize.sh`)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Sourced last by `harper.sh` after every artist and album loop completes,
#   Module 06 wraps up the studio session:
#     1. Appends a single AI Production Disclaimer footer to each artist's
#        `*-discography-and-lyrics.md` booklet (`if ! grep -q` makes it idempotent).
#     2. Prints a reminder if any newly mastered vocal songs still need Google
#        Gemini Multimodal `.vtt` alignment (`$TEMP_GEMINI_VTT_QUEUE`).
#     3. Uses `jq -s '.'` ("slurp mode") to roll up thousands of line-delimited
#        JSON objects (`.jsonl`) into two valid JSON arrays:
#          * `artists/metadata.json`      (full-text lyric & track search index)
#          * `json/master-catalog.json`   (official US ISRC `QTAHP` & `ERR-*` ledger)
#     4. Computes elapsed `Hours / Minutes / Seconds` using integer division and
#        modulo (`%`) arithmetic, and exits with Harper's strict `ERRORLEVEL` (`0..3`).
# ==============================================================================

echo "   📝 HARPER: Applying AI Production Disclaimers to Master Catalogs..."
# Append the Production Disclaimer footer to every artist's discography Markdown file,
# guarding with `if ! grep -q` so it is never duplicated on repeated runs.
find "$SEARCH_PATH" -name "*-discography-and-lyrics.md" | while read -r master_file; do
    if ! grep -q "### Production Disclaimer" "$master_file"; then
        echo "---" >> "$master_file"
        echo "### Production Disclaimer" >> "$master_file"
        echo "All lyrics and lore are human-authored. Audio composition, instrumentation, and vocals were generated via AI platforms." >> "$master_file"
        echo "" >> "$master_file"
    fi
done

# Report any vocal tracks with audio that are awaiting Google Gemini Multimodal Audio-to-VTT alignment
if [ -n "${TEMP_GEMINI_VTT_QUEUE:-}" ] && [ -s "$TEMP_GEMINI_VTT_QUEUE" ]; then
    VTT_QUEUE_COUNT=$(wc -l < "$TEMP_GEMINI_VTT_QUEUE" | tr -d '[:space:]')
    echo "✨ HARPER -> GOOGLE GEMINI VTT HANDOFF: $VTT_QUEUE_COUNT vocal track(s) with audio are queued for Gemini Multimodal Audio-to-VTT generation (NOTE SYNC_TYPE: HUMAN_VERIFIED)."
fi

# Delete temporary sorting/ISRC/queue scratch files and any `sed -i.bak` backup files
rm -f "$TEMP_SORTED_ALBUMS" "$TEMP_ISRC_COUNTER_FILE" "$TEMP_ISRC_GAPS_FILE" "$TEMP_WAV_ISRC_MAP" "${TEMP_GEMINI_VTT_QUEUE:-}"
find "$SEARCH_PATH" -name "*-discography-and-lyrics.md" -exec sed -i.bak '//d' {} + 2>/dev/null
find "$SEARCH_PATH" -name "*.bak" -type f -delete 2>/dev/null

echo "🎧 HARPER: Finalizing the Search Index..."
# HOW `jq -s '.'` ("SLURP MODE") WORKS:
#   During the track loop, `04-track-processor.sh` appended one JSON object per line
#   (`{"id":"1-01",...}\n{"id":"1-02",...}\n`) because appending to a `.jsonl` file is `O(1)` fast!
#   `jq -s '.'` reads ("slurps") all of those separate JSON lines at once and wraps them
#   into a single valid JSON array `[{"id":"1-01",...}, {"id":"1-02",...}]`!
if [ -s "$TEMP_SEARCH_INDEX" ]; then
    jq -s '.' "$TEMP_SEARCH_INDEX" > "$METADATA_FILE" || HARPER_ARCHIVE_ERRORS=$((HARPER_ARCHIVE_ERRORS + 1))
    rm "$TEMP_SEARCH_INDEX"
    echo "   ✅ HARPER: Index saved to $METADATA_FILE"
else
    echo "   ⚠️  HARPER: Search index was empty. Skipping metadata generation."
    rm -f "$TEMP_SEARCH_INDEX"
fi

# Ensure destination `json/` directory exists for `master-catalog.json`
CATALOG_DIR="${SERVER_ROOT:-../raggiesoft-servers}/raggiesoft-assets/engine-room-records/json"
mkdir -p "$CATALOG_DIR"
CATALOG_FILE="$CATALOG_DIR/master-catalog.json"

echo "🎧 HARPER: Compiling the Master ISRC/ERR Catalog..."
# Slurp `temp_catalog_index.jsonl` into the master ISRC & rights ledger (`master-catalog.json`)
if [ -s "$TEMP_CATALOG_INDEX" ]; then
    jq -s '.' "$TEMP_CATALOG_INDEX" > "$CATALOG_FILE" || HARPER_ARCHIVE_ERRORS=$((HARPER_ARCHIVE_ERRORS + 1))
    rm "$TEMP_CATALOG_INDEX"
    echo "   ✅ HARPER: Catalog saved to $CATALOG_FILE"
else
    echo "   ⚠️  HARPER: Catalog index was empty. Skipping generation."
    rm -f "$TEMP_CATALOG_INDEX"
fi

# --- TIME CALCULATION (INTEGER DIVISION `/` & MODULO `%` REMAINDER MATH) ---
# Given `DURATION_SEC` total elapsed seconds (e.g., `3725` seconds):
#   - `3725 / 3600`        = `1` hour (integer division drops decimals)
#   - `(3725 % 3600) / 60` = `125 / 60` = `2` minutes (`%` gives the remainder after full hours)
#   - `3725 % 60`          = `5` remaining seconds!
END_EPOCH=$(date +%s)
END_TIME_STR=$(date +"%Y-%m-%d %I:%M:%S %p")
DURATION_SEC=$((END_EPOCH - START_EPOCH))

DURATION_HOURS=$((DURATION_SEC / 3600))
DURATION_MIN=$(((DURATION_SEC % 3600) / 60))
DURATION_REM_SEC=$((DURATION_SEC % 60))

# --- FINAL SESSION REPORTING ---
if [ "$METADATA_ONLY" = true ]; then
    echo "🎧 HARPER: Session complete! Metadata repacked and ready for the distro network."
else
    echo "🎧 HARPER: Session complete! The radio edits are public, and the master tapes are locked in the vault."
fi

echo "   ⏰ Session Ended: $END_TIME_STR"
if [ "$DURATION_HOURS" -gt 0 ]; then
    echo "   ⏱️  Total Processing Time: "$DURATION_HOURS"h "$DURATION_MIN"m "$DURATION_REM_SEC"s"
else
    echo "   ⏱️  Total Processing Time: "$DURATION_MIN"m "$DURATION_REM_SEC"s"
fi

# --- ENFORCE ERRORLEVEL EXIT CODE CONTRACT ---
# Return deterministic exit status (`2`, `3`, or `0`) to the caller shell / automation pipeline
if [ "${HARPER_AUDIO_ERRORS:-0}" -gt 0 ]; then
    echo "⚠️  HARPER EXIT STATUS: ERRORLEVEL=${ERR_AUDIO_TRANSCODE_FAILED:-2} (ERR_AUDIO_TRANSCODE_FAILED — $HARPER_AUDIO_ERRORS audio transcode/BWF error(s) detected)."
    exit "${ERR_AUDIO_TRANSCODE_FAILED:-2}"
elif [ "${HARPER_ARCHIVE_ERRORS:-0}" -gt 0 ]; then
    echo "⚠️  HARPER EXIT STATUS: ERRORLEVEL=${ERR_ARCHIVE_OR_CATALOG_FAILED:-3} (ERR_ARCHIVE_OR_CATALOG_FAILED — $HARPER_ARCHIVE_ERRORS archive/catalog error(s) detected)."
    exit "${ERR_ARCHIVE_OR_CATALOG_FAILED:-3}"
else
    echo "✅ HARPER EXIT STATUS: ERRORLEVEL=${ERR_SUCCESS:-0} (ERR_SUCCESS — 100% of audio renders, archives, and JSON catalogs verified)."
    exit "${ERR_SUCCESS:-0}"
fi
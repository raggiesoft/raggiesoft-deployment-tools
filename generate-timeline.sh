#!/bin/bash
# ============================================================================
# Architectural Block: generate-timeline.sh
# ============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   In our shared narrative universe, Engine Room Records bands release albums
#   set across decades of in-story history (1970s–2020s), even though we produce
#   them out of chronological order in real life. `generate-timeline.sh` walks
#   every artist folder, reads each album's in-universe year (`temporalCoverage`)
#   from `album.json` using `jq`, spots any half-built folders missing an
#   `album.json`, sorts everything chronologically from oldest year to newest,
#   and writes a clean Markdown table to `engine-room-timeline.md`.
#
# WHEN IT RUNS:
#   On-demand (`./raggiesoft-deployment-tools/generate-timeline.sh`) whenever you
#   want an up-to-date chronological checklist of all Engine Room Records releases.
#
# INPUTS & OUTPUTS:
#   - Reads: `raggiesoft-servers/raggiesoft-assets/engine-room-records/artists/*/*/album.json`
#   - Writes: `raggiesoft-deployment-tools/engine-room-timeline.md`
# ============================================================================

# Resolve paths relative to the script's own directory (`dirname "$0"`).
WORKSPACE_DIR=$(dirname "$0")
cd "$WORKSPACE_DIR" || exit
if [ -d "../raggiesoft-servers" ]; then
    SERVER_ROOT="../raggiesoft-servers"
else
    SERVER_ROOT=".."
fi
SEARCH_PATH="$SERVER_ROOT/raggiesoft-assets/engine-room-records/artists"
OUTPUT_FILE="engine-room-timeline.md"

echo "🔍 Scanning archives for narrative timeline..."

# `{ ... } > "$OUTPUT_FILE"` groups multiple `echo` commands into one block and
# writes (`>` truncates/creates) all of them into `$OUTPUT_FILE` in a single file open!
{
    echo "# 📅 Engine Room Records: Narrative Timeline"
    echo "*Generated on: $(date +"%Y-%m-%d %I:%M %p")*"
    echo ""
    echo "| Narrative Year | Artist | Album / Project | Folder Path |"
    echo "| :--- | :--- | :--- | :--- |"
} > "$OUTPUT_FILE"

# `mktemp` safely creates a unique temporary scratch file in `/tmp` (avoiding filename collisions).
TEMP_LIST=$(mktemp)

# Walk every `album.json` file under `$SEARCH_PATH` and extract pipe-delimited rows (`YEAR|ARTIST|ALBUM|PATH`):
find "$SEARCH_PATH" -name "album.json" | while read -r file; do
    # HOW `jq -r '.temporalCoverage // empty'` WORKS:
    #   - `jq` is a command-line JSON parser; `-r` ("raw output") strips surrounding `"..."` quotes.
    #   - `// empty` is jq's null-coalescing operator: if `.temporalCoverage` is missing or `null`,
    #     output nothing instead of the literal word `"null"`.
    #   - `| cut -c 1-4` slices characters 1 through 4 (turning `"1997-11-18"` into `"1997"`).
    YEAR=$(jq -r '.temporalCoverage // empty' "$file" | cut -c 1-4)
    # Sentinel Value Trick: if `YEAR` is empty (`-z`), assign `"9999"` so numeric `sort -n`
    # automatically pushes undated Work-In-Progress (WIP) albums to the very bottom of the table!
    if [ -z "$YEAR" ]; then YEAR="9999"; fi
    
    # Extract nested artist name (`.byArtist.name`) with a readable fallback
    ARTIST=$(jq -r '.byArtist.name // empty' "$file")
    if [ -z "$ARTIST" ]; then ARTIST="*Missing Artist*"; fi
    
    # Extract album title (`.name`)
    ALBUM=$(jq -r '.name // empty' "$file")
    if [ -z "$ALBUM" ]; then ALBUM="*Missing Album Name*"; fi
    
    # Strip the long `$SEARCH_PATH/` prefix via `sed "s|old|new|"` (using `|` as delimiter
    # instead of `/` because our paths contain `/` slashes!) so only `<artist>/<album>` remains.
    REL_PATH=$(dirname "$file" | sed "s|$SEARCH_PATH/||")
    
    # Append (`>>`) one pipe-delimited record to our scratch file
    echo "$YEAR|$ARTIST|$ALBUM|$REL_PATH" >> "$TEMP_LIST"
done

# Orphan / Uninitialized Album Check:
# `-mindepth 2 -maxdepth 2 -type d` inspects ONLY `<artist>/<album>` level folders (2 levels deep).
# If a folder lacks `album.json` (`! -f`) yet already has `tracks.json` or `.wav`/`.mp3` files
# (`1> /dev/null 2>&1` silences `ls` output and "No such file" warnings), flag it at `9999`!
find "$SEARCH_PATH" -mindepth 2 -maxdepth 2 -type d | while read -r dir; do
    if [ ! -f "$dir/album.json" ]; then
        if [ -f "$dir/tracks.json" ] || ls "$dir"/*.wav 1> /dev/null 2>&1 || ls "$dir"/*.mp3 1> /dev/null 2>&1; then
            REL_PATH=$(echo "$dir" | sed "s|$SEARCH_PATH/||")
            echo "9999|*Missing album.json*|*Uninitialized*|$REL_PATH" >> "$TEMP_LIST"
        fi
    fi
done

# `sort -n` sorts lines numerically by the leading `YEAR` column.
# `IFS='|' read -r year artist album path` temporarily sets Bash's Internal Field Separator (`IFS`)
# to `|` so `read` splits each line cleanly into 4 variables even when album titles contain spaces!
sort -n "$TEMP_LIST" | while IFS='|' read -r year artist album path; do
    if [ "$year" == "9999" ]; then
        echo "| ⚠️ **WIP** | $artist | $album | \`$path\` |" >> "$OUTPUT_FILE"
    else
        echo "| **$year** | $artist | $album | \`$path\` |" >> "$OUTPUT_FILE"
    fi
done

# Delete the temporary scratch file so `/tmp` stays tidy
rm -f "$TEMP_LIST"

echo "✅ Timeline generated successfully: $WORKSPACE_DIR/$OUTPUT_FILE"


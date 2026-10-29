#!/bin/bash

# ============================================================================
# Architectural Block: generate-timeline.sh
# ============================================================================
# This script scans the 'engine-room-records' directory for music project 
# metadata (`album.json` files) and compiles a markdown narrative timeline.
#
# Key Responsibilities:
# 1. Directory Traversal: Recursively finds `album.json` files within the target artist directory.
# 2. Metadata Extraction: Uses `jq` to parse JSON and extract 'temporalCoverage' (Year), 'byArtist.name', and 'name'.
# 3. Missing Data Handling: Assigns placeholder values ("9999", "*Missing Artist*", etc.) when JSON fields are empty or missing.
# 4. Orphan Directory Detection: Identifies directories that contain audio/track data but lack an `album.json`.
# 5. Report Generation: Sorts all discovered projects chronologically and outputs a formatted Markdown table.
#
# Maintenance Notes:
# - Depends on `jq` being installed and available in the system PATH.
# - If the structure of `album.json` changes (e.g., if 'temporalCoverage' moves), the `jq` queries must be updated.
# - The orphan directory check specifically looks for `.wav`, `.mp3`, and `tracks.json` files. If new formats are added (e.g., `.flac`), update the `ls` checks.
# ============================================================================

# Define paths relative to the script's location (~/Developer/raggiesoft-deployment-tools)
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

# Initialize the Markdown file with headers and a timestamp
{
    echo "# 📅 Engine Room Records: Narrative Timeline"
    echo "*Generated on: $(date +"%Y-%m-%d %I:%M %p")*"
    echo ""
    echo "| Narrative Year | Artist | Album / Project | Folder Path |"
    echo "| :--- | :--- | :--- | :--- |"
} > "$OUTPUT_FILE"

# Find all album.json files and extract metadata into a temporary list for sorting
TEMP_LIST=$(mktemp)

find "$SEARCH_PATH" -name "album.json" | while read -r file; do
    # Extract the first 4 characters of temporalCoverage (assuming YYYY format)
    YEAR=$(jq -r '.temporalCoverage // empty' "$file" | cut -c 1-4)
    # Default to 9999 if the year is missing, ensuring WIPs sort to the bottom
    if [ -z "$YEAR" ]; then YEAR="9999"; fi
    
    # Extract artist name
    ARTIST=$(jq -r '.byArtist.name // empty' "$file")
    if [ -z "$ARTIST" ]; then ARTIST="*Missing Artist*"; fi
    
    # Extract album name
    ALBUM=$(jq -r '.name // empty' "$file")
    if [ -z "$ALBUM" ]; then ALBUM="*Missing Album Name*"; fi
    
    # Get the relative path for easy locating in the output markdown
    REL_PATH=$(dirname "$file" | sed "s|$SEARCH_PATH/||")
    
    # Append the piped string to the temp list for processing later
    echo "$YEAR|$ARTIST|$ALBUM|$REL_PATH" >> "$TEMP_LIST"
done

# Check for folders that might have been created but lack an album.json entirely
# (We look for directories that have audio files or tracks.json but NO album.json)
find "$SEARCH_PATH" -mindepth 2 -maxdepth 2 -type d | while read -r dir; do
    if [ ! -f "$dir/album.json" ]; then
        # Check if it has tracks.json or mp3/wav files to ensure it's meant to be an album folder
        if [ -f "$dir/tracks.json" ] || ls "$dir"/*.wav 1> /dev/null 2>&1 || ls "$dir"/*.mp3 1> /dev/null 2>&1; then
            REL_PATH=$(echo "$dir" | sed "s|$SEARCH_PATH/||")
            # Mark uninitialized folders with 9999 so they drop to the bottom of the timeline
            echo "9999|*Missing album.json*|*Uninitialized*|$REL_PATH" >> "$TEMP_LIST"
        fi
    fi
done

# Sort numerically by Year, then output the formatted rows to the Markdown file
sort -n "$TEMP_LIST" | while IFS='|' read -r year artist album path; do
    # Format WIP rows differently (indicated by the 9999 sentinel value)
    if [ "$year" == "9999" ]; then
        echo "| ⚠️ **WIP** | $artist | $album | \`$path\` |" >> "$OUTPUT_FILE"
    else
        echo "| **$year** | $artist | $album | \`$path\` |" >> "$OUTPUT_FILE"
    fi
done

# Cleanup the temporary list file
rm -f "$TEMP_LIST"

echo "✅ Timeline generated successfully: $WORKSPACE_DIR/$OUTPUT_FILE"


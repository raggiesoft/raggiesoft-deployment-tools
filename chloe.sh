#!/bin/bash
# ==============================================================================
# ARCHITECTURAL BLOCK: CHLOÉ MASON - THE ARCHIVIST (`chloe.sh`)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Web LLMs (like Google Gemini in a browser tab) cannot browse hundreds of
#   local folders on your hard drive unless you upload a context file. Chloé
#   Mason ("The Archivist") walks the entire `raggiesoft-servers` monorepo,
#   skips binary/dependency folders (`node_modules/`, `.git/`, `raggiesoft-vaults/`),
#   enriches every source file (`.php`, `.json`, `.js`, `.css`, `.conf`, `.md`)
#   with its live production URL, Elara route status, navigation link status,
#   and song/book lore metadata, and concatenates everything into one neat
#   timestamped `.txt` manuscript inside `raggiesoft-deployment-tools/chloe/`!
#
# WHEN IT RUNS:
#   On-demand (`./raggiesoft-deployment-tools/chloe.sh`) whenever you want a
#   single-file snapshot of the codebase + lore to upload to a browser AI chat.
#
# INPUTS & OUTPUTS:
#   - Reads: `raggiesoft-servers/` source code, route manifests, and lyrics/books.
#   - Writes: `raggiesoft-deployment-tools/chloe/chloe-bundle-YYYY-MM-DD_HH-MM-SS.txt`
# ==============================================================================

# --- CHLOÉ MASON: THE ARCHIVIST (v1.7.0 - Lore & Lyrics Edition) ---
# "I read everything. I pack the codebase into neat little boxes so the AI can read it."

echo "📚 CHLOÉ MASON: Bonjour, Michael. Let me grab my clipboard and my tea..."
echo "                (And before you ask: the tea is from the Québec side of the border,"
echo "                 even if the hospital in Newport insists on claiming my birth certificate.)"
echo ""

# ------------------------------------------------------------------------------
# 1. ESTABLISH PATHS
# ------------------------------------------------------------------------------
# Resolve absolute paths relative to `chloe.sh` (`$0`)
WORKSPACE_DIR=$(cd "$(dirname "$0")" && pwd)
PARENT_ROOT=$(cd "$WORKSPACE_DIR/.." && pwd)
if [ -d "$PARENT_ROOT/raggiesoft-servers" ]; then
    ROOT_DEV_DIR="$PARENT_ROOT/raggiesoft-servers"
else
    ROOT_DEV_DIR="$PARENT_ROOT"
fi

# Create Chloé's output folder (`raggiesoft-deployment-tools/chloe/`) if missing
CHLOE_DIR="$WORKSPACE_DIR/chloe"
if [ ! -d "$CHLOE_DIR" ]; then
    mkdir -p "$CHLOE_DIR"
    echo "   📁 Setting up my private archives at: /chloe"
fi

# Stamp filename with `YYYY-MM-DD_HH-MM-SS` so consecutive runs never overwrite prior snapshots
DATE_STAMP=$(date +"%Y-%m-%d")
TIME_STAMP=$(date +"%H-%M-%S")
SCRIPT_NAME="chloe-bundle"
OUTPUT_FILE="$CHLOE_DIR/${SCRIPT_NAME}-${DATE_STAMP}_${TIME_STAMP}.txt"

echo "   🔍 Targeting Master Directory: $ROOT_DEV_DIR"
echo "   Je commence... Scanning for code artifacts now."
echo "------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. CLEAR THE DESK & WRITE METADATA HEADER
# ------------------------------------------------------------------------------
# Truncate/create empty output file (`>`), then append (`>>`) the architectural briefing header
> "$OUTPUT_FILE"

{
    echo "=================================================================="
    echo "  CHLOÉ MASON'S ARCHIVE BUNDLE"
    echo "  Archivist Origin: Stanstead, QC (via Newport, VT)"
    echo "=================================================================="
    echo "  [AI CONTEXT METADATA]"
    echo "  Date Compiled: $DATE_STAMP"
    echo "  Time Compiled: $TIME_STAMP (24-Hour Format)"
    echo "  Environment: RaggieSoft Hub (Elara Router v5.7) & Assets CDN"
    echo "  Architecture Note: There is NO standard index.php. All Hub frontend"
    echo "                     traffic is routed by Nginx directly through"
    echo "                     /amanda/elara.php. Internal folders are locked."
    echo "  Purpose: Codebase ingestion and context alignment."
    echo "=================================================================="
    echo ""
} >> "$OUTPUT_FILE"

# ------------------------------------------------------------------------------
# 3. EXECUTE THE SMART SEARCH (`find ... -prune`)
# ------------------------------------------------------------------------------
cd "$ROOT_DEV_DIR" || exit

# HOW `find . -type d \( ... \) -prune -o -type f \( ... \) -print` WORKS:
#   - Without `-prune`, `find` wastes seconds walking inside 100,000+ files in `node_modules/` and `.git/`!
#   - `-type d \( -name ".git" -o -name "node_modules" ... \) -prune` tells `find`:
#     "Whenever you hit one of these directory names, STOP descending into it immediately!"
#   - `-o -type f \( -name "*.php" ... \) -print` ("OR if it's a matching text file, print its path")
#     streams only clean source/lore files into `while read -r file`.
find . -type d \( -name ".git" -o -name "node_modules" -o -name "vendor" -o -name "chloe" -o -name "raggiesoft-vaults" -o -name "wav" -o -name "mp3" -o -name "ogg" -o -name "archives" -o -name "obj" -o -name "bin" -o -name "_sysops" \) -prune \
    -o -type f \( -name "*.php" -o -name "*.json" -o -name "*.js" -o -name "*.css" -o -name "*.conf" -o -name "*.md" \) -print | while read -r file; do
    
    # BASH STRING SLICING OPERATORS (`#`, `##`, `%`):
    #   - `${file#./}`      : `#` strips the shortest matching prefix `./` from the front of `$file`.
    #   - `${BASE_NAME##*.}`: `##` strips the *longest* prefix up to the last `.` (extracting file extension `php`, `md`, etc.!).
    REL_PATH="${file#./}"
    DIR_NAME=$(dirname "$REL_PATH")
    BASE_NAME=$(basename "$REL_PATH")
    EXT="${BASE_NAME##*.}"
    
    # Reset per-file diagnostic tags at the start of every iteration
    LIVE_URL="[INTERNAL/UNMAPPED]"
    ROUTE_STATUS=""
    NAV_STATUS=""
    LYRICS_META=""
    BOOK_META=""
    
    # --- CHLOÉ'S URL RESOLUTION, WIP & ORPHAN LOGIC ---
    if [[ "$REL_PATH" == *"raggiesoft-assets/"* ]]; then
        # Rule 1: Anything inside `raggiesoft-assets/` maps 1:1 to `https://assets.raggiesoft.com/...`
        CLEAN_PATH="${REL_PATH#*raggiesoft-assets/}"
        LIVE_URL="https://assets.raggiesoft.com/${CLEAN_PATH}"
        
    elif [[ "$REL_PATH" == *"raggiesoft.com/www/"* ]] || [[ "$REL_PATH" == *"raggiesoft-hub/"* ]]; then
        if [[ "$REL_PATH" == *"raggiesoft.com/www/"* ]]; then
            CLEAN_PATH="${REL_PATH#*raggiesoft.com/www/}"
            HUB_REL_DIR="raggiesoft.com/www"
        else
            CLEAN_PATH="${REL_PATH#*raggiesoft-hub/}"
            HUB_REL_DIR="raggiesoft-hub"
        fi
        
        if [[ "$CLEAN_PATH" == "pages/"* ]]; then
            # Rule 2: Hub View Pages (`pages/foo/bar.php` -> `foo/bar` via `#pages/` prefix strip and `%.php` suffix strip)
            PAGE_PATH="${CLEAN_PATH#pages/}" 
            PAGE_PATH="${PAGE_PATH%.php}" 
            
            # Route Manifest Check: `grep -rl` searches recursively (`-r`) and prints ONLY matching filenames (`-l`)
            ROUTES_DIR="$HUB_REL_DIR/data/routes"
            if [ -d "$ROUTES_DIR" ]; then
                MATCHING_JSON=$(grep -rl "$PAGE_PATH" "$ROUTES_DIR" 2>/dev/null | head -n 1)
                if [ -n "$MATCHING_JSON" ]; then
                    ROUTE_STATUS="[Mapped in JSON: $MATCHING_JSON]"
                else
                    ROUTE_STATUS="[UNMAPPED / Work-In-Progress]"
                fi
            fi
            
            PAGE_DIR=$(dirname "$PAGE_PATH")
            PAGE_BASE=$(basename "$PAGE_PATH")
            LOCAL_URL_PATH=""
            
            # Rule 3: Overview/Home Index Masking (`pages/home.php` -> `/`, `pages/foo/overview.php` -> `/foo/`)
            if [ "$PAGE_BASE" == "overview" ] || [ "$PAGE_BASE" == "home" ]; then
                if [ "$PAGE_DIR" == "." ]; then
                    LIVE_URL="https://raggiesoft.com/"
                    LOCAL_URL_PATH="/"
                else
                    LIVE_URL="https://raggiesoft.com/${PAGE_DIR}/"
                    LOCAL_URL_PATH="/${PAGE_DIR}"
                fi
            else
                if [ "$PAGE_DIR" == "." ]; then
                    LIVE_URL="https://raggiesoft.com/${PAGE_BASE}"
                    LOCAL_URL_PATH="/${PAGE_BASE}"
                else
                    LIVE_URL="https://raggiesoft.com/${PAGE_DIR}/${PAGE_BASE}"
                    LOCAL_URL_PATH="/${PAGE_DIR}/${PAGE_BASE}"
                fi
            fi
            
            # ORPHAN PAGE DETECTION: Check if any header or sidebar menu actually links to `$LOCAL_URL_PATH`
            COMPONENTS_DIR="$HUB_REL_DIR/includes/components"
            if [ -d "$COMPONENTS_DIR" ]; then
                if [ "$LOCAL_URL_PATH" == "/" ]; then
                    MATCHING_NAV=$(grep -rlE "href=[\"']\/[\"']" "$COMPONENTS_DIR" 2>/dev/null | head -n 1)
                else
                    MATCHING_NAV=$(grep -rl "$LOCAL_URL_PATH" "$COMPONENTS_DIR/headers" "$COMPONENTS_DIR/sidebars" 2>/dev/null | head -n 1)
                fi
                
                if [ -n "$MATCHING_NAV" ]; then
                    NAV_STATUS="[Linked in Navigation: $MATCHING_NAV]"
                else
                    NAV_STATUS="[ORPHANED PAGE / No Nav Link Found]"
                fi
            fi
            
        else
            # Non-page hub files (`includes/`, `amanda/`) are blocked from direct HTTP access by Nginx
            LIVE_URL="[INTERNAL - Protected by Nginx / Elara Gateway]"
        fi
    fi

    # --- LORE & LYRICS METADATA EXTRACTION FOR `.md` FILES ---
    if [ "$EXT" == "md" ]; then
        if [[ "$REL_PATH" == *"engine-room-records/artists/"*"/lyrics/"* ]]; then
            # Capture artist and album parent paths via `sed -n 's|pattern|\1|p'` capture groups
            ARTIST_DIR=$(echo "$REL_PATH" | sed -n 's|\(.*engine-room-records/artists/[^/]*\).*|\1|p')
            ALBUM_DIR=$(echo "$REL_PATH" | sed -n 's|\(.*engine-room-records/artists/[^/]*/[^/]*\).*|\1|p')
            
            ALBUM_JSON="$ALBUM_DIR/album.json"
            [ ! -f "$ALBUM_JSON" ] && ALBUM_JSON="$ARTIST_DIR/album.json"
            
            TRACKS_JSON="$ALBUM_DIR/tracks.json"
            [ ! -f "$TRACKS_JSON" ] && TRACKS_JSON="$ARTIST_DIR/tracks.json"

            if [ -f "$ALBUM_JSON" ]; then
                ARTIST_NAME=$(grep -i '"artist"' "$ALBUM_JSON" | cut -d'"' -f4 | head -n 1)
                ALBUM_NAME=$(grep -i '"album"' "$ALBUM_JSON" | cut -d'"' -f4 | head -n 1)
                [ -z "$ALBUM_NAME" ] && ALBUM_NAME=$(grep -i '"title"' "$ALBUM_JSON" | cut -d'"' -f4 | head -n 1)
                RELEASE_YEAR=$(grep -i '"year"' "$ALBUM_JSON" | grep -o '[0-9]\{4\}' | head -n 1)
                LYRICS_META="// ALBUM INFO: $ARTIST_NAME - $ALBUM_NAME ($RELEASE_YEAR)"
            fi

            if [ -f "$TRACKS_JSON" ]; then
                SONG_SLUG="${BASE_NAME%.*}"
                TRACK_NUM=$(grep -n "$SONG_SLUG" "$TRACKS_JSON" | cut -d: -f1)
                if [ -n "$TRACK_NUM" ]; then
                    LYRICS_META="$LYRICS_META\n// TRACK NO:   $TRACK_NUM"
                fi
            fi
            
        elif [[ "$REL_PATH" == *"raggiesoft-books/"* ]] || [[ "$REL_PATH" == *"books/"* ]]; then
            BOOK_META="// CONTEXT:    Managed by Paige (The Literary Editor)"
        fi
    fi

    # Print color/emoji progress line to terminal based on file extension and route status
    if [ "$EXT" == "php" ]; then
        if [[ "$NAV_STATUS" == *"[ORPHANED"* ]]; then
            echo "      👻 Orphaned Route:         $REL_PATH"
        elif [[ "$ROUTE_STATUS" == *"[UNMAPPED"* ]]; then
            echo "      ⚠️  UNMAPPED WIP:          $REL_PATH"
        else
            echo "      🐘 Parsing server logic:   $REL_PATH"
        fi
    elif [ "$EXT" == "md" ]; then
        if [[ "$REL_PATH" == *"engine-room-records/artists/"* ]]; then
            echo "      🎤 Archiving Lyrics:       $REL_PATH"
        elif [[ "$REL_PATH" == *"raggiesoft-books/"* ]] || [[ "$REL_PATH" == *"books/"* ]]; then
            echo "      📖 Archiving Manuscript:   $REL_PATH"
        else
            echo "      📝 Archiving Markdown:     $REL_PATH"
        fi
    elif [ "$EXT" == "json" ]; then
        echo "      📋 Filing JSON manifest:   $REL_PATH"
    elif [ "$EXT" == "js" ]; then
        echo "      ⚡ Archiving JavaScript:   $REL_PATH"
    elif [ "$EXT" == "css" ]; then
        echo "      🎨 Storing Stylesheet:     $REL_PATH"
    elif [ "$EXT" == "conf" ]; then
        echo "      ⚙️ Archiving Server Config: $REL_PATH"
    else
        echo "      📑 Cataloging artifact:    $REL_PATH"
    fi
    
    # Append file boundary header + metadata comments + full `cat "$file"` body into `$OUTPUT_FILE`
    # (`echo -e` enables `\n` newline interpretation inside `$LYRICS_META`).
    {
        echo "--- START OF FILE $REL_PATH ---"
        echo "// DIRECTORY: $DIR_NAME"
        echo "// FILE:      $BASE_NAME"
        echo "// LIVE URL:  $LIVE_URL"
        if [ -n "$ROUTE_STATUS" ]; then
            echo "// ROUTING:   $ROUTE_STATUS"
        fi
        if [ -n "$NAV_STATUS" ]; then
            echo "// NAV LINK:  $NAV_STATUS"
        fi
        if [ -n "$LYRICS_META" ]; then
            echo -e "$LYRICS_META"
        fi
        if [ -n "$BOOK_META" ]; then
            echo "$BOOK_META"
        fi
        echo "------------------------------------------------------------------"
        cat "$file"
        echo -e "\n\n"
    } >> "$OUTPUT_FILE"
    
done

echo "------------------------------------------------------------------"
echo "📚 CHLOÉ MASON: Voilà! The manuscript is collated and audited."
echo "   📦 Saved to: $OUTPUT_FILE"
echo "   You can hand this directly to Gemini now. I'll be in my reading room if you need me."
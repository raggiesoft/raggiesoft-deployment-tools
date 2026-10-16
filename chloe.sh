#!/bin/bash

# ==============================================================================
# ARCHITECTURAL BLOCK: CHLOÉ MASON - THE ARCHIVIST
# ==============================================================================
# This script bundles the entire codebase into a single formatted text artifact
# suitable for ingestion by Large Language Models (LLMs) like Gemini.
# 
# Key Responsibilities:
# 1. Traverses the repository to find relevant source files (.php, .md, .js, etc.).
# 2. Excludes irrelevant binaries and internal directories (.git, node_modules).
# 3. Resolves local file paths to their production LIVE URLs where applicable.
# 4. Extracts deep domain context (Lore & Lyrics) from Markdown and JSON files.
# 5. Compiles all valid files into a standardized, timestamped archive format.
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
# Calculate absolute paths for workspace and the root developer directory
WORKSPACE_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DEV_DIR=$(cd "$WORKSPACE_DIR/.." && pwd)

# Give Chloé her own private reading room for the manuscripts
# Ensure output directory exists before generating bundle
CHLOE_DIR="$WORKSPACE_DIR/chloe"
if [ ! -d "$CHLOE_DIR" ]; then
    mkdir -p "$CHLOE_DIR"
    echo "   📁 Setting up my private archives at: /chloe"
fi

# Define temporal variables for filename uniqueness
DATE_STAMP=$(date +"%Y-%m-%d")
TIME_STAMP=$(date +"%H-%M-%S")
SCRIPT_NAME="chloe-bundle"
OUTPUT_FILE="$CHLOE_DIR/${SCRIPT_NAME}-${DATE_STAMP}_${TIME_STAMP}.txt"

echo "   🔍 Targeting Master Directory: $ROOT_DEV_DIR"
echo "   Je commence... Scanning for code artifacts now."
echo "------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 2. CLEAR THE DESK & WRITE METADATA
# ------------------------------------------------------------------------------
# Initialize an empty output file, overwriting if it exists
> "$OUTPUT_FILE"

# Append global context header for LLM ingestion
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
# 3. EXECUTE THE SMART SEARCH
# ------------------------------------------------------------------------------
cd "$ROOT_DEV_DIR" || exit

# Added *.md to the fetch list
# Uses `find` with pruning to exclude large/binary dirs, fetching only allowed extensions
find . -type d \( -name ".git" -o -name "node_modules" -o -name "vendor" -o -name "chloe" -o -name "wav" -o -name "mp3" -o -name "ogg" -o -name "archives" -o -name "obj" -o -name "bin" -o -name "_sysops" \) -prune \
    -o -type f \( -name "*.php" -o -name "*.json" -o -name "*.js" -o -name "*.css" -o -name "*.conf" -o -name "*.md" \) -print | while read -r file; do
    
    # Extract file path components for analysis
    REL_PATH="${file#./}"
    DIR_NAME=$(dirname "$REL_PATH")
    BASE_NAME=$(basename "$REL_PATH")
    EXT="${BASE_NAME##*.}"
    
    # Initialize metadata variables per file
    LIVE_URL="[INTERNAL/UNMAPPED]"
    ROUTE_STATUS=""
    NAV_STATUS=""
    LYRICS_META=""
    BOOK_META=""
    
    # --- CHLOÉ's URL RESOLUTION, WIP & ORPHAN LOGIC ---
    if [[ "$REL_PATH" == *"raggiesoft-assets/"* ]]; then
        # Rule 1: Static Assets CDN (Maps directly to assets.raggiesoft.com)
        CLEAN_PATH="${REL_PATH#*raggiesoft-assets/}"
        LIVE_URL="https://assets.raggiesoft.com/${CLEAN_PATH}"
        
    elif [[ "$REL_PATH" == *"raggiesoft-hub/"* ]]; then
        CLEAN_PATH="${REL_PATH#*raggiesoft-hub/}"
        
        if [[ "$CLEAN_PATH" == "pages/"* ]]; then
            # Rule 2: Pages Routing
            # Translate local 'pages/' directory to route path
            PAGE_PATH="${CLEAN_PATH#pages/}" 
            PAGE_PATH="${PAGE_PATH%.php}" 
            
            # Route Manifest Check
            # Look up route definition in data/routes directory
            ROUTES_DIR="raggiesoft-hub/data/routes"
            if [ -d "$ROUTES_DIR" ]; then
                MATCHING_JSON=$(grep -rl "$PAGE_PATH" "$ROUTES_DIR" 2>/dev/null | head -n 1)
                if [ -n "$MATCHING_JSON" ]; then
                    ROUTE_STATUS="[Mapped in JSON: $MATCHING_JSON]"
                else
                    ROUTE_STATUS="[UNMAPPED / Work-In-Progress]"
                fi
            fi
            
            # Reconstruct the expected local URL path structure
            PAGE_DIR=$(dirname "$PAGE_PATH")
            PAGE_BASE=$(basename "$PAGE_PATH")
            LOCAL_URL_PATH=""
            
            # Rule 3: Overview/Home Index Masking
            # Standardize index pages (overview/home) to root domains
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
            
            # ORPHAN PAGE DETECTION
            # Search component views to determine if the page is actually reachable
            COMPONENTS_DIR="raggiesoft-hub/includes/components"
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
            # Non-page hub files are internal only
            LIVE_URL="[INTERNAL - Protected by Nginx / Elara Gateway]"
        fi
    fi
    # ------------------------------------

    # --- NEW: LORE & LYRICS METADATA EXTRACTION ---
    # Process rich text documentation and domain content
    if [ "$EXT" == "md" ]; then
        if [[ "$REL_PATH" == *"engine-room-records/artists/"*"/lyrics/"* ]]; then
            # Extract Artist/Album directories to locate JSONs
            # Uses sed to capture path segments
            ARTIST_DIR=$(echo "$REL_PATH" | sed -n 's|\(.*engine-room-records/artists/[^/]*\).*|\1|p')
            ALBUM_DIR=$(echo "$REL_PATH" | sed -n 's|\(.*engine-room-records/artists/[^/]*/[^/]*\).*|\1|p')
            
            # Look for album.json and tracks.json (fallback to artist root if not in album dir)
            ALBUM_JSON="$ALBUM_DIR/album.json"
            [ ! -f "$ALBUM_JSON" ] && ALBUM_JSON="$ARTIST_DIR/album.json"
            
            TRACKS_JSON="$ALBUM_DIR/tracks.json"
            [ ! -f "$TRACKS_JSON" ] && TRACKS_JSON="$ARTIST_DIR/tracks.json"

            # Parse album.json for lore (Artist, Album, Release Year)
            if [ -f "$ALBUM_JSON" ]; then
                ARTIST_NAME=$(grep -i '"artist"' "$ALBUM_JSON" | cut -d'"' -f4 | head -n 1)
                ALBUM_NAME=$(grep -i '"album"' "$ALBUM_JSON" | cut -d'"' -f4 | head -n 1)
                [ -z "$ALBUM_NAME" ] && ALBUM_NAME=$(grep -i '"title"' "$ALBUM_JSON" | cut -d'"' -f4 | head -n 1)
                RELEASE_YEAR=$(grep -i '"year"' "$ALBUM_JSON" | grep -o '[0-9]\{4\}' | head -n 1)
                LYRICS_META="// ALBUM INFO: $ARTIST_NAME - $ALBUM_NAME ($RELEASE_YEAR)"
            fi

            # Parse tracks.json for order using the filename slug
            if [ -f "$TRACKS_JSON" ]; then
                SONG_SLUG="${BASE_NAME%.*}"
                TRACK_NUM=$(grep -n "$SONG_SLUG" "$TRACKS_JSON" | cut -d: -f1)
                if [ -n "$TRACK_NUM" ]; then
                    LYRICS_META="$LYRICS_META\n// TRACK NO:   $TRACK_NUM"
                fi
            fi
            
        elif [[ "$REL_PATH" == *"raggiesoft-books/"* ]] || [[ "$REL_PATH" == *"books/"* ]]; then
            # Inject editorial metadata
            BOOK_META="// CONTEXT:    Managed by Paige (The Literary Editor)"
        fi
    fi
    # ----------------------------------------------

    # Chloé's standard categorization based on file type for terminal feedback
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
    
    # Write to the manuscript
    # Appends file boundaries, dynamic metadata, and file contents to the bundle
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
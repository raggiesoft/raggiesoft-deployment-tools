#!/bin/bash

# ============================================================================
# Architectural Block: samantha-docx.sh
# ============================================================================
# This script ("Samantha") acts as a document ingestor and shatter protocol, 
# transforming legacy DOCX narrative files and lore sheets into structured 
# Markdown suitable for static web deployment.
#
# Key Responsibilities:
# 1. Lore Extraction: Uses `pandoc` to convert DOCX lore files into GFM (GitHub Flavored Markdown).
#    It includes protection mechanisms to prevent overwriting newer manual Markdown edits.
# 2. Narrative Shattering: Takes monolithic DOCX manuscript files and splits them 
#    into individual chapter/part Markdown files based on header depths (#, ##, ###).
# 3. JSON Indexing: Uses `awk` to parse the monolithic document structure and `jq` 
#    to generate a structured `katie.json` manifest representing books, chapters, and parts.
# 4. Web Deployment: Copies the final generated Markdown and JSON artifacts into the 
#    public-facing `raggiesoft-narratives` repository for web presentation.
#
# Maintenance Notes:
# - Depends heavily on `pandoc`, `awk`, and `jq` being installed on the host system.
# - The AWK shattering logic relies strictly on Markdown headers: 
#   # Book Title, ## Chapter Title, ### Part Title.
# - If the structure of the incoming DOCX changes (e.g., header levels shift), 
#   the AWK block must be adjusted accordingly.
# ============================================================================

echo "👱‍♀️ Samantha: Taking the podium. Passive DOCX Extraction Protocol initialized!"

# Fail fast if the required 'books' directory is not present in the current workspace.
if [[ ! -d "books" ]]; then
    echo "   *Whistle blow!* I can't find the 'books' directory. Are we on the wrong practice field?"
    exit 1
fi

# Iterate over each book project directory.
for DIR in books/*/; do
    BASE=$(basename "$DIR")
    
    # LOCAL SOURCES
    NARRATIVE_DOCX="books/$BASE/$BASE.docx"
    LORE_DOCX="books/$BASE/$BASE-lore.docx"
    LOCAL_LORE_MD="books/$BASE/$BASE-lore.md"
    MANUSCRIPT_DIR="books/$BASE/manuscript"
    
    # PUBLIC DEPLOYMENT FOLDERS (resolved from /raggiesoft-deployment-tools)
    OUT_LORE_DIR="../raggiesoft-narratives/lore/$BASE"
    OUT_NARRATIVE_DIR="../raggiesoft-narratives/books/$BASE"
    FINAL_WEB_LORE="$OUT_LORE_DIR/${BASE}-lore.md"

    # -----------------------------------------
    # PROCESS LORE
    # -----------------------------------------
    if [[ -f "$LORE_DOCX" ]]; then
        # Protection mechanism: If a local markdown file exists and is newer than the DOCX, 
        # assume manual edits were made and skip the destructive pandoc conversion.
        if [[ -f "$LOCAL_LORE_MD" ]] && [[ "$LOCAL_LORE_MD" -nt "$LORE_DOCX" ]]; then
            echo "   🛡️ [PROTECT] Local '$LOCAL_LORE_MD' is newer than DOCX. Skipping Pandoc."
        else
            echo "   Found legacy DOCX lore sheet for '$BASE'. Extracting..."
            # Convert DOCX to GitHub Flavored Markdown without line wrapping.
            pandoc --verbose "$LORE_DOCX" -t gfm --wrap=none -o "$LOCAL_LORE_MD"
        fi
        
        # Deploy the generated lore file to the public narrative repository.
        if [[ -f "$LOCAL_LORE_MD" ]]; then
            mkdir -p "$OUT_LORE_DIR"
            # Only copy if the content actually differs, reducing unnecessary disk I/O.
            if [[ -f "$FINAL_WEB_LORE" ]] && cmp -s "$LOCAL_LORE_MD" "$FINAL_WEB_LORE"; then
                echo "   No tempo changes in lore sync. Skipping."
            else
                cp "$LOCAL_LORE_MD" "$FINAL_WEB_LORE"
                echo "   Updated web lore file: $FINAL_WEB_LORE"
            fi
        fi
    fi

    # -----------------------------------------
    # PROCESS NARRATIVE (Passive Mode)
    # -----------------------------------------
    if [[ -f "$NARRATIVE_DOCX" ]]; then
        # SHIELD CHECK: Is the manuscript already natively chunked?
        # If we find numbered markdown chunks, assume the document is already managed natively.
        MD_COUNT=$(find "$MANUSCRIPT_DIR" -maxdepth 1 -name "[0-9][0-9][0-9]-*.md" 2>/dev/null | wc -l)
        
        if [[ -d "$MANUSCRIPT_DIR" ]] && [[ $MD_COUNT -gt 0 ]]; then
            echo "   🛡️ [PROTECT] Native Markdown chunks found in '$MANUSCRIPT_DIR'. Skipping DOCX shatter."
            continue
        fi
        
        echo "   Found legacy DOCX narrative score for '$BASE'. Shattering into manuscript chunks..."
        
        # Convert the entire monolithic DOCX into a single temporary markdown file.
        TMP_MD="books/$BASE/${BASE}_tmp.md"
        if ! pandoc --verbose "$NARRATIVE_DOCX" -t gfm --wrap=none -o "$TMP_MD"; then
            echo "   *Whistle blow!* Permission error on '$NARRATIVE_DOCX'."
            continue
        fi
        
        # Setup directories for local chunk storage and public web deployment.
        mkdir -p "$MANUSCRIPT_DIR"
        mkdir -p "$OUT_NARRATIVE_DIR"
        
        # Clear old web artifacts to ensure deleted parts don't ghost in the final build.
        find "$OUT_NARRATIVE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        
        # Initialize a temporary JSONL index to log the structure during the AWK pass.
        TEMP_JSONL="$OUT_NARRATIVE_DIR/temp_index.jsonl"
        > "$TEMP_JSONL"

        # The core logic: AWK script to parse the monolithic Markdown file and split it into 
        # individual files based on header depth (# = Book, ## = Chapter, ### = Part).
        LC_ALL=C awk -v base_dir="$OUT_NARRATIVE_DIR" -v manu_dir="$MANUSCRIPT_DIR" -v json_log="$TEMP_JSONL" '
        
        # Helper to sanitize strings for JSON output.
        function escape_json(str) {
            gsub(/\\/, "\\\\", str)
            gsub(/"/, "\\\"", str)
            gsub(/\r/, "", str)
            gsub(/\t/, " ", str)
            return str
        }
        
        # Helper to generate URL-safe slugs from titles.
        function make_slug(title) {
            slug = tolower(title)
            gsub(/[^a-z0-9 -]/, "", slug)
            gsub(/[ -]+/, "-", slug)
            sub(/^-+|-+$/, "", slug)
            if (length(slug) > 35) {
                slug = substr(slug, 1, 35)
                sub(/-[^-]*$/, "", slug)
            }
            return slug
        }

        BEGIN { 
            book_count = 0
            chap_count = 0
            part_count = 0
            current_file = "/dev/null"
            current_manu_file = "/dev/null"
        }

        # Level 1 Header: Start of a new Book
        /^# / { 
            close(current_file)
            if (current_manu_file != "/dev/null") close(current_manu_file)
            
            book_title = substr($0, 3)
            safe_book = make_slug(book_title)
            book_count++
            chap_count = 0 
            
            # 1. Web Routing: Create book directory
            book_dir = sprintf("%s/e%03d", base_dir, book_count)
            system("mkdir -p \"" book_dir "\"")
            
            # 2. Permanent Authoring Chunk: Start a new manuscript file
            current_manu_file = sprintf("%s/%03d-%s.md", manu_dir, book_count, safe_book)
            print $0 > current_manu_file
            
            next
        }

        # Level 2 Header: Start of a new Chapter
        /^## / {
            close(current_file)
            if (current_manu_file != "/dev/null") print $0 >> current_manu_file
            
            chap_title = substr($0, 4)
            chap_count++
            part_count = 0 
            
            # Web Routing: Create chapter directory within the book
            chap_dir = sprintf("%s/c%03d", book_dir, chap_count)
            system("mkdir -p \"" chap_dir "\"")
            next
        }

        # Level 3 Header: Start of a new Part
        /^### / {
            close(current_file)
            if (current_manu_file != "/dev/null") print $0 >> current_manu_file
            
            part_title = substr($0, 5)
            part_count++
            
            # Web Routing: Create part markdown file
            filename = sprintf("s%03d.md", part_count)
            current_file = sprintf("%s/%s", chap_dir, filename)
            
            print "# " part_title > current_file
            
            web_file_path = current_file
            sub(base_dir "/", "", web_file_path)
            
            # Log this part into the JSONL index for later compilation.
            json_entry = sprintf("{\"book_num\": %d, \"book_title\": \"%s\", \"chap_num\": %d, \"chap_title\": \"%s\", \"part_num\": %d, \"part_title\": \"%s\", \"file_path\": \"%s\"}", 
                book_count, escape_json(book_title), 
                chap_count, escape_json(chap_title), 
                part_count, escape_json(part_title), 
                escape_json(web_file_path))
                
            print json_entry >> json_log
            next
        }
        
        # Level 4 Header: Convert to Level 2 for web presentation
        /^#### / {
            if (current_manu_file != "/dev/null") print $0 >> current_manu_file
            if (current_file != "/dev/null") {
                part_line = $0
                sub(/^#### /, "## ", part_line)
                print part_line >> current_file
            }
            next
        }

        # Regular text lines
        {
            if (current_manu_file != "/dev/null") print $0 >> current_manu_file
            if (current_file != "/dev/null") print $0 >> current_file
        }
        ' "$TMP_MD"

        echo "   Subdivisions complete. Passing the baton to Katie..."

        # Consolidate the temporary JSONL index into a fully nested JSON structure.
        jq -s '
          group_by(.book_num) | map({
            book_num: .[0].book_num,
            book_title: .[0].book_title,
            chapters: (
              group_by(.chap_num) | map({
                chap_num: .[0].chap_num,
                chap_title: .[0].chap_title,
                parts: map({
                  part_num: .part_num,
                  part_title: .part_title,
                  file_path: .file_path
                })
              })
            )
          })
        ' "$TEMP_JSONL" > "$OUT_NARRATIVE_DIR/katie.json"

        # Cleanup temporary files
        rm -f "$TEMP_JSONL"
        rm -f "$TMP_MD"

        echo "   Katie's manifest locked. Source chunks saved to manuscript vault."
    fi
done

echo "👱‍♀️ Samantha: Shatter Protocol complete!"
#!/bin/bash
# ==============================================================================
# SAMANTHA: THE NARRATIVE COMPILER
# ==============================================================================
# ARCHITECTURAL OVERVIEW:
# Samantha parses standard Markdown manuscript folders and dynamically stitches
# them into web-ready JSON indices, compiling the structured data needed by the
# frontend React client ("Katie") to render books. She also moves raw lore markdown
# files to the public deployment folders.
#
# FUTURE MAINTENANCE NOTES:
# - Relies on `awk` state management to parse hierarchical markdown headers 
#   (Book -> Chapter -> Part). If the manuscript format changes, the awk regex must be updated.
# - Employs a cache shield mechanism: it skips processing if the source files are older
#   than the generated `katie.json` manifest.
# ==============================================================================

echo "👱‍♀️ Samantha: Taking the podium. Native Modular Routing initialized!"

# Validate execution context
if [[ ! -d "books" ]]; then
    echo "   *Whistle blow!* I can't find the 'books' directory."
    exit 1
fi

# Iterate over all nested book directories
for DIR in books/*/; do
    # Extract the base folder name to use as an identifier
    BASE=$(basename "$DIR")
    
    # LOCAL SOURCES
    # Define paths to source files within the workspace
    LORE_MD="books/$BASE/$BASE-lore.md"
    MANUSCRIPT_DIR="books/$BASE/manuscript"
    
    # PUBLIC DEPLOYMENT FOLDERS
    # Target directories where the compiled artifacts will be written (resolved from /raggiesoft-deployment-tools)
    OUT_LORE_DIR="../raggiesoft-narratives/lore/$BASE"
    OUT_NARRATIVE_DIR="../raggiesoft-narratives/books/$BASE"

    # -----------------------------------------
    # PROCESS LORE
    # -----------------------------------------
    if [[ -f "$LORE_MD" ]]; then
        # Ensure the destination directory exists
        mkdir -p "$OUT_LORE_DIR"
        FINAL_WEB_LORE="$OUT_LORE_DIR/${BASE}-lore.md"
        
        # Performance check: Only copy if the source differs from the destination
        if [[ -f "$FINAL_WEB_LORE" ]] && cmp -s "$LORE_MD" "$FINAL_WEB_LORE"; then
            echo "   🛡️ [SKIP] No tempo changes in '$BASE' lore."
        else
            cp "$LORE_MD" "$FINAL_WEB_LORE"
            echo "   Flawless execution. Updated web lore file for '$BASE'."
        fi
    fi

    # -----------------------------------------
    # PROCESS NARRATIVE (The Stitch & Slice)
    # -----------------------------------------
    if [[ -d "$MANUSCRIPT_DIR" ]]; then
        # Gather all chunked files in strict alphabetical/numeric order
        # Expecting format like: 001-intro.md, 002-chapter-one.md
        SOURCE_FILES=$(find "$MANUSCRIPT_DIR" -maxdepth 1 -name "[0-9][0-9][0-9]-*.md" | sort)
        
        if [[ -n "$SOURCE_FILES" ]]; then
            MANIFEST="$OUT_NARRATIVE_DIR/katie.json"
            NEEDS_UPDATE=false
            
            # THE EFFICIENCY SHIELD
            # Skip expensive regex parsing if the destination JSON is newer than all source chunks
            if [[ ! -f "$MANIFEST" ]]; then
                NEEDS_UPDATE=true
            else
                NEWER_FILES=$(find "$MANUSCRIPT_DIR" -maxdepth 1 -name "*.md" -newer "$MANIFEST" 2>/dev/null)
                if [[ -n "$NEWER_FILES" ]]; then
                    NEEDS_UPDATE=true
                fi
            fi

            if [[ "$NEEDS_UPDATE" == false ]]; then
                echo "   🛡️ [SKIP] Modular files in '$BASE/manuscript' are unchanged."
            else
                echo "   Found updated manuscript chunks for '$BASE'. Stitching and Slicing..."
                
                # Setup destination structure
                mkdir -p "$OUT_NARRATIVE_DIR"
                # Clean the output directory to prevent orphaned files, keeping the directory itself
                find "$OUT_NARRATIVE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
                
                # Prepare temporary JSON lines file for the intermediate index
                TEMP_JSONL="$OUT_NARRATIVE_DIR/temp_index.jsonl"
                > "$TEMP_JSONL"

                # Use cat to stream all files seamlessly into AWK
                # The awk script parses markdown headers to build directory hierarchies and index JSON
                cat $SOURCE_FILES | LC_ALL=C awk -v base_dir="$OUT_NARRATIVE_DIR" -v json_log="$TEMP_JSONL" '
                
                # Sanitizes string values for JSON inclusion
                function escape_json(str) {
                    gsub(/\\/, "\\\\", str)
                    gsub(/"/, "\\\"", str)
                    gsub(/\r/, "", str)
                    gsub(/\t/, " ", str)
                    return str
                }

                # Initialize internal state counters
                BEGIN { 
                    book_count = 0
                    chap_count = 0
                    part_count = 0
                    current_file = "/dev/null"
                }

                # H1 tags define Books
                /^# / { 
                    close(current_file)
                    
                    book_title = substr($0, 3)
                    book_count++
                    chap_count = 0 
                    
                    book_dir = sprintf("%s/e%03d", base_dir, book_count)
                    system("mkdir -p \"" book_dir "\"")
                    next
                }

                # H2 tags define Chapters within Books
                /^## / {
                    close(current_file)
                    
                    chap_title = substr($0, 4)
                    chap_count++
                    part_count = 0 
                    
                    chap_dir = sprintf("%s/c%03d", book_dir, chap_count)
                    system("mkdir -p \"" chap_dir "\"")
                    next
                }

                # H3 tags define Parts within Chapters
                /^### / {
                    close(current_file)
                    
                    part_title = substr($0, 5)
                    part_count++
                    
                    # Generate the physical chunk file
                    filename = sprintf("s%03d.md", part_count)
                    current_file = sprintf("%s/%s", chap_dir, filename)
                    
                    print "# " part_title > current_file
                    
                    # Calculate relative path for frontend router
                    web_file_path = current_file
                    sub(base_dir "/", "", web_file_path)
                    
                    # Write the routing metadata line to the temporary index
                    json_entry = sprintf("{\"book_num\": %d, \"book_title\": \"%s\", \"chap_num\": %d, \"chap_title\": \"%s\", \"part_num\": %d, \"part_title\": \"%s\", \"file_path\": \"%s\"}", 
                        book_count, escape_json(book_title), 
                        chap_count, escape_json(chap_title), 
                        part_count, escape_json(part_title), 
                        escape_json(web_file_path))
                        
                    print json_entry >> json_log
                    next
                }
                
                # H4 tags are downgraded to H2 in the output HTML context
                /^#### / {
                    if (current_file != "/dev/null") {
                        part_line = $0
                        sub(/^#### /, "## ", part_line)
                        print part_line >> current_file
                    }
                    next
                }

                # Catch-all: Route standard content text to the current active output file
                {
                    if (current_file != "/dev/null") print $0 >> current_file
                }
                ' 

                echo "   Subdivisions complete. Passing the baton to Katie..."

                # Transform the flat JSON Lines index into a nested JSON structure grouping by Book -> Chapter
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

                # Cleanup the intermediate index file
                rm -f "$TEMP_JSONL"

                echo "   Katie's manifest locked for '$BASE'."
            fi
        fi
    fi
done

echo "👱‍♀️ Samantha: Run-through complete. The repository is pristine!"
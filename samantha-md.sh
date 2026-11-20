#!/bin/bash
# ==============================================================================
# SAMANTHA: THE NARRATIVE COMPILER (`samantha-md.sh`)
# ==============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Companion to `samantha-docx.sh`! Once `samantha-docx.sh` shatters a legacy
#   Word document into numbered Markdown files (`books/<slug>/manuscript/001-*.md`),
#   `samantha-md.sh` concatenates those numbered Markdown chunks in sorted order
#   (`cat $SOURCE_FILES`), slices them by `#` / `##` / `###` heading depth via
#   `awk` into `raggiesoft-narratives/books/<slug>/eXXX/cXXX/sXXX.md`, and rolls
#   up `katie.json` via `jq`—skipping unchanged books instantly using a `find -newer`
#   timestamp cache check!
#   (Note: Modern Ocean View Archives novels authored directly as `eXXX/cXXX/pXXX.md`
#   inside `raggiesoft-narratives/books/` are compiled directly by `paige.php`.)
#
# INPUTS & OUTPUTS:
#   - Reads: `books/<slug>/<slug>-lore.md` and `books/<slug>/manuscript/[0-9][0-9][0-9]-*.md`
#   - Writes: `raggiesoft-narratives/lore/<slug>/` and `raggiesoft-narratives/books/<slug>/`
# ==============================================================================

echo "👱‍♀️ Samantha: Taking the podium. Native Modular Routing initialized!"

# Validate that `books/` exists in the current working directory
if [[ ! -d "books" ]]; then
    echo "   *Whistle blow!* I can't find the 'books' directory."
    exit 1
fi

# Iterate over all nested book directories (`books/*/`)
for DIR in books/*/; do
    BASE=$(basename "$DIR")
    
    # LOCAL SOURCES
    LORE_MD="books/$BASE/$BASE-lore.md"
    MANUSCRIPT_DIR="books/$BASE/manuscript"
    
    # PUBLIC DEPLOYMENT FOLDERS (resolved relative to `raggiesoft-deployment-tools/`)
    if [[ -d "../raggiesoft-servers" ]]; then
        SERVER_ROOT="../raggiesoft-servers"
    else
        SERVER_ROOT=".."
    fi
    if [[ -d "$SERVER_ROOT/raggiesoft-novels" ]]; then
        NARRATIVES_ROOT="$SERVER_ROOT/raggiesoft-novels"
    else
        NARRATIVES_ROOT="$SERVER_ROOT/raggiesoft-narratives"
    fi
    OUT_LORE_DIR="$NARRATIVES_ROOT/lore/$BASE"
    OUT_NARRATIVE_DIR="$NARRATIVES_ROOT/books/$BASE"

    # -----------------------------------------
    # 1. PROCESS LORE (`cmp -s` Byte-Identical Skip)
    # -----------------------------------------
    if [[ -f "$LORE_MD" ]]; then
        mkdir -p "$OUT_LORE_DIR"
        FINAL_WEB_LORE="$OUT_LORE_DIR/${BASE}-lore.md"
        
        if [[ -f "$FINAL_WEB_LORE" ]] && cmp -s "$LORE_MD" "$FINAL_WEB_LORE"; then
            echo "   🛡️ [SKIP] No tempo changes in '$BASE' lore."
        else
            cp "$LORE_MD" "$FINAL_WEB_LORE"
            echo "   Flawless execution. Updated web lore file for '$BASE'."
        fi
    fi

    # -----------------------------------------
    # 2. PROCESS NARRATIVE ("The Stitch & Slice")
    # -----------------------------------------
    if [[ -d "$MANUSCRIPT_DIR" ]]; then
        # Gather 3-digit-prefixed files (`001-book-one.md`, `002-book-two.md`) in sorted numeric order
        SOURCE_FILES=$(find "$MANUSCRIPT_DIR" -maxdepth 1 -name "[0-9][0-9][0-9]-*.md" | sort)
        
        if [[ -n "$SOURCE_FILES" ]]; then
            MANIFEST="$OUT_NARRATIVE_DIR/katie.json"
            NEEDS_UPDATE=false
            
            # THE EFFICIENCY SHIELD (`find ... -newer "$MANIFEST"`):
            # Much like `make` in C/C++, `find -newer` asks the filesystem if ANY `.md` chunk
            # was modified after `katie.json` was last built. If none are newer, skip in <2ms!
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
                
                mkdir -p "$OUT_NARRATIVE_DIR"
                # Remove old generated era folders inside `$OUT_NARRATIVE_DIR` while keeping the root directory
                find "$OUT_NARRATIVE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
                
                TEMP_JSONL="$OUT_NARRATIVE_DIR/temp_index.jsonl"
                > "$TEMP_JSONL"

                # Stream all sorted `001-*.md` chunks seamlessly via `cat ... | awk` so `awk` sees one unified stream:
                #   - `# Title`   -> Era `e001/`
                #   - `## Title`  -> Chapter `e001/c001/`
                #   - `### Title` -> Scene `e001/c001/s001.md` + `.jsonl` index entry
                #   - `#### Sub`  -> Promoted to `## Sub` inside the scene Markdown
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

                # Slurp (`jq -s`) the flat `.jsonl` rows and `group_by` Book -> Chapter -> Parts into `katie.json`
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

                rm -f "$TEMP_JSONL"

                echo "   Katie's manifest locked for '$BASE'."
            fi
        fi
    fi
done

echo "👱‍♀️ Samantha: Run-through complete. The repository is pristine!"
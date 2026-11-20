#!/bin/bash
# ============================================================================
# Architectural Block: samantha-docx.sh (Legacy DOCX Shatter Protocol)
# ============================================================================
# PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
#   Before our books moved to native Markdown folders (`eXXX/cXXX/pXXX.md`
#   compiled by `paige.php`), early manuscripts were written as single giant
#   Microsoft Word `.docx` files (`books/<name>/<name>.docx`).
#   `samantha-docx.sh` ("Samantha: Passive DOCX Extraction & Shatter Protocol")
#   converts those legacy Word `.docx` manuscripts into GitHub-Flavored Markdown
#   via **Pandoc**, "shatters" the giant file into clean `e001/c001/s001.md`
#   chapter chunks using an **AWK state machine** driven by `#` / `##` / `###`
#   heading levels, and compiles a nested `katie.json` table-of-contents via `jq`!
#
# BUILT-IN NON-DESTRUCTIVE SAFETY SHIELDS:
#   1. Lore Timestamp Shield (`-nt` = "newer than"): If a local `.md` lore file
#      was edited more recently than the `.docx`, Pandoc skips it so manual
#      Markdown edits are NEVER overwritten!
#   2. Manuscript Chunk Shield: If `books/<name>/manuscript/001-*.md` chunks
#      already exist on disk, Samantha skips `.docx` shattering completely and
#      lets `samantha-md.sh` / `paige.php` own the native Markdown files.
#
# INPUTS & OUTPUTS:
#   - Reads: `books/<slug>/<slug>.docx` and `books/<slug>/<slug>-lore.docx`
#   - Writes: `books/<slug>/manuscript/001-*.md`, `raggiesoft-narratives/lore/<slug>/`,
#     and `raggiesoft-narratives/books/<slug>/eXXX/cXXX/sXXX.md` + `katie.json`.
# ============================================================================

echo "👱‍♀️ Samantha: Taking the podium. Passive DOCX Extraction Protocol initialized!"

# Fail fast if the local `books/` staging folder is not present in the current working directory.
if [[ ! -d "books" ]]; then
    echo "   *Whistle blow!* I can't find the 'books' directory. Are we on the wrong practice field?"
    exit 1
fi

# Iterate over each book staging folder (`books/*/` trailing slash matches directories only).
for DIR in books/*/; do
    BASE=$(basename "$DIR")
    
    # LOCAL STAGING SOURCES
    NARRATIVE_DOCX="books/$BASE/$BASE.docx"
    LORE_DOCX="books/$BASE/$BASE-lore.docx"
    LOCAL_LORE_MD="books/$BASE/$BASE-lore.md"
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
    FINAL_WEB_LORE="$OUT_LORE_DIR/${BASE}-lore.md"

    # -----------------------------------------
    # 1. PROCESS LORE DOCX -> GFM MARKDOWN
    # -----------------------------------------
    if [[ -f "$LORE_DOCX" ]]; then
        # BASH `[[ "$FILE_A" -nt "$FILE_B" ]]` ("Newer Than" Modification-Time Check):
        # Protects hand-edited Markdown if `$LOCAL_LORE_MD` has a newer timestamp than `$LORE_DOCX`!
        if [[ -f "$LOCAL_LORE_MD" ]] && [[ "$LOCAL_LORE_MD" -nt "$LORE_DOCX" ]]; then
            echo "   🛡️ [PROTECT] Local '$LOCAL_LORE_MD' is newer than DOCX. Skipping Pandoc."
        else
            echo "   Found legacy DOCX lore sheet for '$BASE'. Extracting..."
            # `pandoc -t gfm --wrap=none`: Converts Word `.docx` to GitHub-Flavored Markdown
            # (`-t gfm`) keeping each paragraph on one clean line (`--wrap=none`).
            pandoc --verbose "$LORE_DOCX" -t gfm --wrap=none -o "$LOCAL_LORE_MD"
        fi
        
        # Copy to public `raggiesoft-narratives/lore/` only if bytes actually changed (`cmp -s`)
        if [[ -f "$LOCAL_LORE_MD" ]]; then
            mkdir -p "$OUT_LORE_DIR"
            if [[ -f "$FINAL_WEB_LORE" ]] && cmp -s "$LOCAL_LORE_MD" "$FINAL_WEB_LORE"; then
                echo "   No tempo changes in lore sync. Skipping."
            else
                cp "$LOCAL_LORE_MD" "$FINAL_WEB_LORE"
                echo "   Updated web lore file: $FINAL_WEB_LORE"
            fi
        fi
    fi

    # -----------------------------------------
    # 2. PROCESS NARRATIVE DOCX (Passive Shatter Mode)
    # -----------------------------------------
    if [[ -f "$NARRATIVE_DOCX" ]]; then
        # SHIELD CHECK: Count existing numbered Markdown chunks (`001-*.md`); if `> 0`, never overwrite them!
        MD_COUNT=$(find "$MANUSCRIPT_DIR" -maxdepth 1 -name "[0-9][0-9][0-9]-*.md" 2>/dev/null | wc -l)
        
        if [[ -d "$MANUSCRIPT_DIR" ]] && [[ $MD_COUNT -gt 0 ]]; then
            echo "   🛡️ [PROTECT] Native Markdown chunks found in '$MANUSCRIPT_DIR'. Skipping DOCX shatter."
            continue
        fi
        
        echo "   Found legacy DOCX narrative score for '$BASE'. Shattering into manuscript chunks..."
        
        # Step A: Convert the entire monolithic `.docx` into one temporary Markdown file (`$TMP_MD`)
        TMP_MD="books/$BASE/${BASE}_tmp.md"
        if ! pandoc --verbose "$NARRATIVE_DOCX" -t gfm --wrap=none -o "$TMP_MD"; then
            echo "   *Whistle blow!* Permission error on '$NARRATIVE_DOCX'."
            continue
        fi
        
        mkdir -p "$MANUSCRIPT_DIR"
        mkdir -p "$OUT_NARRATIVE_DIR"
        
        # Wipe stale output subfolders inside `$OUT_NARRATIVE_DIR` while keeping `$OUT_NARRATIVE_DIR` itself (`-mindepth 1`)
        find "$OUT_NARRATIVE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        
        TEMP_JSONL="$OUT_NARRATIVE_DIR/temp_index.jsonl"
        > "$TEMP_JSONL"

        # Step B: HOW THIS EMBEDDED `awk` STATE MACHINE WORKS (100-LEVEL INTRO):
        #   `awk` reads `$TMP_MD` top-to-bottom, one line (`$0`) at a time (`LC_ALL=C` speeds up byte-level ASCII regexes,
        #   and `-v name=value` passes Bash variables into `awk`!).
        #   - `BEGIN { ... }` runs once before Line 1 to initialize counters (`book_count`, `chap_count`, `part_count`).
        #   - `/^# /`   matches Level-1 headings -> increments `book_count`, creates `e001/`, opens `manuscript/001-slug.md`.
        #   - `/^## /`  matches Level-2 headings -> increments `chap_count`, creates `e001/c001/`.
        #   - `/^### /` matches Level-3 headings -> increments `part_count`, opens `e001/c001/s001.md`, and logs JSONL metadata.
        #   - `{ ... }` at the bottom matches every normal prose line and appends (`>>`) it into the currently open file!
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

        # Step C: Roll up flat `.jsonl` lines into a nested `Book -> Chapters -> Parts` JSON tree via `jq -s` ("slurp" + `group_by`)
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
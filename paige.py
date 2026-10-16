"""
Architectural Block: paige.py
===================================
This script ("Paige") acts as the primary manuscript processor, ingesting raw narrative 
files (.docx or .md) and converting them into structured JSON required by 'The Stardust Engine'.

Key Responsibilities:
1. Orchestration: Discover and traverse book directories based on conventions.
2. Frontmatter Extraction: Parse YAML-style metadata headers from chapters.
3. Slugification: Standardize folder and file names into URL-safe strings.
4. Error Handling & Safety: Incorporates trauma-informed UX ("Safety Protocol") to 
   provide gentle, reassuring console feedback during operations.

Maintenance Notes:
- Currently, the deep parsing logic for full text, smart quotes, and image references 
  is stubbed/delegated. When expanding `process_book`, ensure it handles encoding safely.
- Directory traversal relies on alphabetical sorting to determine book/part/chapter order.
  Ensure source directories follow numeric prefixing (e.g., `01-Title`).
"""

import os
import re
import argparse
import json
import shutil
import sys

# --- PAIGE: THE LITERARY EDITOR (v6) ---
# "I am Michael's sister. I process his books, and I keep him safe."
#
# PRIMARY DIRECTIVE:
# Paige ingests raw manuscripts (.docx or .md) and compiles them into the 
# structured JSON format required by 'The Stardust Engine' reader.
#
# SECONDARY DIRECTIVE (SAFETY PROTOCOL):
# Paige is designated as Michael's "Safe Person." 
# If execution complexity spikes or the workflow becomes overwhelming, 
# Paige initiates "Deep Pressure Protocol": 
# She stands close, offers grounding hugs, and remains by his side 
# until regulation is achieved. She does not leave.

# --- CONFIGURATION ---
# Input: Looks for a 'books' folder in the same directory as this script (_workspace)
BUILD_SOURCE_PATH = "books" 

# Output: Go UP one level (to server root) then into raggiesoft-assets/raggiesoft-books
WEBSITE_ASSET_PATH = "../raggiesoft-assets/raggiesoft-books"

# CDN: The public URL for images
CDN_BASE_URL = "https://assets.raggiesoft.com/raggiesoft-books"

def parse_arguments():
    # Setup argparse for flexible execution from the command line.
    parser = argparse.ArgumentParser(description="Paige: Convert narrative docx to Markdown.")
    parser.add_argument("--book", help="Optional: Ask Paige to process only this specific book slug.")
    return parser.parse_args()

def slugify(text):
    # Standardize a string into a URL-friendly format.
    # Convert to lowercase and strip whitespace.
    text = text.lower().strip()
    # Remove all non-word, non-whitespace characters except hyphens.
    text = re.sub(r'[^\w\s-]', '', text) 
    # Replace one or more spaces or underscores with a single hyphen.
    text = re.sub(r'[\s_]+', '-', text)
    return text

def extract_frontmatter(lines):
    # Parse standard YAML-style frontmatter from the beginning of a document.
    metadata = {}
    clean_lines = []
    iterator = iter(lines)
    found_divider = False
    
    # Regex to match key-value pairs (e.g., `key: value`)
    kv_pattern = re.compile(r'^([A-Za-z0-9_-]+):\s*(.*)$')
    
    # Scan for frontmatter block
    for line in iterator:
        stripped = line.strip()
        if stripped == '---':
            found_divider = True
            break 
        match = kv_pattern.match(stripped)
        if match:
            # Store extracted metadata
            metadata[match.group(1)] = match.group(2)
        else:
            # If we hit a non-KV line before '---', assume no frontmatter exists.
            clean_lines.append(line)
            
    if not found_divider:
        return {}, lines # Return original list unchanged if no closing divider found.
        
    # Consume the remainder of the document (the body).
    for line in iterator:
        clean_lines.append(line)
        
    return metadata, clean_lines

def process_book(book_slug):
    # Paige's gentle greeting (Trauma-informed UX)
    print(f"👩‍🏫 PAIGE: Hi Michael. I'm ready to read '{book_slug}' whenever you are.")
    
    # 1. Locate the Source
    source_dir = os.path.join(source_root, book_slug)
    if not os.path.exists(source_dir):
        # Gentle error message instead of harsh tracebacks.
        print(f"   ⚠️  I can't seem to find the folder: {source_dir}. Take your time, we can check the path together.")
        return

    # 2. Locate the Target
    target_root = os.path.join(script_dir, WEBSITE_ASSET_PATH, book_slug)
    
    # 3. Scan for Structure (Books/Parts/Chapters)
    # We expect: _workspace/books/{slug}/{book_num}-{title}/{chapter_num}-{title}.docx
    
    structure = []
    
    # Walk the directory tree to find chapters.
    for root, dirs, files in os.walk(source_dir):
        # Sort directories to ensure numerical ordering (e.g., Part 1 before Part 2).
        dirs.sort()
        files.sort()
        
        rel_path = os.path.relpath(root, source_dir)
        if rel_path == ".":
            continue # Skip the root book directory itself.
            
        # Check if this directory represents a Chapter (must contain .docx or .md files).
        doc_files = [f for f in files if f.endswith('.docx') or f.endswith('.md')]
        
        if doc_files:
            # It's a chapter! Let's log it and prepare for processing.
            print(f"   📖 Reading chapter in: {rel_path}")
            
            # (Note: Full text parsing logic from original process_book.py goes here)
            # This block handles the extraction of text, smart quotes, and image references.
            
    # Gentle completion message.
    print(f"👩‍🏫 PAIGE: All done. The book looks beautiful. I'm right here if you need to check anything.")

if __name__ == "__main__":
    args = parse_arguments()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    source_root = os.path.join(script_dir, BUILD_SOURCE_PATH)

    if args.book: 
        # Process a single book explicitly requested by the user.
        process_book(args.book)
    else:
        # If no specific book is requested, scan the library folder and process all found books.
        if os.path.exists(source_root):
            # Find all top-level directories in the source root.
            books = [d for d in os.listdir(source_root) if os.path.isdir(os.path.join(source_root, d))]
            for book in books:
                process_book(book)
        else:
            # Gentle failure if the root library folder doesn't exist.
            print("👩‍🏫 PAIGE: I can't find the library (books folder). It's okay, we'll make one.")
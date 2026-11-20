// ==============================================================================
// ARCHITECTURAL BLOCK: GEMINI CHAT LOGGER (gemini-chat-logger.js)
// ==============================================================================
// PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
//   Unlike our Node.js command-line scripts, this JavaScript snippet is meant to
//   be pasted directly into Chrome DevTools' **Console** tab on a Google Gemini
//   web chat page! When a brainstorming thread grows to hundreds of messages,
//   selecting text or copying to the OS clipboard often truncates or freezes.
//   This script walks the live HTML page (the DOM), grabs every User message and
//   Model reply in order, formats them as Markdown, builds an in-memory file
//   (`Blob`), and triggers a normal browser `.md` file download automatically.
//
// HOW AN "IIFE" `(function extractChat() { ... })();` WORKS:
//   Wrapping a function inside parentheses `(function ... )` and immediately
//   adding `()` at the end is called an **Immediately Invoked Function Expression**.
//   1. It executes right away as soon as you press Enter in DevTools.
//   2. Every `const` and `let` variable inside stays private to this function's
//      scope, so pasting it multiple times never clashes with variables on the web page!
// ==============================================================================

(function extractChat() {
    // --------------------------------------------------------------------------
    // 1. TARGETING DOM ELEMENTS
    // --------------------------------------------------------------------------
    // `document.querySelectorAll('selectorA, selectorB')` searches the entire live
    // HTML page for elements matching either CSS class and returns a `NodeList`
    // in exact top-to-bottom document order, preserving the conversation flow.
    const messageNodes = document.querySelectorAll('.query-text-line, .response-container-content');
    
    // Safety check: if the page lazy-loads older messages as you scroll, warn if empty.
    if (messageNodes.length === 0) {
        console.error("No nodes found. Make sure you are scrolled to the top so everything is rendered.");
        return;
    }

    // --------------------------------------------------------------------------
    // 2. EXTRACT AND FORMAT TEXT
    // --------------------------------------------------------------------------
    // `messageNodes` is a DOM `NodeList` (which lacks `.map()`), so `Array.from(...)`
    // converts it into a real JavaScript `Array`:
    //   - `.map((node) => ...)` transforms each HTML element into a Markdown string.
    //   - `.join('\n\n---\n\n')` glues all message strings together separated by horizontal rules.
    const chatLog = Array.from(messageNodes).map((node) => {
        let speaker = "";
        
        // `node.classList.contains(...)` checks which CSS class is on this DOM element
        // so we can label whether the human user or Gemini spoke.
        if (node.classList.contains('query-text-line')) {
            speaker = "**User:**\n";
        } else if (node.classList.contains('response-container-content')) {
            speaker = "**Model:**\n";
        }
        
        // `node.innerText` reads only the human-visible rendered text (stripping HTML tags),
        // and `.trim()` removes extra blank lines at the start/end.
        return speaker + node.innerText.trim();
    }).join('\n\n---\n\n'); // Separate messages with a Markdown horizontal rule

    // --------------------------------------------------------------------------
    // 3. PACKAGE INTO BLOB (IN-MEMORY VIRTUAL FILE)
    // --------------------------------------------------------------------------
    // A `Blob` (Binary Large Object) lets browser JavaScript construct a virtual
    // file in RAM without touching a backend server or the size-limited clipboard.
    // `URL.createObjectURL(blob)` mints a temporary `blob:https://...` address pointing to that RAM buffer.
    const blob = new Blob([chatLog], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    
    // --------------------------------------------------------------------------
    // 4. FORCE SILENT DOWNLOAD
    // --------------------------------------------------------------------------
    // Standard browser trick to save a Blob to the user's `Downloads/` folder:
    // create an invisible `<a href="blob:..." download="filename.md">` link,
    // attach it to `document.body`, and call `.click()` programmatically!
    const a = document.createElement('a');
    a.href = url;
    a.download = 'meridian-city-lore-backup.md'; // Default export filename
    document.body.appendChild(a);
    a.click(); // Trigger the browser's native Save File dialog / Downloads bar
    
    // --------------------------------------------------------------------------
    // 5. CLEANUP (PREVENT MEMORY LEAKS)
    // --------------------------------------------------------------------------
    // Remove our temporary `<a>` element from the page and call `URL.revokeObjectURL`
    // so the browser frees the RAM held by `blob`.
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    
    console.log("Extraction complete. Markdown file downloaded.");
})();

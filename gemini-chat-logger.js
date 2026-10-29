// ==============================================================================
// ARCHITECTURAL BLOCK: GEMINI CHAT LOGGER
// ==============================================================================
// This is an Immediately Invoked Function Expression (IIFE) designed to be 
// executed directly within a browser's developer console.
// 
// Key Responsibilities:
// 1. Scrape DOM elements corresponding to user queries and model responses.
// 2. Format the scraped content into a readable Markdown structure.
// 3. Generate a local file (Blob) in the browser memory.
// 4. Trigger an automatic download of the resulting Markdown file to bypass
//    clipboard copy-paste limits for large chat histories.
// ==============================================================================

(function extractChat() {
    // --------------------------------------------------------------------------
    // 1. TARGETING DOM ELEMENTS
    // --------------------------------------------------------------------------
    // Target both user queries and model responses. 
    // querySelectorAll automatically returns them in document order, preserving
    // the conversational sequence.
    const messageNodes = document.querySelectorAll('.query-text-line, .response-container-content');
    
    // Safety check: ensure we actually found chat nodes. 
    // If lazy loading is used, the user may need to scroll up.
    if (messageNodes.length === 0) {
        console.error("No nodes found. Make sure you are scrolled to the top so everything is rendered.");
        return;
    }

    // --------------------------------------------------------------------------
    // 2. EXTRACT AND FORMAT TEXT
    // --------------------------------------------------------------------------
    // Convert the NodeList to an Array and map over each element to construct
    // a Markdown string representation.
    const chatLog = Array.from(messageNodes).map((node) => {
        let speaker = "";
        
        // Check which class the node has to apply the correct Markdown speaker label
        if (node.classList.contains('query-text-line')) {
            speaker = "**User:**\n";
        } else if (node.classList.contains('response-container-content')) {
            speaker = "**Model:**\n";
        }
        
        // Combine the speaker label with the inner text, stripping leading/trailing whitespace
        return speaker + node.innerText.trim();
    }).join('\n\n---\n\n'); // Separate messages with a Markdown horizontal rule

    // --------------------------------------------------------------------------
    // 3. PACKAGE INTO BLOB
    // --------------------------------------------------------------------------
    // Package the string into a Blob to bypass clipboard limits, which can 
    // fail for extremely long conversation logs.
    const blob = new Blob([chatLog], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    
    // --------------------------------------------------------------------------
    // 4. FORCE SILENT DOWNLOAD
    // --------------------------------------------------------------------------
    // Create a temporary hidden anchor tag to trigger the browser's download API
    const a = document.createElement('a');
    a.href = url;
    a.download = 'meridian-city-lore-backup.md'; // Default export filename
    document.body.appendChild(a);
    a.click(); // Trigger the download
    
    // --------------------------------------------------------------------------
    // 5. CLEANUP
    // --------------------------------------------------------------------------
    // Remove the temporary anchor and release the Blob URL memory
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    
    console.log("Extraction complete. Markdown file downloaded.");
})();

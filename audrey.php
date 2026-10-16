<?php
/**
 * Architectural Block: audrey.php
 * ===================================
 * Audrey ("The Production Coordinator") is a standalone, single-file PHP application
 * serving as a metadata intake workbench for music releases. It generates structured
 * `album.json` and `tracks.json` assets used by the Stardust Engine.
 *
 * Key Responsibilities:
 * 1. Form Intake: Provides a Frutiger Aero themed web GUI for data entry.
 * 2. Schema Mapping: Maps user inputs directly into Schema.org `MusicAlbum` and `MusicGroup` JSON-LD standards.
 * 3. Track Reconstruction: Parses dynamic POST arrays to assemble multi-disc track listings.
 * 4. Output Generation: Produces formatted JSON payloads ready for copy-pasting into project directories.
 *
 * Maintenance Notes:
 * - This file mixes PHP logic, inline CSS, and vanilla JS for portability (zero dependencies).
 * - If Schema.org standards for `MusicAlbum` evolve, update the `$albumData` array structure.
 * - The dynamic track form rows rely on a JS counter (`sequentialCounter`). If the DOM structure
 *   of the track block changes, ensure the `name="tracks[...][...]"` attribute matrix remains intact.
 */

// audrey.php - Audrey: The Production Coordinator (v1.1.0)
// Self-contained Frutiger Aero Media Workbench for multi-disc studio releases.

$message = "";
$albumJsonOut = "";
$tracksJsonOut = "";

// Process the form submission
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    // 1. Map core album details to Schema.org standards.
    // Falls back to safe defaults (e.g., 'DistroKid', 'Pending Distribution') if empty.
    $albumData = [
        "@context" => "https://schema.org",
        "@type" => ["MusicAlbum", "Product"],
        "name" => $_POST['album_name'] ?? '',
        "byArtist" => [
            "@type" => "MusicGroup",
            "name" => $_POST['artist_name'] ?? ''
        ],
        "isRockOpera" => isset($_POST['is_rock_opera']) ? true : false,
        "albumProductionType" => $_POST['production_type'] ?? 'StudioAlbum',
        "albumReleaseType" => $_POST['release_type'] ?? 'AlbumRelease',
        "genre" => $_POST['genre'] ?? '',
        "datePublished" => $_POST['date_published'] ?? '',
        "temporalCoverage" => $_POST['temporal_coverage'] ?? '',
        "description" => $_POST['description'] ?? '',
        "gtin12" => $_POST['gtin12'] ?? '',
        "publisher" => [
            "@type" => "Organization",
            "name" => $_POST['publisher_name'] ?? 'DistroKid'
        ],
        "conditionsOfAccess" => $_POST['access_conditions'] ?? 'Pending Distribution',
        "creativeWorkStatus" => $_POST['work_status'] ?? 'Upcoming Release'
    ];

    // 2. Map Multi-Disc Track Listing Arrays from dynamic inputs.
    $tracksData = ["tracks" => []];
    
    // Ensure the track array exists and iterate over submitted rows.
    if (isset($_POST['tracks']) && is_array($_POST['tracks'])) {
        foreach ($_POST['tracks'] as $track) {
            // Skip empty/malformed rows
            if (empty($track['title'])) continue;
            
            // Build the track object, casting disc and track numbers to integers.
            $tracksData['tracks'][] = [
                "fileName" => $track['file_name'] ?? '',
                "title" => $track['title'] ?? '',
                "isrc" => $track['isrc'] ?? '',
                "masterWavPath" => "studio/" . ($track['file_name'] ?? ''),
                "disc" => (int)($track['disc_num'] ?? 1),
                "discName" => $track['disc_name'] ?? '',
                "track" => (int)($track['track_num'] ?? 1),
                "suiteName" => $track['suite_name'] ?? '',
                "suiteTrack" => $track['suite_track'] ?? '',
                "legacyTier" => $track['legacy_tier'] ?? '',
                "loreNote" => $track['lore_note'] ?? '',
                "duration" => $track['duration'] ?? ''
            ];
        }
    }

    // Output formatted JSON string payloads.
    $albumJsonOut = json_encode($albumData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    $tracksJsonOut = json_encode($tracksData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    
    $message = "SUCCESS";
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Audrey // Studio Intake Workbench</title>
    <style>
        /* --- RAGGIESOFT FRUTIGER AERO CORE PALETTE --- */
        :root {
            --mpr-blue-500: #0082E6;
            --mpr-blue-600: #005BB5;
            --mpr-cyan-400: #00E5FF;
            --mpr-grass-500: #38E54D;
            
            /* Light Mode Defaults */
            --bs-body-bg: #F4F9FD;
            --bs-body-color: #1A2A3A;
            --bs-primary: var(--mpr-blue-500);
            --bs-secondary: #5F7A8C;
            --bs-border-color: #CBE0F0;
            --raggie-glass-bg: rgba(255, 255, 255, 0.65);
            --raggie-glass-border: rgba(0, 130, 230, 0.3);
            --raggie-gloss-highlight: rgba(255, 255, 255, 0.6);
            --input-bg: #ffffff;
            --input-color: #1A2A3A;
            --text-glow: rgba(0, 130, 230, 0.4);
            
            --font-stack: 'Ubuntu', system-ui, -apple-system, sans-serif;
        }

        /* --- AUTOMATED SYSTEM-LEVEL DARK AERO OVERRIDES --- */
        @media (prefers-color-scheme: dark) {
            :root {
                --bs-body-bg: #070B14;
                --bs-body-color: #E2F1FF;
                --bs-primary: var(--mpr-cyan-400);
                --bs-secondary: #859DB3;
                --bs-border-color: #1A2B40;
                --raggie-glass-bg: rgba(7, 11, 20, 0.75);
                --raggie-glass-border: rgba(0, 229, 255, 0.3);
                --raggie-gloss-highlight: rgba(0, 229, 255, 0.15);
                --input-bg: #0A111C;
                --input-color: #E2F1FF;
                --text-glow: rgba(0, 229, 255, 0.6);
            }
        }

        /* --- GLOBAL LAYOUT & SELECTION --- */
        html, body {
            max-width: 100%;
            overflow-x: hidden;
            background-color: var(--bs-body-bg);
            color: var(--bs-body-color);
            font-family: var(--font-stack);
            margin: 0;
            padding: 0;
        }

        ::selection { background: rgba(0, 130, 230, 0.4); }
        @media (prefers-color-scheme: dark) {
            ::selection { background: rgba(0, 229, 255, 0.4); }
        }

        /* --- RECYCLING AERO SCROLLBARS --- */
        ::-webkit-scrollbar { width: 14px; }
        ::-webkit-scrollbar-track { background: rgba(0, 0, 0, 0.05); }
        ::-webkit-scrollbar-thumb {
            background: linear-gradient(90deg, #b0c4de 0%, #8fa8c7 100%);
            border-radius: 10px;
            border: 3px solid transparent;
            background-clip: padding-box;
        }
        @media (prefers-color-scheme: dark) {
            ::-webkit-scrollbar-track { background: rgba(0, 0, 0, 0.3); }
            ::-webkit-scrollbar-thumb { background: linear-gradient(90deg, #1A2B40 0%, #2A4365 100%); }
        }

        /* --- STRUCTURAL LAYOUT --- */
        .aero-header {
            background-color: var(--raggie-glass-bg);
            backdrop-filter: blur(16px) saturate(120%);
            -webkit-backdrop-filter: blur(16px) saturate(120%);
            border-bottom: 1px solid var(--raggie-glass-border);
            padding: 20px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.05);
        }

        .header-content {
            max-width: 1200px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
        }

        .brand-title {
            font-size: 1.5rem;
            font-weight: 700;
            margin: 0;
            text-shadow: 0 1px 2px rgba(255, 255, 255, 0.3);
            color: var(--bs-body-color);
        }
        @media (prefers-color-scheme: dark) {
            .brand-title { text-shadow: 0 1px 5px rgba(0, 229, 255, 0.4); }
        }

        .terminal-sticky {
            background: #000;
            border: 1px solid #333;
            color: #00ff00;
            font-family: 'Courier New', monospace;
            padding: 8px 15px;
            border-radius: 6px;
            font-size: 0.85rem;
            box-shadow: inset 0 2px 4px rgba(0,0,0,0.5);
        }

        .main-container {
            max-width: 1200px;
            margin: 40px auto;
            padding: 0 20px;
        }

        /* --- VOLUMETRIC GLASS HUD PANELS --- */
        .hud-panel {
            backdrop-filter: blur(8px) saturate(120%);
            -webkit-backdrop-filter: blur(8px) saturate(120%);
            border-radius: 12px;
            padding: 30px;
            margin-bottom: 35px;
            background: linear-gradient(135deg, rgba(0, 130, 230, 0.04) 0%, rgba(0, 130, 230, 0.01) 100%);
            border: 1px solid var(--raggie-glass-border);
            box-shadow: 0 8px 32px rgba(0, 85, 150, 0.05), inset 0 1px 0 rgba(255, 255, 255, 0.4);
        }
        @media (prefers-color-scheme: dark) {
            .hud-panel {
                background: linear-gradient(135deg, rgba(0, 229, 255, 0.04) 0%, rgba(0, 229, 255, 0.01) 100%);
                box-shadow: inset 0 1px 0 rgba(0, 229, 255, 0.1), 0 0 20px rgba(0, 229, 255, 0.02);
            }
        }

        .hud-success {
            border-left: 5px solid var(--mpr-grass-500);
            background: linear-gradient(135deg, rgba(56, 229, 77, 0.08) 0%, rgba(56, 229, 77, 0.01) 100%);
        }

        h2 {
            font-size: 1.35rem;
            margin-top: 0;
            margin-bottom: 25px;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            border-bottom: 1px solid var(--bs-border-color);
            padding-bottom: 8px;
            color: var(--bs-body-color);
        }

        /* --- ACCESSIBLE FORM HANDLING --- */
        .form-grid {
            display: grid;
            grid-template-columns: repeat(12, 1fr);
            gap: 20px;
        }

        .col-4 { grid-column: span 4; }
        .col-6 { grid-column: span 6; }
        .col-12 { grid-column: span 12; }

        @media (max-width: 768px) {
            .col-4, .col-6 { grid-column: span 12; }
        }

        .field-group {
            display: flex;
            flex-direction: column;
        }

        /* WCAG AAA Contrast Approved Labels */
        label {
            font-size: 0.85rem;
            font-weight: 700;
            margin-bottom: 6px;
            color: var(--bs-body-color);
        }

        input[type="text"], input[type="number"], select, textarea {
            background-color: var(--input-bg);
            color: var(--input-color);
            border: 1px solid var(--bs-border-color);
            border-radius: 6px;
            padding: 10px 12px;
            font-size: 0.95rem;
            font-family: var(--font-stack);
            box-shadow: inset 0 1px 3px rgba(0,0,0,0.05);
            box-sizing: border-box;
        }

        input:focus, select:focus, textarea:focus {
            outline: 2px solid var(--bs-primary);
            outline-offset: 1px;
            box-shadow: 0 0 10px var(--text-glow);
        }

        .checkbox-container {
            display: flex;
            align-items: center;
            gap: 10px;
            cursor: pointer;
            font-weight: 700;
            font-size: 0.95rem;
            margin-top: 25px;
        }

        .checkbox-container input {
            width: 18px;
            height: 18px;
            cursor: pointer;
        }

        /* --- DYNAMIC TRACK ROW RESTRUCTURING --- */
        .track-block {
            background: rgba(0, 0, 0, 0.02);
            border: 1px dashed var(--bs-border-color);
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 20px;
        }
        @media (prefers-color-scheme: dark) {
            .track-block { background: rgba(255, 255, 255, 0.01); }
        }

        /* --- THE AERO GEL AND NEON BUTTON SYSTEMS --- */
        .btn {
            border-radius: 50rem !important;
            padding: 10px 24px;
            font-size: 0.9rem;
            font-weight: 600 !important;
            cursor: pointer;
            border: none;
            display: inline-block;
            text-align: center;
            text-decoration: none;
        }

        /* Light Mode Gel Layout // Dark Mode Neon Bloom */
        .btn-primary {
            color: #ffffff !important;
            background: linear-gradient(180deg, #42AADB 0%, #0082E6 48%, #005BB5 52%, #004b96 100%) !important;
            border: 1px solid #003e7a !important;
            box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.6), 0 2px 4px rgba(0, 0, 0, 0.2) !important;
            text-shadow: 0 1px 2px rgba(0, 0, 0, 0.3) !important;
        }

        .btn-secondary {
            background: rgba(0, 0, 0, 0.05);
            border: 1px solid var(--bs-border-color);
            color: var(--bs-body-color);
        }

        /* REDUCED MOTION SAFE ENVIRONMENT */
        @media (prefers-reduced-motion: no-preference) {
            .btn, input, select, textarea {
                transition: all 0.2s ease-in-out !important;
            }
            .btn-primary:hover {
                transform: translateY(-1px) !important;
            }
            .btn-primary:active {
                transform: translateY(1px) !important;
            }
        }

        .btn-primary:hover, .btn-primary:focus {
            background: linear-gradient(180deg, #5ebcf0 0%, #1a96f0 48%, #006dd9 52%, #005bb5 100%) !important;
            box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.9), 0 4px 8px rgba(0, 0, 0, 0.3) !important;
            outline: 2px solid transparent;
        }

        @media (prefers-color-scheme: dark) {
            [data-bs-theme="dark"] .btn-primary, .btn-primary {
                background: linear-gradient(180deg, #00e5ff 0%, #00c6dd 48%, #00a4b8 52%, #008393 100%) !important;
                border: 1px solid #005c66 !important;
                color: #000000 !important;
                text-shadow: 0 1px 1px rgba(255, 255, 255, 0.5) !important;
                box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.7), 0 0 12px rgba(0, 229, 255, 0.4) !important;
            }
            [data-bs-theme="dark"] .btn-primary:hover, .btn-primary:hover, .btn-primary:focus {
                background: linear-gradient(180deg, #80f2ff 0%, #00e5ff 48%, #00c6dd 52%, #00a4b8 100%) !important;
                box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.9), 0 0 25px rgba(0, 229, 255, 0.8) !important;
            }
        }

        .json-pane {
            background: #02060c;
            color: #00E5FF;
            font-family: 'Courier New', monospace;
            padding: 20px;
            border-radius: 8px;
            width: 100%;
            height: 350px;
            box-sizing: border-box;
            border: 1px solid var(--bs-border-color);
        }
    </style>
</head>
<body data-bs-theme="light">

    <header class="aero-header">
        <div class="header-content">
            <div>
                <h1 class="brand-title">Audrey // Production Intake</h1>
                <p style="margin: 3px 0 0 0; font-size: 0.85rem; opacity: 0.8;">"Let's get your master metadata organized before Harper locks the vault doors."</p>
            </div>
            <div class="terminal-sticky" aria-label="Terminal Launch Command">
                💻 Run Command: php -S localhost:8000
            </div>
        </div>
    </header>

    <main class="main-container">
        
        <?php if ($message === "SUCCESS"): ?>
            <div class="hud-panel hud-success" role="alert">
                <h2>✨ Master Tracks Pressed Successfully</h2>
                <p>Audrey has successfully compiled your multi-disc metadata layers into memory. Scroll to the footer of the console to pull your generated source files.</p>
            </div>
        <?php endif; ?>

        <form method="POST" id="workbenchForm">
            
            <!-- SECTION 1: SCHEMA RUNTIME -->
            <section class="hud-panel">
                <h2>1. Album Core Schema (album.json)</h2>
                <div class="form-grid">
                    <div class="field-group col-6">
                        <label自动 for="album_name">Album Title</label>
                        <input type="text" id="album_name" name="album_name" required>
                    </div>
                    <div class="field-group col-6">
                        <label for="artist_name">Artist Persona</label>
                        <input type="text" id="artist_name" name="artist_name" required>
                    </div>
                    <div class="field-group col-4">
                        <label for="genre">Genre Label</label>
                        <input type="text" id="genre" name="genre" placeholder="e.g. Rock Opera / Synthwave">
                    </div>
                    <div class="field-group col-4">
                        <label for="temporal_coverage">Narrative Timeline Setting (temporalCoverage)</label>
                        <input type="text" id="temporal_coverage" name="temporal_coverage" placeholder="YYYY-MM-DD">
                    </div>
                    <div class="field-group col-4">
                        <label for="date_published">Real-World DSP Release Date (datePublished)</label>
                        <input type="text" id="date_published" name="date_published" placeholder="YYYY-MM-DD">
                    </div>
                    <div class="field-group col-12">
                        <label for="description">Release Description Summary</label>
                        <textarea id="description" name="description" rows="3"></textarea>
                    </div>
                    <div class="field-group col-6">
                        <label class="checkbox-container">
                            <input type="checkbox" name="is_rock_opera" value="1"> 🎭 Flag Project as Rock Opera / Narrative Concept Piece
                        </label>
                    </div>
                </div>
            </section>

            <!-- SECTION 2: TRACK RECONSTRUCTION LAYER -->
            <section class="hud-panel">
                <h2>2. Linear Track Assemblies (tracks.json)</h2>
                <div id="trackAssemblyFloor"></div>
                
                <div style="margin-top: 20px; display: flex; gap: 10px;">
                    <button type="button" class="btn btn-secondary" onclick="appendTrack(1)">+ Add Disc 1 Track</button>
                    <button type="button" class="btn btn-secondary" onclick="appendTrack(2)">+ Add Disc 2 Track</button>
                </div>
            </section>

            <button type="submit" class="btn btn-primary" style="width: 100%; padding: 15px; font-size: 1.1rem; text-transform: uppercase;">Compile Project Parameters</button>
        </form>

        <!-- SECTION 3: CODE OUTPUT VAULTS -->
        <?php if ($_SERVER["REQUEST_METHOD"] == "POST"): ?>
            <section class="hud-panel" style="margin-top: 40px;">
                <h2>3. Extracted Core Code Assets</h2>
                
                <div class="form-grid">
                    <div class="field-group col-12" style="margin-bottom: 25px;">
                        <label for="album_out_box">File Output Target: <code style="color:var(--bs-primary);">album.json</code></label>
                        <textarea id="album_out_box" class="json-pane" readonly><?php echo htmlspecialchars($albumJsonOut); ?></textarea>
                    </div>
                    <div class="field-group col-12">
                        <label for="tracks_out_box">File Output Target: <code style="color:var(--bs-primary);">tracks.json</code></label>
                        <textarea id="tracks_out_box" class="json-pane" readonly><?php echo htmlspecialchars($tracksJsonOut); ?></textarea>
                    </div>
                </div>
            </section>
        <?php endif; ?>

    </main>

    <script>
        let sequentialCounter = 0;

        function appendTrack(discNumber) {
            $floor = document.getElementById('trackAssemblyFloor');
            
            let currentTrackIndex = $floor.children.length + 1;
            let defaultDiscName = (discNumber === 2) ? "The Journey Home" : "The Long Road West";
            
            let blueprint = `
                <div class="track-block" id="block_${sequentialCounter}">
                    <div class="form-grid">
                        <div class="field-group col-4">
                            <label for="t_title_${sequentialCounter}">Track Title</label>
                            <input type="text" id="t_title_${sequentialCounter}" name="tracks[${sequentialCounter}][title]" required>
                        </div>
                        <div class="field-group col-4">
                            <label for="t_slug_${sequentialCounter}">File Name String (Slug)</label>
                            <input type="text" id="t_slug_${sequentialCounter}" name="tracks[${sequentialCounter}][file_name]" placeholder="e.g. ${discNumber}-01-track-title" required>
                        </div>
                        <div class="field-group col-4">
                            <label for="t_isrc_${sequentialCounter}">ISRC Code</label>
                            <input type="text" id="t_isrc_${sequentialCounter}" name="tracks[${sequentialCounter}][isrc]">
                        </div>
                        
                        <div class="field-group col-4">
                            <label for="t_disc_${sequentialCounter}">Disc Index</label>
                            <input type="number" id="t_disc_${sequentialCounter}" name="tracks[${sequentialCounter}][disc_num]" value="${discNumber}" required>
                        </div>
                        <div class="field-group col-4">
                            <label for="t_dname_${sequentialCounter}">Disc Act Heading</label>
                            <input type="text" id="t_dname_${sequentialCounter}" name="tracks[${sequentialCounter}][disc_name]" value="${defaultDiscName}">
                        </div>
                        <div class="field-group col-2">
                            <label for="t_num_${sequentialCounter}">Track position</label>
                            <input type="number" id="t_num_${sequentialCounter}" name="tracks[${sequentialCounter}][track_num]" value="${currentTrackIndex}" required>
                        </div>
                        <div class="field-group col-2">
                            <label for="t_dur_${sequentialCounter}">Runtime (MM:SS)</label>
                            <input type="text" id="t_dur_${sequentialCounter}" name="tracks[${sequentialCounter}][duration]">
                        </div>
                        
                        <div class="field-group col-4">
                            <label for="t_suite_${sequentialCounter}">Suite Grouping Name (Optional)</label>
                            <input type="text" id="t_suite_${sequentialCounter}" name="tracks[${sequentialCounter}][suite_name]">
                        </div>
                        <div class="field-group col-4">
                            <label for="t_suitenum_${sequentialCounter}">Track Index in Suite</label>
                            <input type="text" id="t_suitenum_${sequentialCounter}" name="tracks[${sequentialCounter}][suite_track]">
                        </div>
                        <div class="field-group col-4">
                            <label for="t_tier_${sequentialCounter}">Catalog Legacy Tier</label>
                            <select id="t_tier_${sequentialCounter}" name="tracks[${sequentialCounter}][legacy_tier]">
                                <option value="">-- No Status --</option>
                                <option value="Chart Smash">Chart Smash</option>
                                <option value="Fan Anthem">Fan Anthem</option>
                                <option value="Deep Cut">Deep Cut</option>
                                <option value="The Dud">The Dud</option>
                            </select>
                        </div>
                        <div class="field-group col-12">
                            <label for="t_lore_${sequentialCounter}">Narrative Extended Lore Notes</label>
                            <input type="text" id="t_lore_${sequentialCounter}" name="tracks[${sequentialCounter}][lore_note]">
                        </div>
                    </div>
                </div>
            `;
            
            $floor.insertAdjacentHTML('beforeend', blueprint);
            sequentialCounter++;
        }

        // Initialize setup with a starting track field
        window.onload = function() { appendTrack(1); };
    </script>
</body>
</html>
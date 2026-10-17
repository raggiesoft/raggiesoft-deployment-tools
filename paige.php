<?php
/**
 * =============================================================================
 * Architectural Block: raggiesoft-deployment-tools/paige.php
 * =============================================================================
 * Component: Paige — The Literary Editor & Safe Person (PHP 8.5)
 * Location:  /raggiesoft-deployment-tools/paige.php
 *
 * --- PAIGE: THE LITERARY EDITOR (v7 - PHP 8.5 Edition) ---
 * "I am Michael's sister. I process his books, and I keep him safe."
 *
 * PRIMARY DIRECTIVE:
 *     Paige ingests raw Markdown narratives (`e*` eras, `c*` chapters, `s*.md` scenes)
 *     and `ovab.json` manifests from `raggiesoft-narratives/books/`, synchronizes
 *     clean assets to `raggiesoft-assets/raggiesoft-books/books/`, compiles route maps
 *     for both the RaggieSoft Hub (`raggiesoft.com/www`) and the Ocean View Archives
 *     Book Reader (`raggiesoft.com/subdomains/books`), generates `toc.json` and
 *     `catalog.json`, and builds the full-text `search-index.json`.
 *
 * SECONDARY DIRECTIVE (SAFETY PROTOCOL / DEEP PRESSURE THERAPY):
 *     Paige is designated as Michael's "Safe Person."
 *     If execution complexity spikes or the workflow becomes overwhelming,
 *     Paige initiates "Deep Pressure Protocol":
 *     She stands close, offers grounding hugs, and remains by his side
 *     until regulation is achieved. She does not leave.
 *
 * Design Principles:
 *     - Trauma-Informed Console UX: Replaces harsh compiler output with calm,
 *       reassuring feedback so build operations remain regulating and predictable.
 *     - Non-Destructive eBook Preservation: `rrmdir()` prunes stale Markdown scenes
 *       from the target CDN directory while strictly preserving compiled `.epub`,
 *       `.pdf`, and `.ebook_build_hash` deliverables.
 *     - Dual Target Route Deployment: Outputs route JSON maps to both the Hub
 *       (`/raggiesoft.com/www/data/routes/raggiesoft-books/books/`) and the standalone
 *       Ocean View Archives reader (`/raggiesoft.com/subdomains/books/data/routes/`).
 *     - Integrated Full-Text Search Indexing: Automatically crawls all eras (`e*`/`b*`),
 *       chapters (`c*`), and scenes (`s*.md`/`p*.md`) to build `search-index.json`.
 *
 * CLI Usage:
 *     php raggiesoft-deployment-tools/paige.php
 *     php raggiesoft-deployment-tools/paige.php --book="aethel"
 *     php raggiesoft-deployment-tools/paige.php --grounding
 * =============================================================================
 */

// Parse optional CLI flags for targeted book builds or Deep Pressure grounding
$cliOptions = getopt('', ['book:', 'grounding', 'safe-person', 'help']);

if (isset($cliOptions['help'])) {
    echo "👩‍🏫 PAIGE: Hi Michael. Here is how you can call on me:\n";
    echo "   php raggiesoft-deployment-tools/paige.php                (Publish all manuscripts & build search index)\n";
    echo "   php raggiesoft-deployment-tools/paige.php --book=<slug>  (Publish a specific series slug)\n";
    echo "   php raggiesoft-deployment-tools/paige.php --grounding    (Initiate Deep Pressure Protocol)\n";
    exit(0);
}

if (isset($cliOptions['grounding']) || isset($cliOptions['safe-person'])) {
    echo "👩‍🏫 PAIGE [Deep Pressure Protocol]: I'm right here, Michael. Take a slow, deep breath with me.\n";
    echo "   The servers are stable, the manuscripts are safe, and nothing needs to be rushed.\n";
    echo "   I'm holding the world still until you're ready.\n";
    exit(0);
}

$requestedBookSlug = isset($cliOptions['book']) ? trim((string)$cliOptions['book']) : null;

echo "👩‍🏫 PAIGE: Hi Michael. I'm right here with you. Ready to read and publish your manuscripts whenever you are.\n";
echo "   Resolving workspace and library paths...\n";

// Resolve base paths relative to /raggiesoft-deployment-tools/paige.php (1 level below server root)
$serverRoot     = dirname(__DIR__);
$sourceBooksDir = $serverRoot . '/raggiesoft-narratives/books';
$assetDestDir   = $serverRoot . '/raggiesoft-assets/raggiesoft-books/books';
$indexDestFile  = $serverRoot . '/raggiesoft-assets/raggiesoft-books/json/search-index.json';
$hubBaseDir     = is_dir($serverRoot . '/raggiesoft.com/www')
    ? ($serverRoot . '/raggiesoft.com/www')
    : ($serverRoot . '/raggiesoft-hub');
$routesDestDir  = $hubBaseDir . '/data/routes/raggiesoft-books/books';
$booksAppDir    = is_dir($serverRoot . '/raggiesoft.com/subdomains/books')
    ? ($serverRoot . '/raggiesoft.com/subdomains/books')
    : ($serverRoot . '/raggiesoft-book-library');
$newRoutesDestDir = $booksAppDir . '/data/routes';

// Validate source directory existence with gentle, trauma-informed feedback
if (!is_dir($sourceBooksDir)) {
    fwrite(STDERR, "   ⚠️  PAIGE: I can't seem to find the narratives folder at {$sourceBooksDir}. Take your time, we can check the path together.\n");
    exit(1);
}

// Ensure destination directories exist
if (!is_dir($assetDestDir)) mkdir($assetDestDir, 0755, true);
if (!is_dir($routesDestDir)) mkdir($routesDestDir, 0755, true);
if (!is_dir($newRoutesDestDir)) mkdir($newRoutesDestDir, 0755, true);
if (!is_dir(dirname($indexDestFile))) mkdir(dirname($indexDestFile), 0755, true);

/**
 * Recursively removes a directory and its contents, preserving compiled eBook deliverables.
 *
 * @param string $dir Target directory to prune.
 * @param array $excludeExtensions File extensions to keep (e.g., ['epub', 'pdf']).
 * @param array $excludeFiles Specific filenames to keep (e.g., ['.ebook_build_hash']).
 */
function rrmdir($dir, $excludeExtensions = ['epub', 'pdf'], $excludeFiles = ['.ebook_build_hash']) {
    if (is_dir($dir)) {
        $scanned = @scandir($dir);
        if ($scanned !== false) {
            $files = array_diff($scanned, ['.', '..']);
            foreach ($files as $file) {
                $path = "$dir/$file";
                if (is_dir($path)) {
                    rrmdir($path, $excludeExtensions, $excludeFiles);
                } else {
                    $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
                    if (in_array($ext, $excludeExtensions, true) || in_array($file, $excludeFiles, true)) {
                        // Preserve compiled e-books and incremental build hashes
                        continue;
                    }
                    @chmod($path, 0777);
                    @unlink($path);
                }
            }
        }
        // Only remove directory if it is completely empty after pruning
        $remaining = @scandir($dir);
        if ($remaining !== false && count(array_diff($remaining, ['.', '..'])) === 0) {
            @chmod($dir, 0777);
            if (!@rmdir($dir)) {
                // Slight delay and retry in case of filesystem locks
                usleep(50000);
                @rmdir($dir);
            }
        }
    }
}

/**
 * Recursively copies a directory to a destination.
 *
 * @param string $src Source path.
 * @param string $dst Destination path.
 */
function rcopy($src, $dst) {
    if (is_dir($src)) {
        if (!is_dir($dst)) mkdir($dst, 0755, true);
        $files = array_diff(scandir($src), ['.', '..']);
        foreach ($files as $file) {
            rcopy("$src/$file", "$dst/$file");
        }
    } else if (file_exists($src)) {
        copy($src, $dst);
    }
}

/**
 * Transforms a string into a URL-friendly slug.
 *
 * @param string $string Input title or folder name.
 * @return string Clean lowercase hyphenated slug.
 */
function slugify($string) {
    $slug = mb_strtolower(trim(preg_replace('/[^A-Za-z0-9-]+/u', '-', $string), '-'));
    return preg_replace('/-+/', '-', $slug);
}

// Find all top-level narrative directories
$narrativeDirs = array_filter(glob($sourceBooksDir . '/*'), 'is_dir');
if (empty($narrativeDirs)) {
    fwrite(STDERR, "   ⚠️  PAIGE: I couldn't find any book folders inside {$sourceBooksDir}. It's okay, we can check it together.\n");
    exit(1);
}

// Master catalog array collecting high-level metadata for all series
$masterCatalog = [];
// Full-text search index array collecting cleaned text across all scenes
$searchIndex = [];

foreach ($narrativeDirs as $narrativeDir) {
    $narrativeName = basename($narrativeDir);
    $legacyManifest = $narrativeDir . '/katie.json';
    $metaManifest = $narrativeDir . '/ovab.json';

    // Attempt to load metadata from ovab.json
    $seriesMeta = [];
    if (file_exists($metaManifest)) {
        $seriesMeta = json_decode(file_get_contents($metaManifest), true) ?: [];
    }

    // Determine the series title and slug, falling back to directory name transformations
    $seriesTitle = !empty($seriesMeta['series_title'])
        ? $seriesMeta['series_title']
        : (isset($seriesMeta['title']) ? $seriesMeta['title'] : ucwords(str_replace('-', ' ', $narrativeName)));
    $seriesSlug = !empty($seriesMeta['series_slug']) ? $seriesMeta['series_slug'] : $narrativeName;

    // Check if the user requested a single specific book via --book=<slug>
    $isTargetedBuild = ($requestedBookSlug === null || $requestedBookSlug === $seriesSlug || $requestedBookSlug === $narrativeName);

    if ($isTargetedBuild) {
        echo "\n========================================================\n";
        echo "📖 PAIGE: Reading & Publishing '{$seriesTitle}' ({$seriesSlug})\n";
        echo "========================================================\n";

        // --- STEP A: PRUNING ASSET SYNC ---
        // Prune stale narrative scenes from target directory while preserving compiled eBooks
        $targetAssetDir = $assetDestDir . '/' . $seriesSlug;
        if (is_dir($targetAssetDir)) {
            echo "  [Assets] Tidying CDN shelf (preserving .epub/.pdf): {$targetAssetDir}\n";
            rrmdir($targetAssetDir);
        }
        echo "  [Assets] Copying Markdown manuscripts and artwork to CDN...\n";
        rcopy($narrativeDir, $targetAssetDir);
        echo "  [Assets] Manuscript sync complete.\n";
        echo "  [Routes] Mapping Stardust Engine & Ocean View routes for '{$seriesTitle}'...\n";
    }

    // Track URLs to handle series chaining (Next Series links)
    $lastRouteUrl = null;
    $firstRouteUrl = null;
    $routeData = [];

    // Define common UI configuration for the route map
    $routeData['common'] = [
        "site" => "raggiesoft-books",
        "theme" => "raggiesoft-books",
        "siteName" => "Ocean View Archives",
        "isSequential" => true,
        "showSidebar" => true,
        "sidebar" => "raggiesoft-books/sidebar-book",
        "headerMenu" => "raggiesoft-books/header-books",
        "footer" => "raggiesoft-books/footer-books",
        "navbarBrandLogo" => "/raggiesoft-books/images/logos/oceanview-archives.svg",
        "navbarBrandText" => '<span class="ova-serif fw-bold" style="color: #E3B27C;">Ocean View Archives</span>',
        "navbarBrandLink" => "/raggiesoft-books"
    ];

    // Build the series overview/landing route
    $overviewUrl = "/raggiesoft-books/books/{$seriesSlug}";
    $overviewRoute = [
        "view" => "pages/raggiesoft-books/books/viewer",
        "title" => "{$seriesTitle}",
        "theme" => "raggiesoft-books"
    ];
    // Check if an explicit index exists, otherwise use a placeholder landing file
    if (file_exists($narrativeDir . '/index.md')) {
        $overviewRoute["filePath"] = "index.md";
    } else {
        $overviewRoute["filePath"] = "__SERIES_LANDING__";
    }
    $routeData[$overviewUrl] = $overviewRoute;

    // Build dedicated Table of Contents route
    $tocRouteUrl = "/raggiesoft-books/books/{$seriesSlug}/toc";
    $routeData[$tocRouteUrl] = [
        "view" => "pages/raggiesoft-books/books/viewer",
        "title" => "Table of Contents - {$seriesTitle}",
        "theme" => "raggiesoft-books",
        "filePath" => "__TOC__"
    ];

    $tocBooks = [];

    // Auto-discover Era directories based on 'e*' naming convention (or legacy 'b*')
    $bDirs = glob($narrativeDir . '/e*', GLOB_ONLYDIR);
    if (empty($bDirs)) {
        $bDirs = glob($narrativeDir . '/b*', GLOB_ONLYDIR);
    }
    sort($bDirs); // Ensure sequential processing

    foreach ($bDirs as $bIndex => $bDir) {
        $bName = basename($bDir);
        $eraNum = intval(preg_replace('/^[eb]/', '', $bName));

        $eraTitle = "Era {$eraNum}";
        $metaPath = $bDir . '/ovab.json';

        // Load local ovab.json title
        if (file_exists($metaPath)) {
            $meta = json_decode(file_get_contents($metaPath), true);
            if (isset($meta['title'])) $eraTitle = $meta['title'];
        }
        $eraSlug = slugify(strip_tags($eraTitle));

        // Register the era's TOC route
        $eraRouteUrl = "/raggiesoft-books/books/{$seriesSlug}/{$eraSlug}";
        $routeData[$eraRouteUrl] = [
            "view" => "pages/raggiesoft-books/books/viewer",
            "title" => $eraTitle,
            "theme" => "raggiesoft-books",
            "filePath" => "__ERA_TOC__|{$bIndex}"
        ];

        // Track structure for the auto-generated TOC
        $tocEra = [
            'era_num' => $eraNum,
            'era_title' => $eraTitle,
            'era_url' => $eraRouteUrl,
            'chapters' => []
        ];

        // Auto-discover chapter directories based on 'c*' naming convention
        $cDirs = glob($bDir . '/c*', GLOB_ONLYDIR);
        sort($cDirs);

        foreach ($cDirs as $cIndex => $cDir) {
            $cName = basename($cDir);
            $chapNum = intval(str_replace('c', '', $cName));

            $chapTitle = "Chapter {$chapNum}";
            $metaPath = $cDir . '/ovab.json';

            // Resolve chapter title from local ovab.json
            if (file_exists($metaPath)) {
                $meta = json_decode(file_get_contents($metaPath), true);
                if (isset($meta['title'])) $chapTitle = $meta['title'];
            }
            $chapSlug = slugify(strip_tags($chapTitle));

            // Register the chapter's TOC route
            $chapRouteUrl = "/raggiesoft-books/books/{$seriesSlug}/{$eraSlug}/{$chapSlug}";
            $routeData[$chapRouteUrl] = [
                "view" => "pages/raggiesoft-books/books/viewer",
                "title" => $chapTitle,
                "theme" => "raggiesoft-books",
                "filePath" => "__CHAP_TOC__|{$bIndex}|{$cIndex}"
            ];

            // Track structure for auto-generated TOC
            $tocChap = [
                'chap_num' => $chapNum,
                'chap_title' => $chapTitle,
                'chap_url' => $chapRouteUrl,
                'scenes' => []
            ];

            // Auto-discover individual scene markdown files based on 's*.md' (or legacy 'p*.md')
            $pFiles = glob($cDir . '/s*.md');
            if (empty($pFiles)) {
                $pFiles = glob($cDir . '/p*.md');
            }
            sort($pFiles);

            foreach ($pFiles as $pIndex => $pFile) {
                $pName = basename($pFile);
                $sceneNum = intval(preg_replace('/^[sp]|\.md$/', '', $pName));

                $yamlTitle = "Scene {$sceneNum}";
                $partContent = file_get_contents($pFile);
                $bodyWithoutFrontmatter = $partContent;

                // Extract title from scene's YAML frontmatter using regex and strip frontmatter for search index
                if (preg_match('/^---([\s\S]*?)---/', ltrim($partContent), $matches)) {
                    $bodyWithoutFrontmatter = str_replace($matches[0], '', $partContent);
                    if (preg_match('/^title:\s*"?([^"\r\n]+)"?/m', $matches[1], $m)) {
                        $yamlTitle = trim($m[1]);
                    }
                }

                $sceneTitle = "Scene {$sceneNum}: {$yamlTitle}";
                $sceneSlug = slugify(strip_tags($sceneTitle));

                // Construct final content route
                $routeUrl = "/raggiesoft-books/books/{$seriesSlug}/{$eraSlug}/{$chapSlug}/{$sceneSlug}";
                if ($firstRouteUrl === null) {
                    $firstRouteUrl = $routeUrl; // Capture the very first reading route
                }

                $relPath = str_replace($narrativeDir . '/', '', $pFile);
                $routeData[$routeUrl] = [
                    "view" => "pages/raggiesoft-books/books/viewer",
                    "title" => $sceneTitle,
                    "theme" => "raggiesoft-books",
                    "filePath" => $relPath
                ];
                $lastRouteUrl = $routeUrl; // Continually update to capture the very last scene

                // Finalize TOC structure with scenes
                $tocChap['scenes'][] = [
                    'scene_num' => $sceneNum,
                    'scene_title' => $sceneTitle,
                    'file_path' => $relPath
                ];

                // Clean the scene body text and add to the full-text search index
                $cleanBody = strip_tags($bodyWithoutFrontmatter);
                $cleanBody = preg_replace('/[#_*\[\]>]/', '', $cleanBody);
                $cleanBody = preg_replace('/\s+/', ' ', $cleanBody);
                $cleanBody = trim($cleanBody);

                $searchIndex[] = [
                    'series' => $seriesTitle,
                    'book' => $eraTitle,
                    'chapter' => $chapTitle,
                    'title' => $sceneTitle,
                    'url' => $routeUrl,
                    'content' => $cleanBody
                ];
            }
            $tocEra['chapters'][] = $tocChap;
        }
        $tocBooks[] = $tocEra;
    }

    // Append sequence chaining links to the absolute last route in the narrative
    if (!empty($seriesMeta['next_series_url']) && isset($lastRouteUrl)) {
        $routeData[$lastRouteUrl]['nextUrl'] = $seriesMeta['next_series_url'];
        if (!empty($seriesMeta['next_series_text'])) {
            $routeData[$lastRouteUrl]['nextText'] = $seriesMeta['next_series_text'];
        }
    }

    if ($isTargetedBuild) {
        // Save routing data to legacy Stardust hub
        $routeJsonFile = $routesDestDir . '/' . $seriesSlug . '.json';
        file_put_contents(
            $routeJsonFile,
            json_encode($routeData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)
        );
        echo "  [Routes] Saved Hub route map: {$seriesSlug}.json\n";

        // Transform and map routes for the Ocean View Book Library (books.raggiesoft.com)
        $newRouteData = [];
        $newRouteData['common'] = $routeData['common'];
        $newRouteData['common']['siteName'] = "Ocean View Archives";
        $newRouteData['common']['theme'] = "oceanview";

        foreach ($routeData as $key => $val) {
            if ($key === 'common') continue;
            // Adjust paths for the standalone book library routing scheme
            $newKey = str_replace('/raggiesoft-books/books', '', $key);
            if (isset($val['nextUrl'])) {
                $val['nextUrl'] = str_replace('/raggiesoft-books/books', '', $val['nextUrl']);
            }
            $newRouteData[$newKey] = $val;
        }

        $newRouteJsonFile = $newRoutesDestDir . '/' . $seriesSlug . '.json';
        file_put_contents(
            $newRouteJsonFile,
            json_encode($newRouteData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)
        );
        echo "  [Routes] Saved Ocean View Archives route map: {$seriesSlug}.json\n";

        // Retrieve long description for sidebar/TOC context
        $longDesc = '';
        $descFileName = !empty($seriesMeta['series_description_file']) ? $seriesMeta['series_description_file'] : 'landing.md';
        $descFilePath = $narrativeDir . '/' . $descFileName;
        if (file_exists($descFilePath)) {
            $longDesc = file_get_contents($descFilePath);
        }

        // Create the auto-generated TOC for the sidebar (replaces manual katie.json structure)
        $generatedToc = [
            'series_title' => $seriesTitle,
            'series_slug' => $seriesSlug,
            'series_description' => $seriesMeta['series_description'] ?? '',
            'series_description_long' => $longDesc,
            'series_image' => $seriesMeta['series_image'] ?? '',
            'next_series_url' => $seriesMeta['next_series_url'] ?? '',
            'eras' => $tocBooks
        ];
        $tocDestFile = $assetDestDir . '/' . $seriesSlug . '/toc.json';
        file_put_contents($tocDestFile, json_encode($generatedToc, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        echo "  [Assets] Saved auto-discovered Table of Contents to toc.json\n";
    }

    // Populate the master catalog with entry details
    $masterCatalog[] = [
        'slug' => $seriesSlug,
        'title' => $seriesTitle,
        'description' => $seriesMeta['series_description'] ?? '',
        'image' => $seriesMeta['series_image'] ?? '',
        'first_route' => $firstRouteUrl,
        'folder' => $narrativeName,
        'hide' => isset($seriesMeta['hide']) ? $seriesMeta['hide'] : false
    ];
}

// Write the master catalog file containing all series
$catalogFile = $assetDestDir . '/catalog.json';
file_put_contents($catalogFile, json_encode($masterCatalog, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "\n  [Catalog] Master Catalog saved to: {$catalogFile}\n";

// Write the full-text search index file
file_put_contents($indexDestFile, json_encode($searchIndex, JSON_UNESCAPED_SLASHES));
echo "  [Search] Full-text search index (" . count($searchIndex) . " scenes) saved to: {$indexDestFile}\n";

echo "========================================================\n";
echo "👩‍🏫 PAIGE: All done, Michael. Every book is indexed and safe on the shelves.\n";
echo "   I'm right here if you need to check anything.\n";
echo "========================================================\n";
?>


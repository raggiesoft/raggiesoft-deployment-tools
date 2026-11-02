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
 *     Paige ingests raw Markdown narratives (`e*` eras, `c*` chapters, `p*.md` parts)
 *     and `ovab.json` manifests from `raggiesoft-narratives/books/`, synchronizes
 *     clean assets to `raggiesoft-assets/raggiesoft-books/books/`, compiles route maps
 *     for the Ocean View Archives Book Reader (`raggiesoft.com/subdomains/books`),
 *     generates `toc.json` and `catalog.json`, and builds the full-text `search-index.json`.
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
 *     - Ocean View Archives Route Deployment: Outputs route JSON maps directly to the
 *       standalone Ocean View Archives reader (`/raggiesoft.com/subdomains/books/data/routes/`).
 *     - Integrated Full-Text Search Indexing: Automatically crawls all eras (`e*`),
 *       chapters (`c*`), and scenes (`s*.md`) to build `search-index.json`.
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

// Resolve base paths relative to ~/Developer/raggiesoft-deployment-tools/paige.php
$parentRoot     = dirname(__DIR__);
$serverRoot     = is_dir($parentRoot . '/raggiesoft-servers')
    ? ($parentRoot . '/raggiesoft-servers')
    : $parentRoot;
$sourceBooksDir = $serverRoot . '/raggiesoft-narratives/books';
$assetDestDir   = $serverRoot . '/raggiesoft-assets/raggiesoft-books/books';
$indexDestFile  = $serverRoot . '/raggiesoft-assets/raggiesoft-books/json/search-index.json';
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

/**
 * Formats a raw byte count into a pleasant, human-readable file size string
 * (e.g., "36.8 MB", "2.8 MB", "690 KB", "5.3 KB") for eBook download links.
 *
 * @param int $bytes Raw file size in bytes.
 * @return string Pleasant human-readable size string, or empty string if invalid.
 */
function formatEbookFileSize(int $bytes): string {
    if ($bytes <= 0) {
        return '';
    }
    if ($bytes < 1024) {
        return $bytes . ' B';
    }
    $kb = $bytes / 1024;
    if ($kb < 1024) {
        if ($kb < 10) {
            $formatted = rtrim(rtrim(number_format($kb, 1, '.', ''), '0'), '.');
            return $formatted . ' KB';
        }
        return (string)round($kb) . ' KB';
    }
    $mb = $bytes / 1048576;
    if ($mb < 1024) {
        $formatted = rtrim(rtrim(number_format($mb, 1, '.', ''), '0'), '.');
        return $formatted . ' MB';
    }
    $gb = $bytes / 1073741824;
    $formatted = rtrim(rtrim(number_format($gb, 2, '.', ''), '0'), '.');
    return $formatted . ' GB';
}

/**
 * Inspects a compiled book asset directory and returns human-readable and raw byte
 * file sizes for all 4 eBook deliverables (Illustrated EPUB/PDF + Text-Only EPUB/PDF).
 *
 * @param string $bookAssetDir Path to `raggiesoft-assets/raggiesoft-books/books/<slug>`.
 * @param string $seriesSlug   Canonical series slug.
 * @return array Associative array of formatted strings and byte counts.
 */
function getSeriesEbookSizes(string $bookAssetDir, string $seriesSlug): array {
    clearstatcache();
    $files = [
        'epub'      => $bookAssetDir . '/' . $seriesSlug . '.epub',
        'pdf'       => $bookAssetDir . '/' . $seriesSlug . '.pdf',
        'text_epub' => $bookAssetDir . '/' . $seriesSlug . '-text.epub',
        'text_pdf'  => $bookAssetDir . '/' . $seriesSlug . '-text.pdf',
    ];
    $sizes = [
        'epub'            => '',
        'pdf'             => '',
        'text_epub'       => '',
        'text_pdf'        => '',
        'epub_bytes'      => 0,
        'pdf_bytes'       => 0,
        'text_epub_bytes' => 0,
        'text_pdf_bytes'  => 0,
    ];
    foreach ($files as $key => $filePath) {
        if (is_file($filePath)) {
            $bytes = (int)@filesize($filePath);
            if ($bytes > 0) {
                $sizes[$key] = formatEbookFileSize($bytes);
                $sizes[$key . '_bytes'] = $bytes;
            }
        }
    }
    return $sizes;
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
// Lookup map of all series eBook file sizes for `raggiesoft.com/subdomains/books/data/ebook-sizes.json`
$allEbookSizes = [];
// Lookup map of all internal route preview cards for Wikipedia-style link hovercards (`data/link-previews.json`)
$linkPreviewsManifestFile = $booksAppDir . '/data/link-previews.json';
$allLinkPreviews = [];
if ($requestedBookSlug !== null && is_file($linkPreviewsManifestFile)) {
    $allLinkPreviews = json_decode((string)@file_get_contents($linkPreviewsManifestFile), true) ?: [];
}
$allLinkPreviews['/illustrations'] = [
    'kind' => 'gallery',
    'title' => 'Library-Wide Table of Illustrations',
    'series' => 'Ocean View Archives',
    'series_slug' => 'illustrations',
    'kicker' => 'Ocean View Archives • Visual Index',
    'date' => '',
    'location' => 'All Illustrated Novels & Universes',
    'image' => '/raggiesoft-books/images/covers/og/rachel.jpg',
    'excerpt' => 'Explore every full-bleed 16:9 chapter plate and inline archival illustration across The Rachel Narrative, The Eleventh Child, The Stardust Engine, and the entire Ocean View Archives catalog.',
    'url' => '/illustrations'
];

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

    // Build dedicated Table of Illustrations route (reusable across all narratives)
    $illustrationsRouteUrl = "/raggiesoft-books/books/{$seriesSlug}/illustrations";
    $routeData[$illustrationsRouteUrl] = [
        "view" => "pages/raggiesoft-books/books/viewer",
        "title" => "Table of Illustrations - {$seriesTitle}",
        "theme" => "raggiesoft-books",
        "filePath" => "__ILLUSTRATIONS__"
    ];

    $tocBooks = [];
    $seriesIllustrationCount = 0;

    // Auto-discover Era directories strictly based on 'e*' naming convention
    $bDirs = glob($narrativeDir . '/e*', GLOB_ONLYDIR);
    sort($bDirs); // Ensure sequential processing

    foreach ($bDirs as $bIndex => $bDir) {
        $bName = basename($bDir);
        $eraNum = intval(str_replace('e', '', $bName));

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
        $eraIllustrationCount = 0;
        $tocEra = [
            'era_num' => $eraNum,
            'era_title' => $eraTitle,
            'era_url' => $eraRouteUrl,
            'illustration_count' => 0,
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

            // Track structure for auto-generated TOC (`parts` array inside each chapter)
            $chapIllustrationCount = 0;
            $tocChap = [
                'chap_num' => $chapNum,
                'chap_title' => $chapTitle,
                'chap_url' => $chapRouteUrl,
                'illustration_count' => 0,
                'parts' => []
            ];

            // Auto-discover individual part markdown files strictly based on 'p*.md'
            $pFiles = glob($cDir . '/p*.md');
            sort($pFiles);
            $chapPartCount = count($pFiles);

            foreach ($pFiles as $pIndex => $pFile) {
                $pName = basename($pFile);
                $partNum = intval(str_replace(['p', '.md'], '', $pName));

                $yamlTitle = "Part {$partNum}";
                $partDate = '';
                $partStardate = '';
                $partRealmTime = '';
                $partStartTime = '';
                $partLocation = '';
                $partSummary = '';
                $partImages = [];
                $partContent = file_get_contents($pFile);
                $bodyWithoutFrontmatter = $partContent;

                // Extract title, scene metadata, and illustrations from part's YAML frontmatter
                if (preg_match('/^---([\s\S]*?)---/', ltrim($partContent), $matches)) {
                    $frontmatterRaw = $matches[1];
                    $bodyWithoutFrontmatter = str_replace($matches[0], '', $partContent);
                    // Parse YAML title safely even if the string contains escaped double quotes (\"...\")
                    if (preg_match('/^title:\s*(.+)$/m', $frontmatterRaw, $m)) {
                        $extractedTitle = trim($m[1]);
                        if ((str_starts_with($extractedTitle, '"') && str_ends_with($extractedTitle, '"')) ||
                            (str_starts_with($extractedTitle, "'") && str_ends_with($extractedTitle, "'"))) {
                            $extractedTitle = substr($extractedTitle, 1, -1);
                        }
                        $extractedTitle = trim(str_replace('\"', '"', $extractedTitle));
                        if ($extractedTitle !== '' && strcasecmp($extractedTitle, 'Untitled Chapter') !== 0 && strcasecmp($extractedTitle, 'Untitled') !== 0) {
                            $yamlTitle = $extractedTitle;
                        } elseif ($chapPartCount === 1) {
                            $yamlTitle = preg_replace('/^Chapter\s+\d+:\s*/i', '', $chapTitle);
                        }
                    }
                    if (preg_match('/^date:\s*"?([^"\r\n]+)"?/m', $frontmatterRaw, $mDate)) {
                        $partDate = trim($mDate[1], " \t\n\r\0\x0B\"'");
                    }
                    if (preg_match('/^stardate:\s*"?([^"\r\n]+)"?/m', $frontmatterRaw, $mStardate)) {
                        $partStardate = trim($mStardate[1], " \t\n\r\0\x0B\"'");
                    }
                    if (preg_match('/^realm_time:\s*"?([^"\r\n]+)"?/m', $frontmatterRaw, $mRealmTime)) {
                        $partRealmTime = trim($mRealmTime[1], " \t\n\r\0\x0B\"'");
                    }
                    if (preg_match('/^start_time:\s*"?([^"\r\n]+)"?/m', $frontmatterRaw, $mTime)) {
                        $partStartTime = trim($mTime[1], " \t\n\r\0\x0B\"'");
                    }
                    if (preg_match('/^location:\s*"?([^"\r\n]+)"?/m', $frontmatterRaw, $mLoc)) {
                        $partLocation = trim($mLoc[1], " \t\n\r\0\x0B\"'");
                    }
                    if (preg_match('/^(?:og_description|summary):\s*"?([^"\r\n]+)"?/m', $frontmatterRaw, $mSum)) {
                        $partSummary = trim($mSum[1], " \t\n\r\0\x0B\"'");
                    }

                    // Parse frontmatter `image:` / `images:` and `image_alt:` / `image_alts:` (scalar or YAML list)
                    $fmImageUrls = [];
                    $fmImageAlts = [];
                    $fmLines = preg_split('/\r\n|\r|\n/', $frontmatterRaw);
                    $currentListKey = null;
                    foreach ($fmLines as $fmLine) {
                        if (preg_match('/^([a-zA-Z0-9_-]+):\s*(.*)$/', $fmLine, $kvMatch)) {
                            $k = strtolower(trim($kvMatch[1]));
                            $v = trim($kvMatch[2]);
                            $currentListKey = null;
                            if ($k === 'image' || $k === 'images') {
                                if ($v === '') {
                                    $currentListKey = 'image';
                                } else {
                                    $cleanVal = trim($v, "\"'");
                                    if ($cleanVal !== '') $fmImageUrls[] = $cleanVal;
                                }
                            } elseif ($k === 'image_alt' || $k === 'image_alts') {
                                if ($v === '') {
                                    $currentListKey = 'image_alt';
                                } else {
                                    $cleanVal = trim($v, "\"'");
                                    if ($cleanVal !== '') $fmImageAlts[] = $cleanVal;
                                }
                            }
                        } elseif ($currentListKey !== null && preg_match('/^\s*-\s+(.*)$/', $fmLine, $listMatch)) {
                            $itemVal = trim($listMatch[1], " \t\"'");
                            if ($itemVal !== '') {
                                if ($currentListKey === 'image') {
                                    $fmImageUrls[] = $itemVal;
                                } elseif ($currentListKey === 'image_alt') {
                                    $fmImageAlts[] = $itemVal;
                                }
                            }
                        } elseif (preg_match('/^\S/', $fmLine)) {
                            $currentListKey = null;
                        }
                    }

                    foreach ($fmImageUrls as $idx => $imgUrl) {
                        $normSrc = preg_replace('/#.*$/', '', str_replace(['{{CDN}}', '{{cms}}', 'https://assets.raggiesoft.com'], '', trim($imgUrl)));
                        $cleanRel = ltrim($normSrc, '/');
                        if ($cleanRel !== '' && strpos($cleanRel, 'raggiesoft-books/') !== 0 && strpos($cleanRel, 'raggiesoft-lore/') !== 0 && strpos($cleanRel, 'engine-room-records/') !== 0 && strpos($cleanRel, 'stardust-engine/images/') !== 0) {
                            $cleanRel = 'raggiesoft-books/images/scenes/' . preg_replace('#^scenes/#', '', $cleanRel);
                        }
                        $normSrc = '/' . $cleanRel;
                        if ($normSrc !== '/' && is_file($serverRoot . '/raggiesoft-assets' . $normSrc)) {
                            $partImages[] = [
                                'src' => $normSrc,
                                'alt' => $fmImageAlts[$idx] ?? ($fmImageAlts[0] ?? '')
                            ];
                        }
                    }
                }

                // Also discover any inline Markdown images (`![alt](url)`) inside the scene body
                if (preg_match_all('/!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/', $bodyWithoutFrontmatter, $inlineImgMatches, PREG_SET_ORDER)) {
                    $seenSrcs = array_column($partImages, 'src');
                    foreach ($inlineImgMatches as $inlineMatch) {
                        $inlineAlt = trim($inlineMatch[1]);
                        $inlineSrc = trim($inlineMatch[2]);
                        $normInlineSrc = preg_replace('/#.*$/', '', str_replace(['{{CDN}}', '{{cms}}', 'https://assets.raggiesoft.com'], '', $inlineSrc));
                        $cleanInlineRel = ltrim($normInlineSrc, '/');
                        if ($cleanInlineRel !== '' && strpos($cleanInlineRel, 'raggiesoft-books/') !== 0 && strpos($cleanInlineRel, 'raggiesoft-lore/') !== 0 && strpos($cleanInlineRel, 'engine-room-records/') !== 0) {
                            $cleanInlineRel = 'raggiesoft-books/images/scenes/' . $cleanInlineRel;
                        }
                        $normInlineSrc = '/' . $cleanInlineRel;
                        if ($normInlineSrc !== '/' && !in_array($normInlineSrc, $seenSrcs, true) && is_file($serverRoot . '/raggiesoft-assets' . $normInlineSrc)) {
                            $partImages[] = [
                                'src' => $normInlineSrc,
                                'alt' => $inlineAlt
                            ];
                            $seenSrcs[] = $normInlineSrc;
                        }
                    }
                }

                // Smart Polish (Option 1 + Idea 3):
                // - When a Chapter has 2+ Parts, display "Part X: <Title>".
                // - When a Chapter has only 1 Part, omit the redundant "Part 1:" prefix.
                $partTitle = ($chapPartCount > 1)
                    ? "Part {$partNum}: {$yamlTitle}"
                    : $yamlTitle;
                $partSlug = slugify(strip_tags($partTitle));

                // Construct final content route
                $routeUrl = "/raggiesoft-books/books/{$seriesSlug}/{$eraSlug}/{$chapSlug}/{$partSlug}";
                if ($firstRouteUrl === null) {
                    $firstRouteUrl = $routeUrl; // Capture the very first reading route
                }

                $relPath = str_replace($narrativeDir . '/', '', $pFile);
                $routeData[$routeUrl] = [
                    "view" => "pages/raggiesoft-books/books/viewer",
                    "title" => $partTitle,
                    "theme" => "raggiesoft-books",
                    "filePath" => $relPath
                ];
                if ($chapPartCount === 1 && strpos($partSlug, 'part-1-') !== 0) {
                    $legacyPart1RouteUrl = "/raggiesoft-books/books/{$seriesSlug}/{$eraSlug}/{$chapSlug}/part-1-{$partSlug}";
                    $routeData[$legacyPart1RouteUrl] = $routeData[$routeUrl];
                }
                $lastRouteUrl = $routeUrl; // Continually update to capture the very last part

                $partImgCount = count($partImages);
                $chapIllustrationCount += $partImgCount;
                $eraIllustrationCount += $partImgCount;
                $seriesIllustrationCount += $partImgCount;

                // Clean the part body text and add to the full-text search index
                $cleanBody = strip_tags($bodyWithoutFrontmatter);
                $cleanBody = preg_replace('/[#_*\[\]>]/', '', $cleanBody);
                $cleanBody = preg_replace('/\s+/', ' ', $cleanBody);
                $cleanBody = trim($cleanBody);

                // Extract a clean 1-2 sentence excerpt (~210 characters) for Wikipedia-style hovercard previews
                $partExcerpt = $partSummary;
                if ($partExcerpt === '') {
                    $proseBody = preg_replace('/!\[[^\]]*\]\([^)]*\)/', '', $bodyWithoutFrontmatter);
                    $proseBody = preg_replace('/\[([^\]]+)\]\([^)]*\)/', '$1', $proseBody);
                    $proseBody = preg_replace('/^#+\s+.*$/m', '', $proseBody);
                    $proseBody = preg_replace('/^---+\s*$/m', '', $proseBody);
                    $proseBody = strip_tags($proseBody);
                    $proseBody = preg_replace('/[*_`~>]/', '', $proseBody);
                    $proseBody = trim(preg_replace('/\s+/', ' ', $proseBody));
                    if (mb_strlen($proseBody) > 215) {
                        $cut = mb_substr($proseBody, 0, 212);
                        $lastSpace = mb_strrpos($cut, ' ');
                        if ($lastSpace !== false && $lastSpace > 140) {
                            $cut = mb_substr($cut, 0, $lastSpace);
                        }
                        $partExcerpt = rtrim($cut, " \t\n\r\0\x0B.,;:-—") . '…';
                    } else {
                        $partExcerpt = $proseBody;
                    }
                }

                // Finalize TOC structure with parts and illustration manifest
                $partStandaloneUrl = str_replace('/raggiesoft-books/books', '', $routeUrl);
                $partEntry = [
                    'part_num' => $partNum,
                    'part_title' => $partTitle,
                    'file_path' => $relPath,
                    'url' => $partStandaloneUrl
                ];
                if ($partDate !== '') $partEntry['date'] = $partDate;
                if ($partStardate !== '') $partEntry['stardate'] = $partStardate;
                if ($partRealmTime !== '') $partEntry['realm_time'] = $partRealmTime;
                if ($partStartTime !== '') $partEntry['start_time'] = $partStartTime;
                if ($partLocation !== '') $partEntry['location'] = $partLocation;
                if ($partExcerpt !== '') $partEntry['excerpt'] = $partExcerpt;
                if ($partImgCount > 0) {
                    $partEntry['image'] = $partImages[0]['src'];
                    $partEntry['image_alt'] = $partImages[0]['alt'];
                    $partEntry['images'] = $partImages;
                    $partEntry['image_count'] = $partImgCount;
                }
                $tocChap['parts'][] = $partEntry;

                $defaultSeriesOgImg = '/raggiesoft-books/images/covers/og/' . $seriesSlug . '.jpg';
                $partPreviewImg = ($partImgCount > 0) ? $partImages[0]['src'] : $defaultSeriesOgImg;
                $partTimeBadge = $partDate !== '' ? $partDate : ($partStardate !== '' ? "Stardate {$partStardate}" : ($partRealmTime !== '' ? $partRealmTime : ''));
                $scenePreviewPayload = [
                    'kind' => 'scene',
                    'title' => $partTitle,
                    'series' => $seriesTitle,
                    'series_slug' => $seriesSlug,
                    'kicker' => $seriesTitle . ' • ' . $chapTitle,
                    'date' => $partTimeBadge,
                    'location' => $partLocation,
                    'image' => $partPreviewImg,
                    'excerpt' => $partExcerpt,
                    'url' => $partStandaloneUrl
                ];
                $allLinkPreviews[$partStandaloneUrl] = $scenePreviewPayload;
                if ($chapPartCount === 1 && strpos($partSlug, 'part-1-') !== 0) {
                    $allLinkPreviews["/{$seriesSlug}/{$eraSlug}/{$chapSlug}/part-1-{$partSlug}"] = $scenePreviewPayload;
                }

                $searchIndex[] = [
                    'series' => $seriesTitle,
                    'book' => $eraTitle,
                    'chapter' => $chapTitle,
                    'title' => $partTitle,
                    'url' => $routeUrl,
                    'content' => $cleanBody
                ];
            }
            $tocChap['illustration_count'] = $chapIllustrationCount;
            $tocEra['chapters'][] = $tocChap;

            // Register chapter-level preview card (inheriting first part's image & excerpt)
            $chapStandaloneUrl = str_replace('/raggiesoft-books/books', '', $chapRouteUrl);
            $firstChapPart = $tocChap['parts'][0] ?? null;
            $chapPreviewImg = '/raggiesoft-books/images/covers/og/' . $seriesSlug . '.jpg';
            foreach ($tocChap['parts'] as $cp) {
                if (!empty($cp['image'])) {
                    $chapPreviewImg = $cp['image'];
                    break;
                }
            }
            $allLinkPreviews[$chapStandaloneUrl] = [
                'kind' => 'chapter',
                'title' => $chapTitle,
                'series' => $seriesTitle,
                'series_slug' => $seriesSlug,
                'kicker' => $seriesTitle . ' • ' . $eraTitle,
                'date' => $firstChapPart['date'] ?? ($firstChapPart['stardate'] ?? ($firstChapPart['realm_time'] ?? '')),
                'location' => $firstChapPart['location'] ?? '',
                'image' => $chapPreviewImg,
                'excerpt' => $firstChapPart['excerpt'] ?? ($seriesMeta['series_short_description'] ?? ''),
                'url' => $chapStandaloneUrl
            ];
        }
        $tocEra['illustration_count'] = $eraIllustrationCount;
        $tocBooks[] = $tocEra;

        // Register era-level preview card
        $eraStandaloneUrl = str_replace('/raggiesoft-books/books', '', $eraRouteUrl);
        $firstEraChap = $tocEra['chapters'][0] ?? null;
        $firstEraPart = $firstEraChap['parts'][0] ?? null;
        $eraPreviewImg = '/raggiesoft-books/images/covers/og/' . $seriesSlug . '.jpg';
        foreach ($tocEra['chapters'] as $ec) {
            foreach ($ec['parts'] as $ep) {
                if (!empty($ep['image'])) {
                    $eraPreviewImg = $ep['image'];
                    break 2;
                }
            }
        }
        $allLinkPreviews[$eraStandaloneUrl] = [
            'kind' => 'era',
            'title' => $eraTitle,
            'series' => $seriesTitle,
            'series_slug' => $seriesSlug,
            'kicker' => $seriesTitle . ' • Narrative Era',
            'date' => $firstEraPart['date'] ?? '',
            'location' => count($tocEra['chapters']) . ' ' . (count($tocEra['chapters']) === 1 ? 'Chapter' : 'Chapters'),
            'image' => $eraPreviewImg,
            'excerpt' => $firstEraPart['excerpt'] ?? ($seriesMeta['series_short_description'] ?? ''),
            'url' => $eraStandaloneUrl
        ];
    }

    // Register book-level, TOC, and Illustrations preview cards
    $seriesDescText = $seriesMeta['series_short_description'] ?? ($seriesMeta['series_description'] ?? '');
    $seriesOgCover = '/raggiesoft-books/images/covers/og/' . $seriesSlug . '.jpg';
    $allLinkPreviews['/' . $seriesSlug] = [
        'kind' => 'book',
        'title' => $seriesTitle,
        'series' => $seriesTitle,
        'series_slug' => $seriesSlug,
        'kicker' => 'Ocean View Archives Novel',
        'date' => count($tocBooks) . ' ' . (count($tocBooks) === 1 ? 'Era' : 'Eras'),
        'location' => $seriesIllustrationCount > 0 ? "{$seriesIllustrationCount} Illustrations" : 'Full-Length Archive',
        'image' => $seriesOgCover,
        'excerpt' => $seriesDescText,
        'url' => '/' . $seriesSlug
    ];
    $allLinkPreviews['/' . $seriesSlug . '/toc'] = [
        'kind' => 'book',
        'title' => "Table of Contents — {$seriesTitle}",
        'series' => $seriesTitle,
        'series_slug' => $seriesSlug,
        'kicker' => $seriesTitle . ' • Index',
        'date' => count($tocBooks) . ' ' . (count($tocBooks) === 1 ? 'Era' : 'Eras'),
        'location' => 'Complete Chapter Directory',
        'image' => $seriesOgCover,
        'excerpt' => $seriesDescText,
        'url' => '/' . $seriesSlug . '/toc'
    ];
    $allLinkPreviews['/' . $seriesSlug . '/illustrations'] = [
        'kind' => 'gallery',
        'title' => "Table of Illustrations — {$seriesTitle}",
        'series' => $seriesTitle,
        'series_slug' => $seriesSlug,
        'kicker' => $seriesTitle . ' • Visual Gallery',
        'date' => "{$seriesIllustrationCount} Illustrations",
        'location' => '16:9 Chapter Plates & Scene Artwork',
        'image' => $seriesOgCover,
        'excerpt' => "Browse all {$seriesIllustrationCount} canonical illustrations for {$seriesTitle} in chronological order.",
        'url' => '/' . $seriesSlug . '/illustrations'
    ];

    // Append sequence chaining links to the absolute last route in the narrative
    if (!empty($seriesMeta['next_series_url']) && isset($lastRouteUrl)) {
        $routeData[$lastRouteUrl]['nextUrl'] = $seriesMeta['next_series_url'];
        if (!empty($seriesMeta['next_series_text'])) {
            $routeData[$lastRouteUrl]['nextText'] = $seriesMeta['next_series_text'];
        }
    }

    // Measure compiled EPUB & PDF file sizes (Illustrated + Text-Only Editions)
    $seriesAssetDir = $assetDestDir . '/' . $seriesSlug;
    $ebookSizes = getSeriesEbookSizes($seriesAssetDir, $seriesSlug);
    $allEbookSizes[$seriesSlug] = $ebookSizes;

    if ($isTargetedBuild) {
        // Transform and map routes for the Ocean View Book Library (books.raggiesoft.com)
        $newRouteData = [];
        $newRouteData['common'] = $routeData['common'];
        $newRouteData['common']['siteName'] = "Ocean View Archives";
        $newRouteData['common']['theme'] = "oceanview";
        $newRouteData['common']['ebook_sizes'] = $ebookSizes;
        $newRouteData['common']['illustration_count'] = $seriesIllustrationCount;

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
            'series_theme' => $seriesMeta['series_theme'] ?? '',
            'series_short_description' => $seriesMeta['series_short_description'] ?? ($seriesMeta['series_description'] ?? ''),
            'series_description' => $seriesMeta['series_description'] ?? '',
            'series_description_long' => $longDesc,
            'series_image' => $seriesMeta['series_image'] ?? '',
            'next_series_url' => $seriesMeta['next_series_url'] ?? '',
            'ebook_sizes' => $ebookSizes,
            'illustration_count' => $seriesIllustrationCount,
            'eras' => $tocBooks
        ];
        $tocDestFile = $assetDestDir . '/' . $seriesSlug . '/toc.json';
        file_put_contents($tocDestFile, json_encode($generatedToc, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        echo "  [Assets] Saved auto-discovered Table of Contents (with {$seriesIllustrationCount} illustrations & eBook sizes) to toc.json\n";
    }

    // Populate the master catalog with entry details (separating quick-glance short_description from longer main description)
    $masterCatalog[] = [
        'slug' => $seriesSlug,
        'title' => $seriesTitle,
        'short_description' => $seriesMeta['series_short_description'] ?? ($seriesMeta['series_description'] ?? ''),
        'description' => $seriesMeta['series_description'] ?? '',
        'image' => $seriesMeta['series_image'] ?? '',
        'first_route' => $firstRouteUrl,
        'folder' => $narrativeName,
        'hide' => isset($seriesMeta['hide']) ? $seriesMeta['hide'] : false,
        'ebook_sizes' => $ebookSizes,
        'illustration_count' => $seriesIllustrationCount
    ];
}

// Write the master catalog file containing all series
$catalogFile = $assetDestDir . '/catalog.json';
file_put_contents($catalogFile, json_encode($masterCatalog, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "\n  [Catalog] Master Catalog saved to: {$catalogFile}\n";

// Write the local eBook file sizes manifest for books.raggiesoft.com
$ebookSizesManifestFile = $booksAppDir . '/data/ebook-sizes.json';
file_put_contents($ebookSizesManifestFile, json_encode($allEbookSizes, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "  [Sizes] eBook file sizes manifest saved to: {$ebookSizesManifestFile}\n";

// Write the Wikipedia-style link preview hovercard manifest for books.raggiesoft.com and CDN
$linkPreviewsJson = json_encode($allLinkPreviews, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
file_put_contents($linkPreviewsManifestFile, $linkPreviewsJson);
$cdnLinkPreviewsFile = $assetDestDir . '/../json/link-previews.json';
if (is_dir(dirname($cdnLinkPreviewsFile))) {
    file_put_contents($cdnLinkPreviewsFile, $linkPreviewsJson);
}
echo "  [Previews] Wikipedia-style link preview index (" . count($allLinkPreviews) . " routes) saved to: {$linkPreviewsManifestFile}\n";

// Write the full-text search index file
file_put_contents($indexDestFile, json_encode($searchIndex, JSON_UNESCAPED_SLASHES));
echo "  [Search] Full-text search index (" . count($searchIndex) . " parts) saved to: {$indexDestFile}\n";

echo "========================================================\n";
echo "👩‍🏫 PAIGE: All done, Michael. Every book is indexed and safe on the shelves.\n";
echo "   I'm right here if you need to check anything.\n";
echo "========================================================\n";
?>


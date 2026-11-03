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
function rrmdir($dir, $excludeExtensions = ['epub', 'pdf', '7z'], $excludeFiles = ['.ebook_build_hash']) {
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
        'epub'       => $bookAssetDir . '/' . $seriesSlug . '.epub',
        'pdf'        => $bookAssetDir . '/' . $seriesSlug . '.pdf',
        'text_epub'  => $bookAssetDir . '/' . $seriesSlug . '-text.epub',
        'text_pdf'   => $bookAssetDir . '/' . $seriesSlug . '-text.pdf',
        'package_7z' => $bookAssetDir . '/' . $seriesSlug . '-package.7z',
    ];
    $sizes = [
        'epub'             => '',
        'pdf'              => '',
        'text_epub'        => '',
        'text_pdf'         => '',
        'package_7z'       => '',
        'epub_bytes'       => 0,
        'pdf_bytes'        => 0,
        'text_epub_bytes'  => 0,
        'text_pdf_bytes'   => 0,
        'package_7z_bytes' => 0,
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

/**
 * Resolves the cross-platform 7-Zip executable path (matching harper.sh's 01-init.sh
 * discovery logic across Windows 7za.exe and macOS/Linux 7zz).
 *
 * @return string|null Absolute path or command name for 7-Zip, or null if unavailable.
 */
function resolveSevenZipBinary(): ?string {
    $localToolsDir = __DIR__ . '/build-tools/7zip';
    if (stripos(PHP_OS_FAMILY, 'Windows') !== false) {
        $winBin = $localToolsDir . '/7za.exe';
        if (is_file($winBin)) {
            return $winBin;
        }
    } else {
        $macBin = $localToolsDir . '/7zz';
        if (is_file($macBin)) {
            @chmod($macBin, 0755);
            return $macBin;
        }
        $which = trim((string)@shell_exec('command -v 7zz 2>/dev/null'));
        if ($which !== '') {
            return $which;
        }
    }
    return null;
}

/**
 * Packages a compiled book asset directory (`toc.json`, `ovab.json`, `landing.md`,
 * and all `e*` era/chapter/part Markdown folders) into `<slug>-package.7z` for
 * instant one-shot offline downloading in the RaggieSoft Book Reader desktop & mobile apps.
 *
 * @param string $bookAssetDir Path to `raggiesoft-assets/raggiesoft-books/books/<slug>`.
 * @param string $seriesSlug   Canonical series slug.
 */
function buildSeriesSevenZipPackage(string $bookAssetDir, string $seriesSlug): void {
    $sevenZip = resolveSevenZipBinary();
    if ($sevenZip === null || !is_dir($bookAssetDir)) {
        return;
    }

    $archivePath = $bookAssetDir . '/' . $seriesSlug . '-package.7z';
    @unlink($archivePath);

    $cmd = sprintf(
        'cd %s && %s a -t7z -mx=7 -ms=on %s . -xr!*.epub -xr!*.pdf -xr!*.7z -xr!.ebook_build_hash -xr!.DS_Store >/dev/null 2>&1',
        escapeshellarg($bookAssetDir),
        escapeshellarg($sevenZip),
        escapeshellarg($seriesSlug . '-package.7z')
    );
    @exec($cmd);
}

/**
 * Counts readable prose words in a Markdown string after stripping YAML frontmatter,
 * Markdown image tags, link URLs, HTML tags, and structural symbols.
 *
 * @param string $markdownText     Raw Markdown or plain text.
 * @param bool   $stripFrontmatter Whether to remove a leading `--- ... ---` block.
 * @return int Exact readable word count.
 */
function countReadableProseWords(string $markdownText, bool $stripFrontmatter = true): int {
    $text = $markdownText;
    if ($stripFrontmatter) {
        $text = (string)preg_replace('/^\s*---\s*\R.*?\R---\s*\R?/su', ' ', $text, 1);
    }
    // Strip Markdown images ![alt](url)
    $text = (string)preg_replace('/!\[[^\]]*\]\([^)]*\)/u', ' ', $text);
    // Replace Markdown links [label](url) with their visible label
    $text = (string)preg_replace('/\[([^\]]+)\]\([^)]*\)/u', '$1', $text);
    // Strip HTML tags and Markdown formatting characters
    $text = strip_tags($text);
    $text = (string)preg_replace('/[#*_`~>|]/u', ' ', $text);
    if (preg_match_all('/\b[\p{L}\p{N}\'’-]+\b/u', $text, $matches)) {
        return count($matches[0]);
    }
    return 0;
}

/**
 * Counts readable words inside a `.docx` OpenXML document archive (`word/document.xml`).
 *
 * @param string $docxPath Absolute path to the `.docx` file.
 * @return int Readable word count.
 */
function countDocxWords(string $docxPath): int {
    if (!class_exists('ZipArchive') || !is_file($docxPath)) {
        return 0;
    }
    $zip = new ZipArchive();
    if ($zip->open($docxPath) !== true) {
        return 0;
    }
    $xml = $zip->getFromName('word/document.xml');
    $zip->close();
    if (!is_string($xml) || $xml === '') {
        return 0;
    }
    $plain = strip_tags(str_replace('<', ' <', $xml));
    if (preg_match_all('/\b[\p{L}\p{N}\'’-]+\b/u', $plain, $matches)) {
        return count($matches[0]);
    }
    return 0;
}

/**
 * Recursively computes the deduplicated, curated canonical lore word count inside a
 * narrative lore folder (excluding legacy `_old/`, `ai-dump/`, raw AI chat transcripts,
 * and monolithic backup files when structured `chunks/` exist).
 *
 * @param string $folderPath Absolute path to a lore directory.
 * @return int Curated canonical lore word count.
 */
function computeCuratedLoreFolderWords(string $folderPath): int {
    if (!is_dir($folderPath)) {
        return 0;
    }
    $totalWords = 0;
    $seenHashes = [];
    $seenStems  = [];
    $hasChunksSubdir = is_dir($folderPath . '/chunks');

    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($folderPath, FilesystemIterator::SKIP_DOTS)
    );

    $mdTxtFiles = [];
    $docxFiles  = [];
    foreach ($iterator as $fileInfo) {
        if (!$fileInfo->isFile()) {
            continue;
        }
        $fullPath = $fileInfo->getPathname();
        $relPath  = str_replace('\\', '/', substr($fullPath, strlen($folderPath) + 1));
        $segments = explode('/', $relPath);
        if (in_array('_old', $segments, true) || in_array('ai-dump', $segments, true)) {
            continue;
        }
        $fn  = $fileInfo->getFilename();
        $low = strtolower($fn);
        $ext = strtolower($fileInfo->getExtension());
        if (str_starts_with($fn, '~$')) {
            continue;
        }
        if (
            str_contains($low, 'gemini-') ||
            str_contains($low, 'ai conversation') ||
            str_contains($low, 'lore-backup') ||
            in_array($low, ['cassandra-rescue.md', 'cassandra-the-ceo.md', 'shiloh-family.md'], true) ||
            ($low === 'rachel-lore.md' && $hasChunksSubdir)
        ) {
            continue;
        }
        if ($ext === 'md' || $ext === 'txt') {
            $mdTxtFiles[] = $fullPath;
        } elseif ($ext === 'docx') {
            $docxFiles[] = $fullPath;
        }
    }

    sort($mdTxtFiles);
    foreach ($mdTxtFiles as $fullPath) {
        $raw = (string)@file_get_contents($fullPath);
        $hash = hash('sha256', $raw);
        if (isset($seenHashes[$hash])) {
            continue;
        }
        $seenHashes[$hash] = true;
        $stem = preg_replace('/\.[^.]+$/', '', $fullPath);
        $seenStems[$stem] = true;
        $totalWords += countReadableProseWords($raw, true);
    }

    sort($docxFiles);
    foreach ($docxFiles as $fullPath) {
        $stem = preg_replace('/\.[^.]+$/', '', $fullPath);
        if (isset($seenStems[$stem])) {
            continue;
        }
        $hash = (string)@hash_file('sha256', $fullPath);
        if ($hash !== '' && isset($seenHashes[$hash])) {
            continue;
        }
        if ($hash !== '') {
            $seenHashes[$hash] = true;
        }
        $totalWords += countDocxWords($fullPath);
    }

    return $totalWords;
}

/**
 * Classifies a novel's word count against standard, generic contemporary publishing
 * industry benchmarks (strictly zero third-party author names or external book titles).
 *
 * @param int $storyWords    Pure narrative prose word count.
 * @param int $combinedWords Story + curated lore word count.
 * @return array{category:string,badge:string,benchmark_note:string,novel_equivalent:float}
 */
function classifyPublishingScale(int $storyWords, int $combinedWords): array {
    $ratio = round($storyWords / 90000, 1);
    if ($storyWords >= 200000) {
        $volCount = max(2, (int)round($storyWords / 90000));
        return [
            'category'         => 'Multi-Volume Epic Omnibus',
            'badge'            => 'Multi-Volume Omnibus',
            'benchmark_note'   => sprintf('%.1f× a standard 90,000-word contemporary novel (~%d-volume print series)', $ratio, $volCount),
            'novel_equivalent' => $ratio,
        ];
    }
    if ($storyWords >= 110000) {
        return [
            'category'         => 'Epic Full-Length Novel',
            'badge'            => 'Epic Novel',
            'benchmark_note'   => sprintf('%.1f× a standard 90,000-word contemporary novel (Epic 110k–200k tier)', $ratio),
            'novel_equivalent' => $ratio,
        ];
    }
    if ($storyWords >= 70000) {
        return [
            'category'         => 'Full-Length Contemporary Novel',
            'badge'            => 'Full-Length Novel',
            'benchmark_note'   => sprintf('%.1f× a standard 90,000-word contemporary novel (70k–110k trade benchmark)', $ratio),
            'novel_equivalent' => $ratio,
        ];
    }
    if ($storyWords >= 40000) {
        return [
            'category'         => 'Compact Novel',
            'badge'            => 'Compact Novel',
            'benchmark_note'   => 'Compact single-volume trade paperback length (40,000–70,000 words)',
            'novel_equivalent' => $ratio,
        ];
    }
    if ($storyWords >= 17500) {
        return [
            'category'         => 'Novella',
            'badge'            => 'Novella',
            'benchmark_note'   => 'Standard contemporary novella length (17,500–40,000 words)',
            'novel_equivalent' => $ratio,
        ];
    }
    if ($storyWords > 0) {
        return [
            'category'         => 'Short Fiction & Novelette',
            'badge'            => 'Short Fiction',
            'benchmark_note'   => 'Short story / novelette companion (< 17,500 words)',
            'novel_equivalent' => round($storyWords / 90000, 2),
        ];
    }
    return [
        'category'         => 'Lore & Outline Archive',
        'badge'            => 'Lore & Outline',
        'benchmark_note'   => 'In-development series outline & canonical lore treatment',
        'novel_equivalent' => 0.0,
    ];
}

// Preload Engine Room Records album & track liner notes + lyrics word counts for cross-referenced novels
$errArtistLinerWords  = [];
$errArtistLyricsWords = [];
$errPreloadCatalogFile = $serverRoot . '/raggiesoft-assets/engine-room-records/catalog.json';
if (is_file($errPreloadCatalogFile)) {
    $errPreloadCatalog = json_decode((string)@file_get_contents($errPreloadCatalogFile), true) ?: [];
    foreach ($errPreloadCatalog as $errAlb) {
        $aSlug = trim((string)($errAlb['artistSlug'] ?? ''));
        if ($aSlug === '') {
            continue;
        }
        $linerWords = countReadableProseWords((string)($errAlb['description'] ?? ''), false);
        $lyricsWords = 0;
        foreach (($errAlb['tracks'] ?? []) as $errTrack) {
            $linerWords  += countReadableProseWords((string)($errTrack['loreNote'] ?? ''), false);
            $lyricsWords += countReadableProseWords((string)($errTrack['lyrics'] ?? ''), false);
        }
        $errArtistLinerWords[$aSlug]  = ($errArtistLinerWords[$aSlug] ?? 0) + $linerWords;
        $errArtistLyricsWords[$aSlug] = ($errArtistLyricsWords[$aSlug] ?? 0) + $lyricsWords;
    }
}

$bookLoreFolderMap = [
    'rachel'                    => ['lore/rachel'],
    'aubrie'                    => ['lore/aubrie', 'backstage/books/aubrie'],
    'luna-leo'                  => ['lore/luna-leo'],
    'alex-chloe'                => ['lore/astro-kids'],
    'paige'                     => ['lore/paige'],
    'nichole'                   => ['lore/nichole'],
    'quantum-directive-3-casey' => ['lore/casey'],
    'ruby-mountain'             => ['lore/ruby-mountain'],
    'stardust-engine'           => ['backstage/music'],
    'ashley-tower'              => ['lore/ashley-tower'],
    'ad-astra'                  => ['lore/ad-astra'],
    'drew'                      => ['lore/drew'],
    'nate'                      => ['lore/nate'],
    'samantha'                  => ['lore/samantha'],
    'crimson-node'              => ['lore/crimson-node', 'lore/shiloh'],
    'meredith'                  => ['lore/david-meredith'],
    'beth'                      => ['lore/beth'],
    'fractured-prisms'          => ['lore/fractured-prisms'],
    'water-planet'              => ['lore/water-planet'],
];
$bookMusicArtistMap = [
    'stardust-engine'  => 'the-stardust-engine',
    'crimson-node'     => 'crimson-node',
    'fractured-prisms' => 'fractured-prisms',
    'aethel'           => 'firelight',
];
$narrativesRootDir = dirname($sourceBooksDir);

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
    $seriesStoryWordCount = 0;
    $seriesChapCountTotal = 0;
    $seriesPartCountTotal = 0;
    $seriesPartAbsPaths   = [];

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
        $eraWordCount = 0;
        $tocEra = [
            'era_num' => $eraNum,
            'era_title' => $eraTitle,
            'era_url' => $eraRouteUrl,
            'illustration_count' => 0,
            'word_count' => 0,
            'chapters' => []
        ];

        // Auto-discover chapter directories based on 'c*' naming convention
        $cDirs = glob($bDir . '/c*', GLOB_ONLYDIR);
        sort($cDirs);

        foreach ($cDirs as $cIndex => $cDir) {
            $seriesChapCountTotal++;
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
            $chapWordCount = 0;
            $tocChap = [
                'chap_num' => $chapNum,
                'chap_title' => $chapTitle,
                'chap_url' => $chapRouteUrl,
                'illustration_count' => 0,
                'word_count' => 0,
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

                // Finalize TOC structure with parts, word count telemetry, and illustration manifest
                $seriesPartCountTotal++;
                $realPFile = realpath($pFile);
                if ($realPFile !== false) {
                    $seriesPartAbsPaths[$realPFile] = true;
                }
                $partWordCount = countReadableProseWords($bodyWithoutFrontmatter, false);
                $partReadingMinutes = max(1, (int)ceil($partWordCount / 250));
                $chapWordCount += $partWordCount;
                $eraWordCount += $partWordCount;
                $seriesStoryWordCount += $partWordCount;

                $partStandaloneUrl = str_replace('/raggiesoft-books/books', '', $routeUrl);
                $partEntry = [
                    'part_num' => $partNum,
                    'part_title' => $partTitle,
                    'file_path' => $relPath,
                    'url' => $partStandaloneUrl,
                    'word_count' => $partWordCount,
                    'reading_minutes' => $partReadingMinutes
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
            $tocChap['word_count'] = $chapWordCount;
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
        $tocEra['word_count'] = $eraWordCount;
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

    // --- COMPUTE SERIES LORE & COMBINED WORD COUNT TELEMETRY ---
    $seriesInternalLoreWords = 0;
    foreach (['series_short_description', 'series_description'] as $descKey) {
        if (!empty($seriesMeta[$descKey])) {
            $seriesInternalLoreWords += countReadableProseWords((string)$seriesMeta[$descKey], false);
        }
    }
    $bookDirIter = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($narrativeDir, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($bookDirIter as $bFileInfo) {
        if ($bFileInfo->isFile() && strtolower($bFileInfo->getExtension()) === 'md') {
            $absMdPath = $bFileInfo->getRealPath();
            if ($absMdPath !== false && !isset($seriesPartAbsPaths[$absMdPath])) {
                $seriesInternalLoreWords += countReadableProseWords((string)@file_get_contents($absMdPath), true);
            }
        }
    }

    $seriesExternalLoreWords = 0;
    foreach (($bookLoreFolderMap[$seriesSlug] ?? []) as $relLoreFolder) {
        $seriesExternalLoreWords += computeCuratedLoreFolderWords($narrativesRootDir . '/' . $relLoreFolder);
    }
    $seriesMusicLoreWords = 0;
    if (isset($bookMusicArtistMap[$seriesSlug])) {
        $mArtistSlug = $bookMusicArtistMap[$seriesSlug];
        $seriesMusicLoreWords = $errArtistLinerWords[$mArtistSlug] ?? 0;
    }

    $seriesTotalLoreWords = $seriesInternalLoreWords + $seriesExternalLoreWords + $seriesMusicLoreWords;
    $seriesCombinedWords  = $seriesStoryWordCount + $seriesTotalLoreWords;
    $seriesStoryPages     = $seriesStoryWordCount > 0 ? max(1, (int)round($seriesStoryWordCount / 275)) : 0;
    $seriesCombinedPages  = $seriesCombinedWords > 0 ? max(1, (int)round($seriesCombinedWords / 275)) : 0;
    $seriesReadingHours   = $seriesStoryWordCount > 0 ? round($seriesStoryWordCount / 15000, 1) : 0.0;
    $seriesReadingMinutes = $seriesStoryWordCount > 0 ? max(1, (int)round($seriesStoryWordCount / 250)) : 0;
    $scaleInfo            = classifyPublishingScale($seriesStoryWordCount, $seriesCombinedWords);

    $seriesWordStats = [
        'story_word_count'    => $seriesStoryWordCount,
        'lore_word_count'     => $seriesTotalLoreWords,
        'combined_word_count' => $seriesCombinedWords,
        'story_page_count'    => $seriesStoryPages,
        'combined_page_count' => $seriesCombinedPages,
        'reading_hours'       => $seriesReadingHours,
        'reading_minutes'     => $seriesReadingMinutes,
        'novel_equivalent'    => $scaleInfo['novel_equivalent'],
        'scale_category'      => $scaleInfo['category'],
        'scale_badge'         => $scaleInfo['badge'],
        'benchmark_note'      => $scaleInfo['benchmark_note'],
        'era_count'           => count($tocBooks),
        'chapter_count'       => $seriesChapCountTotal,
        'part_count'          => $seriesPartCountTotal,
        'illustration_count'  => $seriesIllustrationCount
    ];

    if ($isTargetedBuild) {
        // Transform and map routes for the Ocean View Book Library (books.raggiesoft.com)
        $newRouteData = [];
        $newRouteData['common'] = $routeData['common'];
        $newRouteData['common']['siteName'] = "Ocean View Archives";
        $newRouteData['common']['theme'] = "oceanview";
        $newRouteData['common']['ebook_sizes'] = $ebookSizes;
        $newRouteData['common']['illustration_count'] = $seriesIllustrationCount;
        $newRouteData['common']['word_stats'] = $seriesWordStats;

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
            'word_stats' => $seriesWordStats,
            'eras' => $tocBooks
        ];
        $tocDestFile = $assetDestDir . '/' . $seriesSlug . '/toc.json';
        file_put_contents($tocDestFile, json_encode($generatedToc, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        echo "  [Assets] Saved auto-discovered Table of Contents (with {$seriesIllustrationCount} illustrations, " . number_format($seriesStoryWordCount) . " story words & eBook sizes) to toc.json\n";

        // Package the book's toc.json, ovab.json, landing.md, and e* Markdown tree into <slug>-package.7z
        buildSeriesSevenZipPackage($seriesAssetDir, $seriesSlug);
        $ebookSizes = getSeriesEbookSizes($seriesAssetDir, $seriesSlug);
        $allEbookSizes[$seriesSlug] = $ebookSizes;
        $generatedToc['ebook_sizes'] = $ebookSizes;
        file_put_contents($tocDestFile, json_encode($generatedToc, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        $newRouteData['common']['ebook_sizes'] = $ebookSizes;
        file_put_contents($newRouteJsonFile, json_encode($newRouteData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        echo "  [7-Zip] Packaged offline desktop reader archive: {$seriesSlug}-package.7z ({$ebookSizes['package_7z']})\n";
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
        'illustration_count' => $seriesIllustrationCount,
        'word_stats' => $seriesWordStats
    ];
}

// Write the master catalog file containing all series
$catalogFile = $assetDestDir . '/catalog.json';
file_put_contents($catalogFile, json_encode($masterCatalog, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "\n  [Catalog] Master Catalog saved to: {$catalogFile}\n";

// --- COMPILE LIVE LIBRARY-WIDE WORD COUNT & SCALE TELEMETRY (`library-stats.json`) ---
$universalLoreWords   = computeCuratedLoreFolderWords($narrativesRootDir . '/universal-lore');
$amayaLoreWords       = computeCuratedLoreFolderWords($narrativesRootDir . '/lore/amaya');
$rescueGameLoreWords  = computeCuratedLoreFolderWords($narrativesRootDir . '/lore/rescue-game');
$courtneyLoreWords    = computeCuratedLoreFolderWords($narrativesRootDir . '/lore/courtney');
$characterListWords   = computeCuratedLoreFolderWords($narrativesRootDir . '/character-list');
$rulesLoreWords       = computeCuratedLoreFolderWords($narrativesRootDir . '/rules');
$backstageSharedWords = computeCuratedLoreFolderWords($narrativesRootDir . '/backstage/corporations')
                      + computeCuratedLoreFolderWords($narrativesRootDir . '/backstage/locations');

$otherErrLinerWords = 0;
$mappedMusicArtists = array_values($bookMusicArtistMap);
foreach ($errArtistLinerWords as $aSlug => $lWords) {
    if (!in_array($aSlug, $mappedMusicArtists, true)) {
        $otherErrLinerWords += $lWords;
    }
}
$totalLyricsWords = array_sum($errArtistLyricsWords);

$sharedUniverseLoreWords = $universalLoreWords
                         + $amayaLoreWords
                         + $rescueGameLoreWords
                         + $courtneyLoreWords
                         + $characterListWords
                         + $rulesLoreWords
                         + $backstageSharedWords
                         + $otherErrLinerWords;

$totalStoryWords     = 0;
$totalBookLoreWords  = 0;
$totalErasCount      = 0;
$totalChapsCount     = 0;
$totalPartsCount     = 0;
$totalIllusCount     = 0;
$activeStoryVolumes  = 0;
$statsBooksRows      = [];

foreach ($masterCatalog as $catBook) {
    $ws = $catBook['word_stats'] ?? [];
    $sWords = (int)($ws['story_word_count'] ?? 0);
    $lWords = (int)($ws['lore_word_count'] ?? 0);
    if ($sWords > 0) {
        $activeStoryVolumes++;
    }
    $totalStoryWords    += $sWords;
    $totalBookLoreWords += $lWords;
    $totalErasCount     += (int)($ws['era_count'] ?? 0);
    $totalChapsCount    += (int)($ws['chapter_count'] ?? 0);
    $totalPartsCount    += (int)($ws['part_count'] ?? 0);
    $totalIllusCount    += (int)($catBook['illustration_count'] ?? 0);

    $statsBooksRows[] = [
        'slug'              => $catBook['slug'],
        'title'             => $catBook['title'],
        'image'             => $catBook['image'],
        'short_description' => $catBook['short_description'],
        'ebook_sizes'       => $catBook['ebook_sizes'],
        'word_stats'        => $ws
    ];
}

usort($statsBooksRows, static function (array $a, array $b): int {
    $sa = (int)($a['word_stats']['story_word_count'] ?? 0);
    $sb = (int)($b['word_stats']['story_word_count'] ?? 0);
    if ($sa !== $sb) {
        return $sb <=> $sa;
    }
    $ca = (int)($a['word_stats']['combined_word_count'] ?? 0);
    $cb = (int)($b['word_stats']['combined_word_count'] ?? 0);
    return $cb <=> $ca;
});

$totalCuratedLoreWords = $totalBookLoreWords + $sharedUniverseLoreWords;
$totalCombinedWords    = $totalStoryWords + $totalCuratedLoreWords;
$totalWithLyricsWords  = $totalCombinedWords + $totalLyricsWords;

$libraryStatsPayload = [
    'generated_at'                     => gmdate('c'),
    'volume_count'                     => count($masterCatalog),
    'active_story_volume_count'        => $activeStoryVolumes,
    'total_eras'                       => $totalErasCount,
    'total_chapters'                   => $totalChapsCount,
    'total_parts'                      => $totalPartsCount,
    'total_illustrations'              => $totalIllusCount,
    'total_story_words'                => $totalStoryWords,
    'total_book_lore_words'            => $totalBookLoreWords,
    'total_shared_universe_lore_words' => $sharedUniverseLoreWords,
    'total_curated_lore_words'         => $totalCuratedLoreWords,
    'total_lyrics_words'               => $totalLyricsWords,
    'total_combined_words'             => $totalCombinedWords,
    'total_combined_with_lyrics_words' => $totalWithLyricsWords,
    'total_story_pages'                => max(1, (int)round($totalStoryWords / 275)),
    'total_combined_pages'             => max(1, (int)round($totalCombinedWords / 275)),
    'total_reading_hours'              => round($totalStoryWords / 15000, 1),
    'total_novel_equivalents'          => round($totalStoryWords / 90000, 1),
    'total_combined_novel_equivalents' => round($totalCombinedWords / 90000, 1),
    'shared_lore_breakdown'            => [
        [
            'label' => 'Universal Lore Archive (CPI, Transit, Cities & Institutions)',
            'words' => $universalLoreWords
        ],
        [
            'label' => 'Amaya Rios & The Wall of Twenty Lore Dossier',
            'words' => $amayaLoreWords
        ],
        [
            'label' => 'Eastern Shore Rescue & Tactical Lore Archive',
            'words' => $rescueGameLoreWords
        ],
        [
            'label' => 'Engine Room Records Standalone Band Liner Notes & Track Lore',
            'words' => $otherErrLinerWords
        ],
        [
            'label' => 'Engine Room Records Complete Song Lyrics (All 8 Roster Bands)',
            'words' => $totalLyricsWords
        ],
        [
            'label' => 'Character Profiles, Backstage Dossiers & Editorial Standards',
            'words' => $characterListWords + $rulesLoreWords + $backstageSharedWords + $courtneyLoreWords
        ]
    ],
    'books' => $statsBooksRows
];

$libraryStatsLocalFile = $booksAppDir . '/data/library-stats.json';
$libraryStatsCdnFile   = $assetDestDir . '/../json/library-stats.json';
$libraryStatsJson      = json_encode($libraryStatsPayload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
file_put_contents($libraryStatsLocalFile, $libraryStatsJson);
if (is_dir(dirname($libraryStatsCdnFile))) {
    file_put_contents($libraryStatsCdnFile, $libraryStatsJson);
}
echo "  [Stats] Live Library Word Count & Scale Telemetry (" . number_format($totalStoryWords) . " story words / " . number_format($totalCombinedWords) . " combined words) saved to: {$libraryStatsLocalFile}\n";

// Write the local eBook file sizes manifest for books.raggiesoft.com
$ebookSizesManifestFile = $booksAppDir . '/data/ebook-sizes.json';
file_put_contents($ebookSizesManifestFile, json_encode($allEbookSizes, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "  [Sizes] eBook file sizes manifest saved to: {$ebookSizesManifestFile}\n";

// --- STEP B: COMPILE THE LISTENING ROOM (music.raggiesoft.com) HOVERCARD PREVIEWS ---
// Populate $allLinkPreviews with rich artist, album, track, and playlist entries from
// `raggiesoft-assets/engine-room-records/catalog.json` so `sophia/oliver.php` can render
// accurate album artwork (`social-preview.jpg` / `album-art.jpg`), clean track titles,
// track numbers, durations, and studio liner notes without relying on local disk checks
// on the production droplet.
$errCatalogFile = $serverRoot . '/raggiesoft-assets/engine-room-records/catalog.json';
if (is_file($errCatalogFile)) {
    $errCatalog = json_decode((string)@file_get_contents($errCatalogFile), true) ?: [];
    $artistRollup = [];
    $truncateMusicExcerpt = static function (string $rawText, int $maxLen = 215): string {
        $clean = strip_tags($rawText);
        $clean = preg_replace('/\[([^\]]+)\]\([^)]*\)/', '$1', $clean);
        $clean = preg_replace('/^#+\s*/m', '', $clean);
        $clean = preg_replace('/[*_`~>]/', '', $clean);
        $clean = trim(preg_replace('/\s+/', ' ', $clean));
        if (mb_strlen($clean) > $maxLen) {
            $cut = mb_substr($clean, 0, $maxLen - 3);
            $lastSpace = mb_strrpos($cut, ' ');
            if ($lastSpace !== false && $lastSpace > 130) {
                $cut = mb_substr($cut, 0, $lastSpace);
            }
            return rtrim($cut, " \t\n\r\0\x0B.,;:-—") . '…';
        }
        return $clean;
    };

    foreach ($errCatalog as $albumEntry) {
        $artistSlug = trim((string)($albumEntry['artistSlug'] ?? ''));
        $albumSlug  = trim((string)($albumEntry['slug'] ?? ''));
        if ($artistSlug === '' || $albumSlug === '') {
            continue;
        }
        $artistName = trim((string)($albumEntry['artist'] ?? ucwords(str_replace('-', ' ', $artistSlug))));
        $albumTitle = trim((string)($albumEntry['title'] ?? ucwords(str_replace('-', ' ', $albumSlug))));
        $albumYear  = trim((string)($albumEntry['year'] ?? ''));
        $albumTypeLabel = trim((string)($albumEntry['albumTypeLabel'] ?? 'Album'));
        $tracksList = is_array($albumEntry['tracks'] ?? null) ? $albumEntry['tracks'] : [];
        $trackCount = (int)($albumEntry['totalTracksCount'] ?? count($tracksList));

        // Prefer album social-preview.jpg if present in raggiesoft-assets, else album-art.jpg
        $relAlbumSocial = "/engine-room-records/artists/{$artistSlug}/{$albumSlug}/social-preview.jpg";
        $relAlbumCover  = "/engine-room-records/artists/{$artistSlug}/{$albumSlug}/album-art.jpg";
        $albumPreviewImg = is_file($serverRoot . '/raggiesoft-assets' . $relAlbumSocial)
            ? $relAlbumSocial
            : $relAlbumCover;

        // Track artist-level statistics for `music://{artistSlug}`
        if (!isset($artistRollup[$artistSlug])) {
            $relArtistSocial = "/engine-room-records/artists/{$artistSlug}/social-preview.jpg";
            $artistRollup[$artistSlug] = [
                'name' => $artistName,
                'albums' => 0,
                'tracks' => 0,
                'image' => is_file($serverRoot . '/raggiesoft-assets' . $relArtistSocial) ? $relArtistSocial : $albumPreviewImg
            ];
        }
        $artistRollup[$artistSlug]['albums']++;
        $artistRollup[$artistSlug]['tracks'] += $trackCount;

        $albumDesc = $truncateMusicExcerpt((string)($albumEntry['description'] ?? ''));
        if ($albumDesc === '') {
            $albumDesc = "Stream {$albumTitle} by {$artistName} in The Listening Room with synchronized lyrics, studio liner notes, and lossless master playback.";
        }

        // Register album-level preview card
        $allLinkPreviews["music://{$artistSlug}/{$albumSlug}"] = [
            'kind' => 'music',
            'kicker' => 'The Listening Room • ' . $artistName,
            'title' => $albumTitle,
            'date' => $albumYear !== '' ? "Released {$albumYear}" : 'Engine Room Records',
            'location' => "{$albumTypeLabel} • {$trackCount} " . ($trackCount === 1 ? 'Track' : 'Tracks'),
            'image' => $albumPreviewImg,
            'excerpt' => $albumDesc,
            'url' => "https://music.raggiesoft.com/{$artistSlug}/{$albumSlug}"
        ];

        // Register track-level preview cards
        foreach ($tracksList as $tIdx => $trackItem) {
            $fileName = trim((string)($trackItem['fileName'] ?? ''));
            if ($fileName === '') {
                continue;
            }
            $trackTitle = trim((string)($trackItem['title'] ?? ''));
            if ($trackTitle === '') {
                $trackTitle = ucwords(str_replace('-', ' ', preg_replace('/^\d+-\d+-/', '', $fileName)));
            }
            $version = trim((string)($trackItem['version'] ?? ''));
            if ($version !== '' && stripos($trackTitle, $version) === false) {
                $trackTitle .= " ({$version})";
            }
            $trackNum = (int)($trackItem['track'] ?? ($tIdx + 1));
            $discNum  = (int)($trackItem['disc'] ?? 1);
            $duration = trim((string)($trackItem['duration'] ?? ''));
            $trackLocParts = [$albumTitle];
            if ($discNum > 1) {
                $trackLocParts[] = "Disc {$discNum}, Track {$trackNum}";
            } else {
                $trackLocParts[] = "Track {$trackNum}";
            }
            $trackLocation = implode(' • ', $trackLocParts) . ($duration !== '' ? " ({$duration})" : '');

            $trackLore = $truncateMusicExcerpt((string)($trackItem['loreNote'] ?? ''));
            if ($trackLore === '') {
                $trackLore = $albumDesc;
            }

            $allLinkPreviews["music://{$artistSlug}/{$albumSlug}?track={$fileName}"] = [
                'kind' => 'music',
                'kicker' => 'The Listening Room • ' . $artistName,
                'title' => $trackTitle,
                'date' => $albumYear !== '' ? "Released {$albumYear}" : 'Engine Room Records',
                'location' => $trackLocation,
                'image' => $albumPreviewImg,
                'excerpt' => $trackLore,
                'url' => "https://music.raggiesoft.com/{$artistSlug}/{$albumSlug}?track={$fileName}"
            ];
        }
    }

    // Also scan any artist/album folders in `raggiesoft-assets/engine-room-records/artists/`
    // that have `album.json` / `tracks.json` so every album/track on disk is indexed.
    $artistFolders = glob($serverRoot . '/raggiesoft-assets/engine-room-records/artists/*', GLOB_ONLYDIR) ?: [];
    foreach ($artistFolders as $artistFolder) {
        $artistSlug = basename($artistFolder);
        $albumFolders = glob($artistFolder . '/*', GLOB_ONLYDIR) ?: [];
        foreach ($albumFolders as $albumFolder) {
            $albumSlug = basename($albumFolder);
            $albumKey = "music://{$artistSlug}/{$albumSlug}";
            $relAlbumSocial = "/engine-room-records/artists/{$artistSlug}/{$albumSlug}/social-preview.jpg";
            $relAlbumCover  = "/engine-room-records/artists/{$artistSlug}/{$albumSlug}/album-art.jpg";
            $albumPreviewImg = is_file($serverRoot . '/raggiesoft-assets' . $relAlbumSocial)
                ? $relAlbumSocial
                : $relAlbumCover;

            $albumMeta = is_file($albumFolder . '/album.json')
                ? (json_decode((string)@file_get_contents($albumFolder . '/album.json'), true) ?: [])
                : [];
            $tracksMeta = is_file($albumFolder . '/tracks.json')
                ? (json_decode((string)@file_get_contents($albumFolder . '/tracks.json'), true) ?: [])
                : [];
            $tracksList = is_array($tracksMeta['tracks'] ?? null) ? $tracksMeta['tracks'] : [];

            $artistName = trim((string)($albumMeta['artist'] ?? ($artistRollup[$artistSlug]['name'] ?? ucwords(str_replace('-', ' ', $artistSlug)))));
            $albumTitle = trim((string)($albumMeta['title'] ?? ucwords(str_replace('-', ' ', preg_replace('/^\d{4}-/', '', $albumSlug)))));
            $albumYear = '';
            if (preg_match('/^(\d{4})/', (string)($albumMeta['releaseDate'] ?? $albumSlug), $ym)) {
                $albumYear = $ym[1];
            }
            $albumDesc = $truncateMusicExcerpt((string)($albumMeta['description'] ?? ''));
            if ($albumDesc === '') {
                $albumDesc = "Stream {$albumTitle} by {$artistName} in The Listening Room with synchronized lyrics, studio liner notes, and lossless master playback.";
            }

            if (!isset($allLinkPreviews[$albumKey])) {
                $tCount = count($tracksList);
                $allLinkPreviews[$albumKey] = [
                    'kind' => 'music',
                    'kicker' => 'The Listening Room • ' . $artistName,
                    'title' => $albumTitle,
                    'date' => $albumYear !== '' ? "Released {$albumYear}" : 'Engine Room Records',
                    'location' => $tCount > 0 ? "{$tCount} Tracks" : 'Album Archive',
                    'image' => $albumPreviewImg,
                    'excerpt' => $albumDesc,
                    'url' => "https://music.raggiesoft.com/{$artistSlug}/{$albumSlug}"
                ];
            }

            foreach ($tracksList as $tIdx => $trackItem) {
                $fileName = trim((string)($trackItem['fileName'] ?? ''));
                if ($fileName === '') continue;
                $trackKey = "music://{$artistSlug}/{$albumSlug}?track={$fileName}";
                if (isset($allLinkPreviews[$trackKey])) continue;

                $trackTitle = trim((string)($trackItem['title'] ?? ''));
                if ($trackTitle === '') {
                    $trackTitle = ucwords(str_replace('-', ' ', preg_replace('/^\d+-\d+-/', '', $fileName)));
                }
                $trackNum = (int)($trackItem['track'] ?? ($tIdx + 1));
                $discNum  = (int)($trackItem['disc'] ?? 1);
                $duration = trim((string)($trackItem['duration'] ?? ''));
                $trackLoc = $albumTitle . ' • ' . ($discNum > 1 ? "Disc {$discNum}, Track {$trackNum}" : "Track {$trackNum}") . ($duration !== '' ? " ({$duration})" : '');
                $trackLore = $truncateMusicExcerpt((string)($trackItem['loreNote'] ?? ''));
                if ($trackLore === '') $trackLore = $albumDesc;

                $allLinkPreviews[$trackKey] = [
                    'kind' => 'music',
                    'kicker' => 'The Listening Room • ' . $artistName,
                    'title' => $trackTitle,
                    'date' => $albumYear !== '' ? "Released {$albumYear}" : 'Engine Room Records',
                    'location' => $trackLoc,
                    'image' => $albumPreviewImg,
                    'excerpt' => $trackLore,
                    'url' => "https://music.raggiesoft.com/{$artistSlug}/{$albumSlug}?track={$fileName}"
                ];
            }
        }
    }

    foreach ($artistRollup as $artistSlug => $info) {
        $allLinkPreviews["music://{$artistSlug}"] = [
            'kind' => 'music',
            'kicker' => 'The Listening Room • Artist Discography',
            'title' => $info['name'],
            'date' => 'Engine Room Records',
            'location' => "{$info['albums']} " . ($info['albums'] === 1 ? 'Album' : 'Albums') . " • {$info['tracks']} Tracks",
            'image' => $info['image'],
            'excerpt' => "Stream {$info['name']}'s complete studio and live discography in The Listening Room with synchronized lyrics, studio liner notes, and lossless master playback.",
            'url' => "https://music.raggiesoft.com/{$artistSlug}"
        ];
    }
}

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


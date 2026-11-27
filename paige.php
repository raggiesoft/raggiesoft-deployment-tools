<?php
/**
 * =============================================================================
 * Architectural Block: raggiesoft-deployment-tools/paige.php
 * =============================================================================
 * Component: Paige — The Literary Editor & Safe Person (PHP 8.5 CLI Compiler)
 * Location:  /raggiesoft-deployment-tools/paige.php
 *
 * --- PAIGE: THE LITERARY EDITOR (v7 - PHP 8.5 Edition) ---
 * "I am Michael's sister. I process his books, and I keep him safe."
 *
 * PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
 *     Even though PHP is famous for generating HTML on web servers, PHP 8.5 is
 *     also a fast, batteries-included **Command-Line Compiler** (`php paige.php`)!
 *     Authors write Ocean View Archives & Story Crossroads novels as plain-text
 *     Markdown files organized in folders:
 *       `raggiesoft-narratives/books/<slug>/e001/c001/p001.md`
 *       (`e` = Era, `c` = Chapter, `p` = Part, plus `ovab.json`, `arcs.json`,
 *        and optional `crossroads.json` + `paths/<route-id>/e001/c001/p001.md`).
 *
 *     When `jenna-sync.sh --push` (or a human author) invokes `paige.php`, Paige
 *     reads all of those Markdown manuscripts and compiles EVERY data file needed
 *     by `books.raggiesoft.com` (Web SPA), `backstage.raggiesoft.com`, and the
 *     native macOS/iOS SwiftUI & Windows .NET 10 WPF **Book Reader** apps:
 *       1. Syncs clean `.md` manuscripts to `raggiesoft-assets/raggiesoft-books/books/<slug>/`
 *          while preserving Pandoc/WeasyPrint `.epub` & `.pdf` eBook files (`rrmdir`).
 *       2. Parses YAML frontmatter (`--- ... ---`), counts readable words/illustrations,
 *          and traverses `e* -> c* -> p*.md` folders (`$compileEraTree`).
 *       3. Compiles **Story Crossroads** interactive branching novels (`crossroads.json`)
 *          into a Directed Acyclic Graph (`segments`) and enforces an automated
 *          Anti-Bleed Gate so alternate storylines never leak terms or links!
 *       4. Compiles **Story Arcs** (`arcs.json`), interleaving chapter parts with
 *          behind-the-scenes **Backstage** bonus dossiers (`story-arcs.json`).
 *       5. Emits per-book `toc.json`, Ocean View route maps (`data/routes/<slug>.json`),
 *          and compressed `<slug>-package.7z` bundles for instant offline app downloads.
 *       6. Emits library-wide `catalog.json`, `library-stats.json`, `ebook-sizes.json`,
 *          `search-index.json` (full-text search), Wikipedia-style hovercard previews
 *          (`link-previews.json`, including `music://` Listening Room cards!), and
 *          categorized Google/Bing XML sitemaps (`sitemap.xml` + `sitemaps/*.xml`)!
 *       7. Immediately after `paige.php` finishes in `jenna-sync.sh`, Jenna runs
 *          `raggiesoft-narratives/scripts/compile_ebooks.php`, which invokes **Pandoc**
 *          and **WeasyPrint** to render Illustrated & Text-Only `.epub` and `.pdf` eBooks!
 *
 * SECONDARY DIRECTIVE (SAFETY PROTOCOL / DEEP PRESSURE THERAPY):
 *     Paige is designated as Michael's "Safe Person."
 *     If execution complexity spikes or the workflow becomes overwhelming,
 *     Paige initiates "Deep Pressure Protocol" (`--grounding` / `--safe-person`):
 *     She stands close, offers grounding hugs, and remains by his side
 *     until regulation is achieved. She does not leave.
 *
 * CLI Usage:
 *     php raggiesoft-deployment-tools/paige.php
 *     php raggiesoft-deployment-tools/paige.php --book="aethel"
 *     php raggiesoft-deployment-tools/paige.php --grounding
 * =============================================================================
 */

// HOW PHP `getopt()` PARSES COMMAND-LINE FLAGS:
//   - Argument 1 (`''`) is for single-letter flags (none used here).
//   - Argument 2 (`[...]`) defines `--long` flags: a trailing colon `'book:'` means
//     `--book=<slug>` requires a string value, whereas `'grounding'` (no colon) is a boolean switch!
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

// Resolve base paths relative to `__DIR__` (PHP magic constant holding the exact directory of `paige.php`):
// `dirname(__DIR__)` steps up one directory (`~/Developer`), and `? :` is PHP's ternary conditional operator.
$parentRoot     = dirname(__DIR__);
$serverRoot     = is_dir($parentRoot . '/raggiesoft-servers')
    ? ($parentRoot . '/raggiesoft-servers')
    : $parentRoot;
$narrativesRoot = is_dir($serverRoot . '/raggiesoft-novels')
    ? ($serverRoot . '/raggiesoft-novels')
    : ($serverRoot . '/raggiesoft-narratives');
$sourceBooksDir = $narrativesRoot . '/books';
$assetDestDir   = $serverRoot . '/raggiesoft-assets/raggiesoft-books/books';
$indexDestFile  = $serverRoot . '/raggiesoft-assets/raggiesoft-books/json/search-index.json';
$booksAppDir    = is_dir($serverRoot . '/raggiesoft.com/subdomains/books')
    ? ($serverRoot . '/raggiesoft.com/subdomains/books')
    : ($serverRoot . '/raggiesoft-book-library');
$newRoutesDestDir = $booksAppDir . '/data/routes';

// `fwrite(STDERR, ...)` writes errors to Standard Error (file descriptor 2) rather than stdout, and `exit(1)` signals failure.
if (!is_dir($sourceBooksDir)) {
    fwrite(STDERR, "   ⚠️  PAIGE: I can't seem to find the narratives folder at {$sourceBooksDir}. Take your time, we can check the path together.\n");
    exit(1);
}

// `mkdir($path, 0755, true)`: third argument `true` works like Unix `mkdir -p`, creating parent folders recursively!
if (!is_dir($assetDestDir)) mkdir($assetDestDir, 0755, true);
if (!is_dir($newRoutesDestDir)) mkdir($newRoutesDestDir, 0755, true);
if (!is_dir(dirname($indexDestFile))) mkdir(dirname($indexDestFile), 0755, true);

/**
 * Recursively removes stale `.md`/`.json` files from a target CDN book folder BEFORE copying fresh ones,
 * while strictly preserving heavy Pandoc/WeasyPrint deliverables (`.epub`, `.pdf`, `.7z`, `.ebook_build_hash`).
 *
 * PHP IDIOMS EXPLAINED:
 *   - `scandir($dir)` returns `['.', '..', 'e001', ...]`, so `array_diff(..., ['.', '..'])` strips `.` and `..`
 *     (never recurse on `.` or `..`, or you would loop infinitely or walk up into parent folders!).
 *   - `@` in `@unlink($path)` suppresses non-fatal OS warnings if a file was already removed.
 *   - `in_array($needle, $haystack, true)`: `true` enables strict `===` type comparison in PHP!
 *
 * @param string $dir Target directory to prune.
 * @param array $excludeExtensions File extensions to keep (e.g., ['epub', 'pdf', '7z']).
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
                        // Preserve compiled Pandoc e-books and incremental build hashes!
                        continue;
                    }
                    @chmod($path, 0777);
                    @unlink($path);
                }
            }
        }
        // Only remove the directory itself if 0 preserved files (like `.epub`) remain inside
        $remaining = @scandir($dir);
        if ($remaining !== false && count(array_diff($remaining, ['.', '..'])) === 0) {
            @chmod($dir, 0777);
            if (!@rmdir($dir)) {
                usleep(50000);
                @rmdir($dir);
            }
        }
    }
}

/**
 * Recursively copies source manuscript files (`$src` -> `$dst`), skipping internal
 * author-only `BRANCH-CANON.md` notes and macOS `.DS_Store` metadata files.
 *
 * @param string $src Source path.
 * @param string $dst Destination path.
 */
function rcopy($src, $dst) {
    if (is_dir($src)) {
        if (!is_dir($dst)) mkdir($dst, 0755, true);
        $files = array_diff(scandir($src), ['.', '..']);
        foreach ($files as $file) {
            if (strcasecmp($file, 'BRANCH-CANON.md') === 0 || $file === '.DS_Store') {
                continue;
            }
            rcopy("$src/$file", "$dst/$file");
        }
    } else if (file_exists($src)) {
        copy($src, $dst);
    }
}

/**
 * Converts a human title (`"Chapter 1: The Crucible!"`) into a clean URL slug (`"chapter-1-the-crucible"`).
 * Uses `mb_strtolower` ("multibyte" UTF-8 safe lowercase) and `/u` Unicode regex mode.
 *
 * @param string $string Input title or folder name.
 * @return string Clean lowercase hyphenated slug.
 */
function slugify($string) {
    $slug = mb_strtolower(trim(preg_replace('/[^A-Za-z0-9-]+/u', '-', $string), '-'));
    return preg_replace('/-+/', '-', $slug);
}

/**
 * Formats a raw byte count (`1024` bytes = `1 KB`, `1048576` = `1 MB`, `1073741824` = `1 GB`)
 * into a clean consumer-friendly label (`"36.8 MB"`, `"690 KB"`) for eBook download buttons.
 * Notice PHP 8 type hints (`int $bytes` parameter type and `: string` return type)!
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
 * file sizes for all 5 deliverables: Illustrated EPUB/PDF, Text-Only EPUB/PDF (built by
 * `compile_ebooks.php` via Pandoc + WeasyPrint), and `<slug>-package.7z` (built below!).
 * `clearstatcache()` flushes PHP's internal `filesize()` cache so newly generated `.7z` sizes read accurately!
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
 * Resolves the cross-platform 7-Zip executable (`?string` means "returns `string` or `null`").
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
 * Packages `toc.json`, `ovab.json`, `landing.md`, and all `e*` Markdown chapters into a
 * solid LZMA2 `<slug>-package.7z` archive (`-t7z -mx=7 -ms=on`) so native desktop/mobile
 * Book Reader apps can download an entire 300-part novel in ONE HTTP request instead of 300!
 * `escapeshellarg()` safely quotes every shell argument, and `-xr!*.epub` excludes heavy eBooks.
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
 * Counts readable prose words in Markdown after stripping YAML frontmatter (`--- ... ---`),
 * image tags `![alt](url)`, link URLs `[label](url)` -> `label`, and HTML/Markdown symbols.
 * Uses Unicode property classes `\p{L}` (any international letter) and `\p{N}` (digits)
 * so accented names (`Zoë`, `Chloé`, `Sainte-Claire`) count accurately as single words!
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
 * Counts readable words inside a Microsoft Word `.docx` file without needing Pandoc!
 * HOW THIS WORKS: Every `.docx` file since Office 2007 is secretly a standard `.zip`
 * archive containing XML files—with the main body text stored inside `word/document.xml`!
 * PHP's `ZipArchive` reads `word/document.xml` straight out of memory and strips XML tags.
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
 * Recursively computes the deduplicated canonical lore word count inside a lore folder:
 *   - Skips `_old/`, `ai-dump/`, Word lockfiles (`~$*.docx`), and raw AI chat logs.
 *   - Computes a `sha256` cryptographic hash of every file (`$seenHashes[$hash]`) so
 *     identical files are NEVER double-counted, and skips `.docx` files when a matching
 *     `.md` stem (`$seenStems[$stem]`) was already counted!
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
    'rachel'                    => ['lore/rachel', 'backstage/books/rachel'],
    'aubrie'                    => ['lore/aubrie', 'backstage/books/aubrie'],
    'luna-leo'                  => ['lore/luna-leo', 'backstage/books/luna-leo'],
    'alex-chloe'                => ['lore/astro-kids'],
    'paige'                     => ['lore/paige'],
    'nichole'                   => ['lore/nichole'],
    'quantum-directive-3-casey' => ['lore/casey', 'backstage/books/quantum-directive-3-casey'],
    'ruby-mountain'             => ['lore/ruby-mountain'],
    'stardust-engine'           => ['backstage/music'],
    'ashley-tower'              => ['lore/ashley-tower'],
    'ad-astra'                  => ['lore/ad-astra'],
    'drew'                      => ['lore/drew'],
    'katie'                     => ['lore/katie', 'backstage/books/katie'],
    'heather'                   => ['lore/heather'],
    'nate'                      => ['lore/nate'],
    'samantha'                  => ['lore/samantha'],
    'crimson-node'              => ['lore/crimson-node', 'lore/shiloh'],
    'meredith'                  => ['lore/david-meredith'],
    'beth'                      => ['lore/beth'],
    'fractured-prisms'          => ['lore/fractured-prisms'],
    'water-planet'              => ['lore/water-planet'],
    'waystation'                => ['lore/waystation', 'backstage/books/waystation'],
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
// Global Story Arcs (Reading Playlists) registry across all novels, compiled from per-book `arcs.json`
$globalStoryArcs = [];
// Full-text search index array collecting cleaned text across all scenes
$searchIndex = [];
// Lookup map of all series eBook file sizes for `raggiesoft.com/subdomains/books/data/ebook-sizes.json`
$allEbookSizes = [];

/**
 * ============================================================================
 * IMMUTABLE SEPTEMBER 11, 2001 ZERO-IMAGES FATAL GUARDRAIL (`paige.php`)
 * ============================================================================
 * 100-LEVEL WALKTHROUGH (WHY THIS HARD GATE EXISTS):
 *   Out of permanent respect for the real lives lost and affected on
 *   Tuesday, September 11, 2001, ANY narrative part (`books/**`) or Backstage
 *   dossier (`backstage/**`) whose `date:` takes place on September 11, 2001
 *   is strictly and permanently prohibited from requesting, attaching, or
 *   rendering ANY illustration—whether via YAML frontmatter (`image:`,
 *   `images:`, `og_image:`, `ogImage:`), inline Markdown (`![alt](url)`), or
 *   raw HTML (`<img ...>`), regardless of whether the image file exists yet.
 *
 *   If ANY `raggiesoft-narratives` work violates this rule, Paige immediately
 *   emits a fatal error to `STDERR` and terminates with `exit(1)` BEFORE
 *   copying a single file to the CDN or updating any route manifest!
 */
function isSeptember112001Date(string $dateStr): bool {
    $d = trim($dateStr, " \t\n\r\0\x0B\"'");
    if ($d === '') {
        return false;
    }
    return (bool)preg_match(
        '/(?:\b2001-0?9-11\b|\b0?9[\/\-]11[\/\-]2001\b|\bSept(?:ember)?\.?\s+11(?:th)?,?\s+2001\b|\b11\s+Sept(?:ember)?\.?,?\s+2001\b)/i',
        $d
    );
}

function assertSeptember11ZeroImagesGuardrail(string $absFilePath, string $rawMarkdown): void {
    if (!preg_match('/^---([\s\S]*?)---/', ltrim($rawMarkdown), $fmMatch)) {
        return;
    }
    $fm   = $fmMatch[1];
    $body = (string)substr(ltrim($rawMarkdown), strlen($fmMatch[0]));

    $dateVal = '';
    if (preg_match('/^date:\s*(.+)$/mi', $fm, $dm)) {
        $dateVal = trim($dm[1], " \t\n\r\0\x0B\"'");
    }
    if (!isSeptember112001Date($dateVal)) {
        return;
    }

    // Check 1: Scalar or YAML-list `image:`, `images:`, `og_image:`, or `ogImage:` in frontmatter
    $hasFrontmatterImage = (bool)preg_match(
        '/^(?:image|images|og_image|ogImage):\s*(?:[^\s#][^\r\n]*|\r?\n\s*-\s*\S+)/mi',
        $fm
    );

    // Strip fenced code blocks before checking prose body for inline `![...](...)` or `<img` tags
    $bodyNoFences = (string)preg_replace('/```[\s\S]*?```/', '', $body);
    $hasInlineMarkdownImage = (bool)preg_match('/!\[[^\]]*\]\([^)]+\)/', $bodyNoFences);
    $hasRawHtmlImgTag       = (bool)preg_match('/<img\b/i', $bodyNoFences);

    if ($hasFrontmatterImage || $hasInlineMarkdownImage || $hasRawHtmlImgTag) {
        fwrite(
            STDERR,
            "\n🛑 FATAL GUARDRAIL ERROR [IMMUTABLE SEPTEMBER 11, 2001 ZERO-IMAGES RULE]:\n" .
            "   File: {$absFilePath}\n" .
            "   Date: {$dateVal}\n" .
            "   Story sections and dossiers taking place on September 11, 2001 MUST NEVER contain\n" .
            "   rendered images (`image:`, `images:`, `og_image:`, `![...](...)`, or `<img>`).\n" .
            "   Aborting build across all raggiesoft-narratives works.\n\n"
        );
        exit(1);
    }
}

// Run a library-wide pre-flight sweep across ALL `books/**` and `backstage/**` Markdown files
// BEFORE copying or modifying any CDN shelf (even when `--book=<single-slug>` is passed!).
foreach ([$sourceBooksDir, $narrativesRootDir . '/backstage'] as $guardScanRoot) {
    if (!is_dir($guardScanRoot)) {
        continue;
    }
    $guardIter = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($guardScanRoot, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($guardIter as $guardFile) {
        if (!$guardFile->isFile() || strtolower($guardFile->getExtension()) !== 'md') {
            continue;
        }
        $gPath = $guardFile->getPathname();
        $gRaw  = (string)@file_get_contents($gPath);
        if ($gRaw !== '') {
            assertSeptember11ZeroImagesGuardrail($gPath, $gRaw);
        }
    }
}

/*
 * ============================================================================
 * PRE-SCAN RAGGIESOFT BACKSTAGE DOSSIERS (`raggiesoft-narratives/backstage/`)
 * ============================================================================
 * Story Arc playlists (`books/<slug>/arcs.json`) can interleave narrative parts
 * (`{ "part": "e010/c001/p002.md" }`) with behind-the-scenes Backstage bonus
 * dossiers (`{ "backstage": "books/katie/north-lion-scales-and-tails-..." }`).
 * Pre-indexing Backstage Markdown frontmatter directly from source allows Paige
 * to compile rich, self-contained stop metadata (title, subtitle, date, artwork,
 * summary, word count, and canonical URL) with zero circular build dependency
 * on the static Backstage site build (`scripts/build.mjs`).
 */
$backstageDossierIndex = [];
$backstageRootDir = $narrativesRootDir . '/backstage';
if (is_dir($backstageRootDir)) {
    $bsIter = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($backstageRootDir, FilesystemIterator::SKIP_DOTS)
    );
    foreach ($bsIter as $bsFileInfo) {
        if (!$bsFileInfo->isFile() || strtolower($bsFileInfo->getExtension()) !== 'md') {
            continue;
        }
        $absBsPath = $bsFileInfo->getPathname();
        $relBsPath = str_replace('\\', '/', substr($absBsPath, strlen($backstageRootDir) + 1));
        $bsSlug = preg_replace('/\.md$/i', '', $relBsPath);
        if ($bsSlug === '' || str_ends_with($bsSlug, '/index') || $bsSlug === 'index') {
            continue;
        }
        $bsRaw = (string)@file_get_contents($absBsPath);
        $bsBody = $bsRaw;
        $bsTitle = ucwords(str_replace('-', ' ', basename($bsSlug)));
        $bsSubtitle = '';
        $bsCategory = '';
        $bsDate = '';
        $bsLocation = '';
        $bsImage = '';
        $bsSummary = '';

        if (preg_match('/^---([\s\S]*?)---/', ltrim($bsRaw), $bsFmMatch)) {
            $bsFm = $bsFmMatch[1];
            $bsBody = str_replace($bsFmMatch[0], '', $bsRaw);
            $extractScalar = static function (string $fm, string $key): string {
                if (preg_match('/^' . preg_quote($key, '/') . ':\s*(.+)$/m', $fm, $m)) {
                    $v = trim($m[1]);
                    if ((str_starts_with($v, '"') && str_ends_with($v, '"')) ||
                        (str_starts_with($v, "'") && str_ends_with($v, "'"))) {
                        $v = substr($v, 1, -1);
                    }
                    return trim(str_replace('\"', '"', $v));
                }
                return '';
            };
            $t = $extractScalar($bsFm, 'title');
            if ($t !== '') $bsTitle = $t;
            $bsSubtitle = $extractScalar($bsFm, 'subtitle');
            $bsCategory = $extractScalar($bsFm, 'category');
            $bsDate     = $extractScalar($bsFm, 'date');
            $bsLocation = $extractScalar($bsFm, 'location');
            $bsSummary  = $extractScalar($bsFm, 'summary');
            $rawBsImg   = $extractScalar($bsFm, 'image');
            if ($rawBsImg !== '') {
                $normBsImg = preg_replace('/#.*$/', '', str_replace(['{{CDN}}', '{{cms}}', 'https://assets.raggiesoft.com'], '', $rawBsImg));
                $normBsImg = '/' . ltrim((string)$normBsImg, '/');
                if ($normBsImg !== '/') {
                    $bsImage = $normBsImg;
                }
            }
        }
        $bsWords = countReadableProseWords($bsBody, false);
        $backstageDossierIndex[$bsSlug] = [
            'slug'            => $bsSlug,
            'title'           => $bsTitle,
            'subtitle'        => $bsSubtitle,
            'category'        => $bsCategory,
            'date'            => $bsDate,
            'location'        => $bsLocation,
            'image'           => $bsImage,
            'summary'         => $bsSummary,
            'word_count'      => $bsWords,
            'reading_minutes' => max(1, (int)ceil($bsWords / 250)),
            'url'             => 'https://backstage.raggiesoft.com/' . ltrim($bsSlug, '/') . '/',
        ];
    }
}

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
$allLinkPreviews['/arcs'] = [
    'kind' => 'book',
    'title' => 'Story Arcs & Reading Playlists',
    'series' => 'Ocean View Archives',
    'series_slug' => 'arcs',
    'kicker' => 'Ocean View Archives • Curated Reading Playlists',
    'date' => '',
    'location' => 'Follow Individual Storylines Across Every Era',
    'image' => '/raggiesoft-books/images/scenes/katie/b005/jun_2018_maplewood_north_lion_ribbon_cutting_earned_hug_nate_heather_wesley.jpg',
    'excerpt' => 'Follow curated chapter-by-chapter Story Arcs—like Katie Prairie\'s political career or Heather, Wesley, and Chelsea at North Lion Scales & Tails—complete with behind-the-scenes bonus stops.',
    'url' => '/arcs'
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
    // Lookup table mapping relative part file paths (`e010/c001/p002.md`) to compiled TOC metadata for `arcs.json` & `crossroads.json`
    $seriesPartsByRelPath = [];

    /**
     * Reusable Era/Chapter/Part Directory Compiler (`$compileEraTree`)
     * -------------------------------------------------------------------------
     * Scans any root directory containing `e*` -> `c*` -> `p*.md` folders—used
     * both for the primary novel root (`books/<slug>/e*`) and for coequal
     * Story Crossroads path trees (`books/<slug>/paths/<path-id>/e*`).
     *
     * HOW PHP CLOSURES & `use (&$var)` WORK (100-LEVEL PHP LESSON):
     *   Unlike JavaScript/Python where inner functions automatically capture
     *   outer variables, PHP closures explicitly list outer variables in `use (...)`:
     *     - `&$routeData` (with `&` = **pass-by-reference**): Mutations inside this
     *       function directly update the outer `$routeData`, `$searchIndex`, and
     *       word/illustration counters!
     *     - `$seriesSlug` (no `&` = **pass-by-value**): Read-only copy of outer string.
     */
    $compileEraTree = function (
        string $scanRootDir,
        string $routePrefix,
        ?string $pathId = null,
        ?string $crossroadsId = null
    ) use (
        &$routeData,
        &$seriesIllustrationCount,
        &$seriesStoryWordCount,
        &$seriesChapCountTotal,
        &$seriesPartCountTotal,
        &$seriesPartAbsPaths,
        &$seriesPartsByRelPath,
        &$allLinkPreviews,
        &$searchIndex,
        &$firstRouteUrl,
        &$lastRouteUrl,
        $narrativeDir,
        $seriesSlug,
        $seriesTitle,
        $seriesMeta,
        $serverRoot
    ): array {
        $compiledEras = [];
        // Level 1 of 3: Discover `e001`, `e002`, ... Era folders (`GLOB_ONLYDIR` ignores files)
        $bDirs = glob($scanRootDir . '/e*', GLOB_ONLYDIR) ?: [];
        sort($bDirs); // Alphabetical sort keeps zero-padded `e001..e099` strictly chronological!

        foreach ($bDirs as $bIndex => $bDir) {
            $bName = basename($bDir);
            // `str_replace('e', '', 'e004')` -> `'004'`, and `intval('004')` -> integer `4`
            $eraNum = intval(str_replace('e', '', $bName));

            $eraTitle = "Era {$eraNum}";
            $metaPath = $bDir . '/ovab.json';

            // Load human-readable Era title from `eXXX/ovab.json` if present
            if (file_exists($metaPath)) {
                $meta = json_decode(file_get_contents($metaPath), true);
                if (isset($meta['title'])) $eraTitle = $meta['title'];
            }
            $eraSlug = slugify(strip_tags($eraTitle));

            // Register the era's TOC route (`__ERA_TOC__|<bIndex>` for root, `__ERA_TOC__|<pathId>|<bIndex>` for Story Crossroads paths)
            $eraRouteUrl = "{$routePrefix}/{$eraSlug}";
            $eraFileToken = ($pathId !== null && $pathId !== '')
                ? "__ERA_TOC__|{$pathId}|{$bIndex}"
                : "__ERA_TOC__|{$bIndex}";
            $eraRouteCfg = [
                "view" => "pages/raggiesoft-books/books/viewer",
                "title" => $eraTitle,
                "theme" => "raggiesoft-books",
                "filePath" => $eraFileToken
            ];
            if ($pathId !== null && $pathId !== '') {
                $eraRouteCfg['pathId'] = $pathId;
            }
            if ($crossroadsId !== null && $crossroadsId !== '') {
                $eraRouteCfg['crossroadsId'] = $crossroadsId;
            }
            $routeData[$eraRouteUrl] = $eraRouteCfg;

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
            if ($pathId !== null && $pathId !== '') {
                $tocEra['path_id'] = $pathId;
            }

            // Level 2 of 3: Auto-discover Chapter directories (`c001`, `c002`, ...) inside this Era
            $cDirs = glob($bDir . '/c*', GLOB_ONLYDIR) ?: [];
            sort($cDirs);

            foreach ($cDirs as $cIndex => $cDir) {
                $seriesChapCountTotal++;
                $cName = basename($cDir);
                $chapNum = intval(str_replace('c', '', $cName));

                $chapTitle = "Chapter {$chapNum}";
                $metaPath = $cDir . '/ovab.json';

                // Resolve chapter title from local `cXXX/ovab.json`
                if (file_exists($metaPath)) {
                    $meta = json_decode(file_get_contents($metaPath), true);
                    if (isset($meta['title'])) $chapTitle = $meta['title'];
                }
                $chapSlug = slugify(strip_tags($chapTitle));

                // Register the chapter's TOC route
                $chapRouteUrl = "{$eraRouteUrl}/{$chapSlug}";
                $chapFileToken = ($pathId !== null && $pathId !== '')
                    ? "__CHAP_TOC__|{$pathId}|{$bIndex}|{$cIndex}"
                    : "__CHAP_TOC__|{$bIndex}|{$cIndex}";
                $chapRouteCfg = [
                    "view" => "pages/raggiesoft-books/books/viewer",
                    "title" => $chapTitle,
                    "theme" => "raggiesoft-books",
                    "filePath" => $chapFileToken
                ];
                if ($pathId !== null && $pathId !== '') {
                    $chapRouteCfg['pathId'] = $pathId;
                }
                if ($crossroadsId !== null && $crossroadsId !== '') {
                    $chapRouteCfg['crossroadsId'] = $crossroadsId;
                }
                $routeData[$chapRouteUrl] = $chapRouteCfg;

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
                if ($pathId !== null && $pathId !== '') {
                    $tocChap['path_id'] = $pathId;
                }

                // Level 3 of 3: Auto-discover individual Part Markdown files (`p001.md`, `p002.md`, ...)
                $pFiles = glob($cDir . '/p*.md') ?: [];
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
                    $partBackstageSlugs = [];
                    $partContent = file_get_contents($pFile);
                    $bodyWithoutFrontmatter = $partContent;

                    // HOW PAIGE PARSES YAML FRONTMATTER (`--- ... ---`):
                    //   Every `pXXX.md` starts with a `---` metadata block at the top containing
                    //   `title:`, `date:`, `start_time:`, `location:`, `pov:`, `image:`/`images:`, etc.
                    //   `preg_match('/^---([\s\S]*?)---/', ...)` captures everything inside `--- ... ---`
                    //   into `$matches[1]` (`$frontmatterRaw`) and strips it off `$bodyWithoutFrontmatter`!
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
                            // Strip any redundant leading "Part X:" prefix from YAML `title:` so
                            // multi-part chapters never render "Part X: Part X: <Title>".
                            $extractedTitle = trim((string)preg_replace('/^(?:Part\s+\d+\s*:\s*)+/i', '', $extractedTitle));
                            if ($extractedTitle !== '' && strcasecmp($extractedTitle, 'Untitled Chapter') !== 0 && strcasecmp($extractedTitle, 'Untitled') !== 0) {
                                $yamlTitle = $extractedTitle;
                            } elseif ($chapPartCount === 1 && $partNum === 1) {
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

                        // Mini Line-by-Line State Machine for YAML Scalar OR Multi-Item `- ...` Lists:
                        // Handles both `image: "/foo.jpg"` AND multi-line `images:\n  - "/a.jpg"\n  - "/b.jpg"`
                        // (plus `image_alt` / `image_alts` and `backstage` dossier links) without needing a C YAML extension!
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
                                } elseif ($k === 'backstage') {
                                    if ($v === '') {
                                        $currentListKey = 'backstage';
                                    } else {
                                        $cleanVal = trim($v, "/ \t\"'");
                                        if ($cleanVal !== '') $partBackstageSlugs[] = $cleanVal;
                                    }
                                }
                            } elseif ($currentListKey !== null && preg_match('/^\s*-\s+(.*)$/', $fmLine, $listMatch)) {
                                $itemVal = trim($listMatch[1], " \t\"'");
                                if ($itemVal !== '') {
                                    if ($currentListKey === 'image') {
                                        $fmImageUrls[] = $itemVal;
                                    } elseif ($currentListKey === 'image_alt') {
                                        $fmImageAlts[] = $itemVal;
                                    } elseif ($currentListKey === 'backstage') {
                                        $cleanBs = trim($itemVal, "/ \t\"'");
                                        if ($cleanBs !== '') $partBackstageSlugs[] = $cleanBs;
                                    }
                                }
                            } elseif (preg_match('/^\S/', $fmLine)) {
                                $currentListKey = null;
                            }
                        }

                        // Normalize `{{CDN}}` / `https://assets.raggiesoft.com` prefixes and verify the `.jpg`/`.png` physically exists on disk!
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

                    // Also discover any inline Markdown images (`![alt](url)`) inside the scene body (`PREG_SET_ORDER` groups each match cleanly)
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

                    // Smart Polish:
                    // - When a Chapter has 2+ Parts (or explicit Part > 1), display "Part X: <Title>".
                    // - When a Chapter has only 1 Part (`p001.md`), omit the redundant "Part 1:" prefix.
                    $partTitle = ($chapPartCount > 1 || $partNum > 1)
                        ? "Part {$partNum}: {$yamlTitle}"
                        : $yamlTitle;
                    $partSlug = slugify(strip_tags($partTitle));

                    // Construct final content route
                    $routeUrl = "{$chapRouteUrl}/{$partSlug}";
                    if ($pathId === null && $firstRouteUrl === null) {
                        $firstRouteUrl = $routeUrl; // Capture the very first reading route of the shared trunk
                    }

                    $relPath = str_replace($narrativeDir . '/', '', $pFile);
                    $partRouteCfg = [
                        "view" => "pages/raggiesoft-books/books/viewer",
                        "title" => $partTitle,
                        "theme" => "raggiesoft-books",
                        "filePath" => $relPath
                    ];
                    if ($pathId !== null && $pathId !== '') {
                        $partRouteCfg['pathId'] = $pathId;
                    }
                    if ($crossroadsId !== null && $crossroadsId !== '') {
                        $partRouteCfg['crossroadsId'] = $crossroadsId;
                    }
                    $routeData[$routeUrl] = $partRouteCfg;
                    if ($pathId === null) {
                        $lastRouteUrl = $routeUrl; // Continually update to capture the very last trunk/inline part
                    }

                    $partImgCount = count($partImages);
                    $chapIllustrationCount += $partImgCount;
                    $eraIllustrationCount += $partImgCount;
                    $seriesIllustrationCount += $partImgCount;

                    // Strip HTML and Markdown syntax from `$bodyWithoutFrontmatter` to build the plain-text `$searchIndex` entry
                    $cleanBody = strip_tags($bodyWithoutFrontmatter);
                    $cleanBody = preg_replace('/[#_*\[\]>]/', '', $cleanBody);
                    $cleanBody = preg_replace('/\s+/', ' ', $cleanBody);
                    $cleanBody = trim($cleanBody);

                    // Extract a clean ~215-character excerpt cut neatly on the last space (`mb_strrpos`) for Wikipedia-style hovercards
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

                    // Finalize TOC structure with parts, word count telemetry (`250` words/min reading pace), and illustration manifest
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
                    if ($pathId !== null && $pathId !== '') {
                        $partEntry['path_id'] = $pathId;
                    }
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
                    if (!empty($partBackstageSlugs)) {
                        $partEntry['backstage'] = array_values(array_unique($partBackstageSlugs));
                    }
                    $tocChap['parts'][] = $partEntry;

                    // Index compiled part metadata by relative path (`eXXX/cYYY/pZZZ.md` or `paths/<id>/...`) for `O(1)` lookup in `arcs.json` & `crossroads.json`
                    $seriesPartsByRelPath[$relPath] = [
                        'part_num'        => $partNum,
                        'part_title'      => $partTitle,
                        'era_num'         => $eraNum,
                        'era_title'       => $eraTitle,
                        'chap_num'        => $chapNum,
                        'chap_title'      => $chapTitle,
                        'file_path'       => $relPath,
                        'url'             => $partStandaloneUrl,
                        'route_url'       => $routeUrl,
                        'date'            => $partDate !== '' ? $partDate : ($partStardate !== '' ? "Stardate {$partStardate}" : $partRealmTime),
                        'location'        => $partLocation,
                        'excerpt'         => $partExcerpt,
                        'image'           => ($partImgCount > 0) ? $partImages[0]['src'] : '',
                        'word_count'      => $partWordCount,
                        'reading_minutes' => $partReadingMinutes,
                        'backstage'       => $partEntry['backstage'] ?? [],
                    ];

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
                    if ($chapPartCount === 1 && $partNum === 1 && strpos($partSlug, 'part-1-') !== 0) {
                        $allLinkPreviews[str_replace('/raggiesoft-books/books', '', "{$chapRouteUrl}/part-1-{$partSlug}")] = $scenePreviewPayload;
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

                // Register chapter-level preview card (inheriting first illustrated part's artwork & opening excerpt)
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
            $compiledEras[] = $tocEra;

            // Register era-level preview card (`break 2` jumps out of BOTH nested `foreach` loops as soon as the first illustration is found!)
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

        return $compiledEras;
    };

    // Compile the primary `e*` directory tree
    $tocBooks = $compileEraTree($narrativeDir, "/raggiesoft-books/books/{$seriesSlug}", null, null);

    /*
     * ========================================================================
     * COMPILE MULTI-CROSSROADS NARRATIVE GRAPH (`books/<slug>/crossroads.json`)
     * ========================================================================
     * Supports ANY number of sequential or nested Story Crossroads at ANY point
     * in a novel (`root e*` chapters OR nested inside `paths/<id>/e*` branches),
     * with `2..N` coequal options per Crossroads.
     *
     * Compiles a deterministic Directed Acyclic Segment Graph (`segments`):
     *   - `"__root__"`: Shared opening eras/chapters/parts up to the first Crossroads.
     *   - `"<option-id>"`: Continuation segment for `<option-id>`, stopping cleanly at
     *     `next_crossroads_id` (if another Crossroads follows along that branch) or
     *     continuing to that storyline's conclusion (`next_crossroads_id = null`).
     *   - Every segment, part, and route carries `required_choices` (`{cxId: optId}`)
     *     so deep-linking to any chapter at any depth hydrates the exact ancestor
     *     Crossroads choices in O(1) across Web PWA, SwiftUI, and Windows WPF.
     */
    $compiledCrossroadsList = [];
    $compiledCrossroadsById = [];
    $compiledPathsMap = [];
    $compiledSegmentsMap = [];
    $trunkEras = [];
    $crossroadsManifestPath = $narrativeDir . '/crossroads.json';

    if (is_file($crossroadsManifestPath)) {
        $rawCxDoc = json_decode((string)@file_get_contents($crossroadsManifestPath), true);
        $rawCxList = is_array($rawCxDoc['crossroads'] ?? null) ? $rawCxDoc['crossroads'] : [];

        // Step 1: Pre-compile all `paths_dir` containers referenced by any Crossroads option
        $containerTrees = ['' => $tocBooks];
        foreach ($rawCxList as $rawCx) {
            $cxIdPre = trim((string)($rawCx['id'] ?? ''));
            foreach (($rawCx['options'] ?? []) as $rawOpt) {
                $optIdPre = trim((string)($rawOpt['id'] ?? ''));
                $optTypePre = trim((string)($rawOpt['source_type'] ?? 'paths_dir'));
                if ($optIdPre === '' || $optTypePre !== 'paths_dir') {
                    continue;
                }
                $relSrcDir = trim(str_replace('\\', '/', trim((string)($rawOpt['source_dir'] ?? "paths/{$optIdPre}"))), '/');
                if ($relSrcDir !== '' && !isset($containerTrees[$relSrcDir])) {
                    $absSrcDir = $narrativeDir . '/' . $relSrcDir;
                    if (is_dir($absSrcDir)) {
                        $containerTrees[$relSrcDir] = $compileEraTree(
                            $absSrcDir,
                            "/raggiesoft-books/books/{$seriesSlug}/{$relSrcDir}",
                            $optIdPre,
                            $cxIdPre
                        );
                    } else {
                        fwrite(STDERR, "  [Crossroads Warning] {$seriesSlug}/{$cxIdPre}: Missing path directory '{$relSrcDir}'.\n");
                    }
                }
            }
        }

        // Step 2: Assign each valid Crossroads to its container (`""` for root `e*`, or `"paths/<dir>"` for nested branches).
        // `fn($a, $b) => strlen($b) <=> strlen($a)` uses PHP's `<=>` ("spaceship") comparison operator
        // (`-1`, `0`, or `+1`) to sort longest path prefixes first so nested sub-branches match accurately!
        $crossroadsByContainer = [];
        $knownContainerPrefixes = array_keys($containerTrees);
        usort($knownContainerPrefixes, static fn($a, $b) => strlen($b) <=> strlen($a));

        foreach ($rawCxList as $rawCx) {
            $cxId = trim((string)($rawCx['id'] ?? ''));
            $triggerRel = ltrim(str_replace('\\', '/', trim((string)($rawCx['trigger_part'] ?? ''))), '/');
            if ($cxId === '' || $triggerRel === '' || !isset($seriesPartsByRelPath[$triggerRel])) {
                fwrite(STDERR, "  [Crossroads Warning] {$seriesSlug}: Invalid crossroads '{$cxId}' or missing trigger_part '{$triggerRel}'.\n");
                continue;
            }
            $matchedContainer = '';
            foreach ($knownContainerPrefixes as $cPrefix) {
                if ($cPrefix !== '' && str_starts_with($triggerRel, $cPrefix . '/')) {
                    $matchedContainer = $cPrefix;
                    break;
                }
            }
            $rawCx['_trig_meta'] = $seriesPartsByRelPath[$triggerRel];
            $rawCx['_trigger_rel'] = $triggerRel;
            $crossroadsByContainer[$matchedContainer][] = $rawCx;
        }

        // Sort multiple sequential Crossroads inside the same container chronologically by `(era_num, chap_num, part_num)`.
        // Note: `foreach (... as &$cxGroup)` iterates by reference; ALWAYS `unset($cxGroup)` right after a `&` loop in PHP!
        foreach ($crossroadsByContainer as $cKey => &$cxGroup) {
            usort($cxGroup, static function (array $a, array $b): int {
                $ma = $a['_trig_meta'];
                $mb = $b['_trig_meta'];
                if ((int)$ma['era_num'] !== (int)$mb['era_num']) return (int)$ma['era_num'] <=> (int)$mb['era_num'];
                if ((int)$ma['chap_num'] !== (int)$mb['chap_num']) return (int)$ma['chap_num'] <=> (int)$mb['chap_num'];
                return (int)$ma['part_num'] <=> (int)$mb['part_num'];
            });
        }
        unset($cxGroup);

        // Step 3: Splits an Era/Chapter/Part tree cleanly into `[$preEras, $postEras]` right at `($trigEra, $trigChap, $trigPart)`
        // so chapters up through the Crossroads trigger belong to the parent segment, and any inline continuation parts belong to `$postEras`.
        $splitErasAtTrigger = static function (array $sourceEras, int $trigEra, int $trigChap, int $trigPart): array {
            $preEras = [];
            $postEras = [];
            foreach ($sourceEras as $srcEra) {
                $eNum = (int)($srcEra['era_num'] ?? 0);
                if ($eNum < $trigEra) {
                    $preEras[] = $srcEra;
                } elseif ($eNum > $trigEra) {
                    $postEras[] = $srcEra;
                } else {
                    $preChaps = [];
                    $postChaps = [];
                    foreach (($srcEra['chapters'] ?? []) as $srcChap) {
                        $cNum = (int)($srcChap['chap_num'] ?? 0);
                        if ($cNum < $trigChap) {
                            $preChaps[] = $srcChap;
                        } elseif ($cNum > $trigChap) {
                            $postChaps[] = $srcChap;
                        } else {
                            $tParts = [];
                            $pParts = [];
                            foreach (($srcChap['parts'] ?? []) as $srcPart) {
                                if ((int)($srcPart['part_num'] ?? 0) <= $trigPart) {
                                    $tParts[] = $srcPart;
                                } else {
                                    $pParts[] = $srcPart;
                                }
                            }
                            if (!empty($tParts)) {
                                $tChap = $srcChap;
                                $tChap['parts'] = $tParts;
                                $tChap['word_count'] = array_sum(array_column($tParts, 'word_count'));
                                $tChap['illustration_count'] = array_sum(array_map(static fn($p) => (int)($p['image_count'] ?? (!empty($p['image']) ? 1 : 0)), $tParts));
                                $preChaps[] = $tChap;
                            }
                            if (!empty($pParts)) {
                                $pChap = $srcChap;
                                $pChap['parts'] = $pParts;
                                $pChap['word_count'] = array_sum(array_column($pParts, 'word_count'));
                                $pChap['illustration_count'] = array_sum(array_map(static fn($p) => (int)($p['image_count'] ?? (!empty($p['image']) ? 1 : 0)), $pParts));
                                $postChaps[] = $pChap;
                            }
                        }
                    }
                    if (!empty($preChaps)) {
                        $tEra = $srcEra;
                        $tEra['chapters'] = $preChaps;
                        $tEra['word_count'] = array_sum(array_column($preChaps, 'word_count'));
                        $tEra['illustration_count'] = array_sum(array_column($preChaps, 'illustration_count'));
                        $preEras[] = $tEra;
                    }
                    if (!empty($postChaps)) {
                        $pEra = $srcEra;
                        $pEra['chapters'] = $postChaps;
                        $pEra['word_count'] = array_sum(array_column($postChaps, 'word_count'));
                        $pEra['illustration_count'] = array_sum(array_column($postChaps, 'illustration_count'));
                        $postEras[] = $pEra;
                    }
                }
            }
            return [$preEras, $postEras];
        };

        // Step 4: Finalizes one Directed Acyclic Graph (DAG) segment (`"__root__"` or `"<option-id>"`),
        // wiring `prevUrl`/`nextUrl` navigation links along that branch and casting `(object)$requiredChoices`
        // so `json_encode` always emits a JSON object `{}` rather than an empty JSON array `[]`!
        $finalizeNarrativeSegment = function (
            string $segmentId,
            array $segEras,
            ?string $nextCrossroadsId,
            array $requiredChoices,
            ?array $optionMeta,
            ?string $prevTriggerRouteUrl
        ) use (&$routeData, &$compiledSegmentsMap, &$compiledPathsMap, $seriesSlug, $seriesMeta, &$seriesPartsByRelPath): array {
            $isRootSeg = ($segmentId === '__root__');
            $segPathId = $isRootSeg ? null : $segmentId;
            $segCxId   = $optionMeta['crossroads_id'] ?? null;

            $segPartRoutes = [];
            $segPartEntries = [];
            $segWords = 0;
            $segHeroImg = '/raggiesoft-books/images/covers/og/' . $seriesSlug . '.jpg';
            $foundHero = false;

            foreach ($segEras as &$se) {
                if ($segPathId !== null) {
                    $se['path_id'] = $segPathId;
                    $se['required_choices'] = (object)$requiredChoices;
                }
                foreach ($se['chapters'] as &$sc) {
                    if ($segPathId !== null) {
                        $sc['path_id'] = $segPathId;
                        $sc['required_choices'] = (object)$requiredChoices;
                    }
                    foreach ($sc['parts'] as &$sp) {
                        if ($segPathId !== null) {
                            $sp['path_id'] = $segPathId;
                        }
                        if (!empty($requiredChoices)) {
                            $sp['required_choices'] = (object)$requiredChoices;
                        }
                        $fullRUrl = '/raggiesoft-books/books' . $sp['url'];
                        if (isset($routeData[$fullRUrl])) {
                            if ($segPathId !== null) {
                                $routeData[$fullRUrl]['pathId'] = $segPathId;
                            }
                            if ($segCxId !== null) {
                                $routeData[$fullRUrl]['crossroadsId'] = $segCxId;
                            }
                            if (!empty($requiredChoices)) {
                                $routeData[$fullRUrl]['requiredChoices'] = (object)$requiredChoices;
                            }
                        }
                        $segPartRoutes[] = $fullRUrl;
                        $segPartEntries[] = $sp;
                        $segWords += (int)($sp['word_count'] ?? 0);
                        if (!$foundHero && !empty($sp['image'])) {
                            $segHeroImg = (string)$sp['image'];
                            $foundHero = true;
                        }
                    }
                    unset($sp);
                }
                unset($sc);
            }
            unset($se);

            $segCount = count($segPartRoutes);
            foreach ($segPartRoutes as $idx => $rUrl) {
                if (!isset($routeData[$rUrl])) {
                    continue;
                }
                if ($idx === 0) {
                    if ($prevTriggerRouteUrl !== null && $prevTriggerRouteUrl !== '') {
                        $routeData[$rUrl]['prevUrl'] = $prevTriggerRouteUrl;
                    } else {
                        $routeData[$rUrl]['noPrev'] = true;
                    }
                } else {
                    $routeData[$rUrl]['prevUrl'] = $segPartRoutes[$idx - 1];
                }

                if ($idx < $segCount - 1) {
                    $routeData[$rUrl]['nextUrl'] = $segPartRoutes[$idx + 1];
                } else {
                    if ($nextCrossroadsId !== null || empty($seriesMeta['next_series_url'])) {
                        $routeData[$rUrl]['noNext'] = true;
                    }
                }
            }

            $entryPart = !empty($optionMeta['entry_part'])
                ? $optionMeta['entry_part']
                : (string)($segPartEntries[0]['file_path'] ?? '');
            $entryUrl = isset($seriesPartsByRelPath[$entryPart])
                ? (string)$seriesPartsByRelPath[$entryPart]['url']
                : (string)($segPartEntries[0]['url'] ?? '');
            $readingMins = max(1, (int)ceil($segWords / 250));

            $segmentRecord = [
                'id'                 => $segmentId,
                'crossroads_id'      => $segCxId,
                'label'              => $optionMeta['label'] ?? ($isRootSeg ? 'Opening Chapters' : $segmentId),
                'subtitle'           => $optionMeta['subtitle'] ?? '',
                'entry_part'         => $entryPart,
                'entry_url'          => $entryUrl,
                'next_crossroads_id' => $nextCrossroadsId,
                'required_choices'   => (object)$requiredChoices,
                'forbidden_terms'    => $optionMeta['forbidden_terms'] ?? [],
                'part_count'         => $segCount,
                'word_count'         => $segWords,
                'reading_minutes'    => $readingMins,
                'image'              => $segHeroImg,
                'eras'               => $segEras,
            ];
            $compiledSegmentsMap[$segmentId] = $segmentRecord;
            if (!$isRootSeg) {
                $compiledPathsMap[$segmentId] = $segmentRecord;
            }
            return $segmentRecord;
        };

        // Recursive Graph Slicer: Declaring `$sliceContainerIntoSegments = null;` first and capturing
        // `&$sliceContainerIntoSegments` by reference allows this PHP closure to call ITSELF recursively
        // on arbitrarily nested Story Crossroads branches!
        $sliceContainerIntoSegments = null;
        $sliceContainerIntoSegments = function (
            string $containerKey,
            array $workingEras,
            string $currentSegId,
            array $inheritedChoices,
            ?array $currentOptMeta,
            ?string $incomingTriggerRouteUrl
        ) use (
            &$sliceContainerIntoSegments,
            &$compiledCrossroadsById,
            $crossroadsByContainer,
            $containerTrees,
            $splitErasAtTrigger,
            $finalizeNarrativeSegment
        ): void {
            $containerCxs = $crossroadsByContainer[$containerKey] ?? [];
            foreach ($containerCxs as $rawCx) {
                $cxId = trim((string)$rawCx['id']);
                $trigMeta = $rawCx['_trig_meta'];
                $triggerRel = (string)$rawCx['_trigger_rel'];
                $trigRouteUrl = (string)$trigMeta['route_url'];
                $trigStandaloneUrl = (string)$trigMeta['url'];
                $cxParentChoices = $inheritedChoices;

                [$preEras, $postEras] = $splitErasAtTrigger(
                    $workingEras,
                    (int)$trigMeta['era_num'],
                    (int)$trigMeta['chap_num'],
                    (int)$trigMeta['part_num']
                );

                $finalizeNarrativeSegment(
                    $currentSegId,
                    $preEras,
                    $cxId,
                    $cxParentChoices,
                    $currentOptMeta,
                    $incomingTriggerRouteUrl
                );

                $compiledOptions = [];
                $inlineNextOpt = null;

                foreach (($rawCx['options'] ?? []) as $rawOpt) {
                    $optId = trim((string)($rawOpt['id'] ?? ''));
                    $optLabel = trim((string)($rawOpt['label'] ?? ''));
                    $optSubtitle = trim((string)($rawOpt['subtitle'] ?? ''));
                    $optType = trim((string)($rawOpt['source_type'] ?? 'paths_dir'));
                    if ($optId === '' || $optLabel === '') {
                        continue;
                    }
                    $optChoices = array_merge($cxParentChoices, [$cxId => $optId]);
                    $optEntryPartHint = !empty($rawOpt['entry_part'])
                        ? ltrim(str_replace('\\', '/', trim((string)$rawOpt['entry_part'])), '/')
                        : '';
                    $optMeta = [
                        'id'              => $optId,
                        'crossroads_id'   => $cxId,
                        'label'           => $optLabel,
                        'subtitle'        => $optSubtitle,
                        'entry_part'      => $optEntryPartHint,
                        'forbidden_terms' => is_array($rawOpt['forbidden_terms'] ?? null) ? array_values($rawOpt['forbidden_terms']) : [],
                    ];

                    if ($optType === 'paths_dir') {
                        $relSrcDir = trim(str_replace('\\', '/', trim((string)($rawOpt['source_dir'] ?? "paths/{$optId}"))), '/');
                        if (!isset($containerTrees[$relSrcDir])) {
                            continue;
                        }
                        $sliceContainerIntoSegments(
                            $relSrcDir,
                            $containerTrees[$relSrcDir],
                            $optId,
                            $optChoices,
                            $optMeta,
                            $trigRouteUrl
                        );
                        $compiledOptions[] = ['_opt_id' => $optId];
                    } elseif ($optType === 'inline_continuation') {
                        $inlineNextOpt = [
                            'id'      => $optId,
                            'choices' => $optChoices,
                            'meta'    => $optMeta,
                        ];
                        $compiledOptions[] = ['_opt_id' => $optId];
                    }
                }

                $compiledCrossroadsById[$cxId] = [
                    'id'               => $cxId,
                    'trigger_part'     => $triggerRel,
                    'trigger_url'      => $trigStandaloneUrl,
                    'kicker'           => trim((string)($rawCx['kicker'] ?? 'Story Crossroads')),
                    'title'            => trim((string)($rawCx['title'] ?? 'Choose How the Story Continues')),
                    'prompt'           => trim((string)($rawCx['prompt'] ?? '')),
                    'required_choices' => (object)$cxParentChoices,
                    '_option_Order'    => array_column($compiledOptions, '_opt_id'),
                    '_trig_route_url'  => $trigRouteUrl,
                ];

                if ($inlineNextOpt !== null) {
                    $workingEras = $postEras;
                    $currentSegId = $inlineNextOpt['id'];
                    $inheritedChoices = $inlineNextOpt['choices'];
                    $currentOptMeta = $inlineNextOpt['meta'];
                    $incomingTriggerRouteUrl = $trigRouteUrl;
                } else {
                    $workingEras = [];
                    $currentSegId = '';
                }
            }

            if ($currentSegId !== '' && !empty($workingEras)) {
                $finalizeNarrativeSegment(
                    $currentSegId,
                    $workingEras,
                    null,
                    $inheritedChoices,
                    $currentOptMeta,
                    $incomingTriggerRouteUrl
                );
            }
        };

        $sliceContainerIntoSegments('', $tocBooks, '__root__', [], null, null);
        $trunkEras = $compiledSegmentsMap['__root__']['eras'] ?? $tocBooks;

        // Step 5: Automated Story Crossroads Anti-Bleed Gate (`forbidden_terms`, `story_path:` YAML, & cross-branch hyperlinks).
        // When writing an interactive novel with alternate timelines (e.g., Option A vs. Option B),
        // an author must NEVER accidentally reference an event/character unique to Option B inside Option A!
        // Paige enforces 3 hard compile-time checks across every branched `.md` file (`exit(1)` aborts the build on any leak!):
        //   1. Every file inside `paths/<branch>/` MUST declare `story_path: "<branch>"` in its YAML frontmatter.
        //   2. Zero lines may match any sibling branch's `forbidden_terms` (unless listed in `allow_in`).
        //   3. Zero Markdown links `[...](...paths/<other-branch>/...)` may cross into a sibling branch!
        $bleedViolations = [];
        foreach ($compiledSegmentsMap as $segCheckId => $segCheck) {
            if ($segCheckId === '__root__') {
                continue;
            }
            $segForbiddenTerms = is_array($segCheck['forbidden_terms'] ?? null) ? $segCheck['forbidden_terms'] : [];
            $allowedPathIds = array_values((array)($segCheck['required_choices'] ?? []));
            $allowedPathIds[] = $segCheckId;

            foreach (($segCheck['eras'] ?? []) as $chkEra) {
                foreach (($chkEra['chapters'] ?? []) as $chkChap) {
                    foreach (($chkChap['parts'] ?? []) as $chkPart) {
                        $relFp = (string)($chkPart['file_path'] ?? '');
                        $absFp = $narrativeDir . '/' . $relFp;
                        if ($relFp === '' || !is_file($absFp)) {
                            continue;
                        }
                        $rawFileText = (string)@file_get_contents($absFp);
                        if (str_starts_with($relFp, 'paths/')) {
                            $pathSegs = explode('/', $relFp);
                            $expectedDirSlug = $pathSegs[1] ?? '';
                            if ($expectedDirSlug !== '' && !preg_match('/^\s*story_path:\s*["\']?' . preg_quote($expectedDirSlug, '/') . '["\']?\s*$/m', $rawFileText)) {
                                $bleedViolations[] = "{$seriesSlug}/{$relFp}: Missing or mismatched `story_path: \"{$expectedDirSlug}\"` in YAML frontmatter.";
                            }
                        }
                        $lines = preg_split('/\R/', $rawFileText) ?: [];
                        foreach ($lines as $lineZeroIdx => $lineStr) {
                            $lineNum = $lineZeroIdx + 1;
                            foreach ($segForbiddenTerms as $fRule) {
                                $fTermTrim = '';
                                $fAllowIn  = [];
                                $fWordBound = false;
                                if (is_string($fRule)) {
                                    $fTermTrim = trim($fRule);
                                } elseif (is_array($fRule)) {
                                    $fTermTrim = trim((string)($fRule['term'] ?? ''));
                                    $fWordBound = !empty($fRule['word_boundary']);
                                    if (is_array($fRule['allow_in'] ?? null)) {
                                        foreach ($fRule['allow_in'] as $aPath) {
                                            $fAllowIn[] = ltrim(str_replace('\\', '/', trim((string)$aPath)), '/');
                                        }
                                    }
                                }
                                if ($fTermTrim === '' || in_array($relFp, $fAllowIn, true)) {
                                    continue;
                                }
                                $matchedForbidden = $fWordBound
                                    ? (bool)preg_match('/\b' . preg_quote($fTermTrim, '/') . '\b/iu', $lineStr)
                                    : (stripos($lineStr, $fTermTrim) !== false);
                                if ($matchedForbidden) {
                                    $bleedViolations[] = "{$seriesSlug}/{$relFp}:{$lineNum} [Path '{$segCheckId}'] contains forbidden sibling-branch term '{$fTermTrim}'.";
                                }
                            }
                            if (preg_match_all('/\]\(([^)]+)\)/', $lineStr, $linkMatches)) {
                                foreach ($linkMatches[1] as $targetHref) {
                                    if (preg_match('#(?:^|/)paths/([A-Za-z0-9_-]+)/#', $targetHref, $pm)) {
                                        $linkedPathSlug = $pm[1];
                                        if (!in_array($linkedPathSlug, $allowedPathIds, true)) {
                                            $bleedViolations[] = "{$seriesSlug}/{$relFp}:{$lineNum} [Path '{$segCheckId}'] links into sibling branch 'paths/{$linkedPathSlug}/' ({$targetHref}).";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            unset($compiledSegmentsMap[$segCheckId]['forbidden_terms']);
            if (isset($compiledPathsMap[$segCheckId])) {
                unset($compiledPathsMap[$segCheckId]['forbidden_terms']);
            }
        }
        unset($compiledSegmentsMap['__root__']['forbidden_terms']);

        if (!empty($bleedViolations)) {
            fwrite(STDERR, "\n❌ [Story Crossroads Anti-Bleed Gate Failed for '{$seriesSlug}']:\n");
            foreach ($bleedViolations as $bv) {
                fwrite(STDERR, "   • {$bv}\n");
            }
            exit(1);
        }
        echo "  [Crossroads Anti-Bleed] Verified zero cross-branch bleed across " . count($compiledPathsMap) . " Story Paths.\n";

        foreach ($rawCxList as $rawCx) {
            $cxId = trim((string)($rawCx['id'] ?? ''));
            if (!isset($compiledCrossroadsById[$cxId])) {
                continue;
            }
            $cxPending = $compiledCrossroadsById[$cxId];
            $hydratedOpts = [];
            foreach ($cxPending['_option_Order'] as $oid) {
                if (!isset($compiledSegmentsMap[$oid])) {
                    continue;
                }
                $seg = $compiledSegmentsMap[$oid];
                $hydratedOpts[] = [
                    'id'               => $seg['id'],
                    'crossroads_id'    => $cxId,
                    'label'            => $seg['label'],
                    'subtitle'         => $seg['subtitle'],
                    'entry_part'       => $seg['entry_part'],
                    'entry_url'        => $seg['entry_url'],
                    'required_choices' => $seg['required_choices'],
                    'part_count'       => $seg['part_count'],
                    'word_count'       => $seg['word_count'],
                    'reading_minutes'  => $seg['reading_minutes'],
                    'image'            => $seg['image'],
                ];
            }
            if (empty($hydratedOpts)) {
                continue;
            }
            $trigRUrl = $cxPending['_trig_route_url'];
            $finalCx = [
                'id'               => $cxPending['id'],
                'trigger_part'     => $cxPending['trigger_part'],
                'trigger_url'      => $cxPending['trigger_url'],
                'kicker'           => $cxPending['kicker'],
                'title'            => $cxPending['title'],
                'prompt'           => $cxPending['prompt'],
                'required_choices' => $cxPending['required_choices'],
                'options'          => $hydratedOpts,
            ];
            $compiledCrossroadsList[] = $finalCx;
            if (isset($routeData[$trigRUrl])) {
                $routeData[$trigRUrl]['noNext'] = true;
                $routeData[$trigRUrl]['crossroads'] = $finalCx;
            }
        }
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
            if (strcasecmp($bFileInfo->getFilename(), 'BRANCH-CANON.md') === 0) {
                continue;
            }
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

    /*
     * ========================================================================
     * COMPILE MULTI-ARC STORY ARCS (`books/<slug>/arcs.json` -> `story_arcs`)
     * ========================================================================
     * Supports any number of curated Story Arc playlists per book under the
     * `"arcs": [...]` array, seamlessly interleaving narrative chapter parts
     * (`"part": "eXXX/cYYY/pZZZ.md"`) and behind-the-scenes Backstage bonus
     * dossiers (`"backstage": "books/<slug>/<dossier>"`).
     */
    $storyArcs = [];
    $storyArcSummaries = [];
    $arcsManifestPath = $narrativeDir . '/arcs.json';
    if (is_file($arcsManifestPath)) {
        $rawArcsDoc = json_decode((string)@file_get_contents($arcsManifestPath), true);
        $rawArcsList = is_array($rawArcsDoc['arcs'] ?? null) ? $rawArcsDoc['arcs'] : [];
        foreach ($rawArcsList as $rawArc) {
            $arcSlug = trim((string)($rawArc['slug'] ?? ''));
            $arcTitle = trim((string)($rawArc['title'] ?? ''));
            if ($arcSlug === '' || $arcTitle === '') {
                continue;
            }
            $arcSubtitle = trim((string)($rawArc['subtitle'] ?? ''));
            $arcDesc     = trim((string)($rawArc['description'] ?? ''));
            $rawArcImg   = trim((string)($rawArc['image'] ?? ''));
            $arcImage    = '/raggiesoft-books/images/covers/og/' . $seriesSlug . '.jpg';
            if ($rawArcImg !== '') {
                $normArcImg = preg_replace('/#.*$/', '', str_replace(['{{CDN}}', '{{cms}}', 'https://assets.raggiesoft.com'], '', $rawArcImg));
                $normArcImg = '/' . ltrim((string)$normArcImg, '/');
                if ($normArcImg !== '/') {
                    $arcImage = $normArcImg;
                }
            }

            $compiledStops = [];
            $arcPartCount = 0;
            $arcBackstageCount = 0;
            $arcWordCount = 0;
            $arcStartUrl = '';
            $lastPartArcUrl = '';
            $stopNum = 0;

            foreach (($rawArc['stops'] ?? []) as $rawStop) {
                if (!is_array($rawStop)) {
                    continue;
                }
                if (!empty($rawStop['part'])) {
                    $pRel = ltrim(str_replace('\\', '/', trim((string)$rawStop['part'])), '/');
                    if (!isset($seriesPartsByRelPath[$pRel])) {
                        fwrite(STDERR, "  [Arcs Warning] {$seriesSlug}/{$arcSlug}: Part '{$pRel}' not found in compiled TOC; skipping stop.\n");
                        continue;
                    }
                    $pInfo = $seriesPartsByRelPath[$pRel];
                    $stopNum++;
                    $arcPartCount++;
                    $arcWordCount += (int)$pInfo['word_count'];
                    $stopArcUrl = $pInfo['url'] . '?arc=' . rawurlencode($arcSlug);
                    if ($arcStartUrl === '') {
                        $arcStartUrl = $stopArcUrl;
                    }
                    $lastPartArcUrl = $stopArcUrl;
                    $compiledStops[] = [
                        'stop_num'        => $stopNum,
                        'kind'            => 'part',
                        'series_slug'     => $seriesSlug,
                        'series_title'    => $seriesTitle,
                        'file_path'       => $pInfo['file_path'],
                        'title'           => !empty($rawStop['title']) ? trim((string)$rawStop['title']) : $pInfo['part_title'],
                        'subtitle'        => !empty($rawStop['subtitle']) ? trim((string)$rawStop['subtitle']) : ($pInfo['chap_title'] . ' • ' . $pInfo['era_title']),
                        'era_title'       => $pInfo['era_title'],
                        'chap_title'      => $pInfo['chap_title'],
                        'date'            => $pInfo['date'],
                        'location'        => $pInfo['location'],
                        'excerpt'         => $pInfo['excerpt'],
                        'image'           => ($pInfo['image'] !== '') ? $pInfo['image'] : $arcImage,
                        'url'             => $pInfo['url'],
                        'arc_url'         => $stopArcUrl,
                        'word_count'      => (int)$pInfo['word_count'],
                        'reading_minutes' => (int)$pInfo['reading_minutes'],
                    ];
                } elseif (!empty($rawStop['backstage'])) {
                    $bsRel = trim(str_replace('\\', '/', trim((string)$rawStop['backstage'])), '/');
                    $bsRel = preg_replace('/\.md$/i', '', $bsRel);
                    $bsInfo = $backstageDossierIndex[$bsRel] ?? null;
                    if ($bsInfo === null) {
                        fwrite(STDERR, "  [Arcs Warning] {$seriesSlug}/{$arcSlug}: Backstage dossier '{$bsRel}' not found on disk; skipping stop.\n");
                        continue;
                    }
                    $stopNum++;
                    $arcBackstageCount++;
                    $arcWordCount += (int)$bsInfo['word_count'];
                    $compiledStops[] = [
                        'stop_num'        => $stopNum,
                        'kind'            => 'backstage',
                        'series_slug'     => $seriesSlug,
                        'series_title'    => $seriesTitle,
                        'backstage_slug'  => $bsRel,
                        'title'           => !empty($rawStop['title']) ? trim((string)$rawStop['title']) : $bsInfo['title'],
                        'subtitle'        => !empty($rawStop['subtitle']) ? trim((string)$rawStop['subtitle']) : ($bsInfo['subtitle'] !== '' ? $bsInfo['subtitle'] : 'Behind-the-Scenes Bonus Scene'),
                        'era_title'       => 'Behind the Scenes',
                        'chap_title'      => $bsInfo['category'] !== '' ? $bsInfo['category'] : 'RaggieSoft Backstage',
                        'date'            => $bsInfo['date'],
                        'location'        => $bsInfo['location'],
                        'excerpt'         => $bsInfo['summary'],
                        'image'           => ($bsInfo['image'] !== '') ? $bsInfo['image'] : $arcImage,
                        'url'             => $bsInfo['url'],
                        'arc_url'         => $lastPartArcUrl !== '' ? $lastPartArcUrl : ('/' . $seriesSlug . '?arc=' . rawurlencode($arcSlug)),
                        'word_count'      => (int)$bsInfo['word_count'],
                        'reading_minutes' => (int)$bsInfo['reading_minutes'],
                    ];
                }
            }

            if (empty($compiledStops)) {
                continue;
            }
            if ($arcStartUrl === '') {
                $arcStartUrl = '/' . $seriesSlug;
            }
            $arcReadingMinutes = max(1, (int)ceil($arcWordCount / 250));
            $arcReadingHours   = round($arcWordCount / 15000, 1);
            $backstagePlaylistSlug = $seriesSlug . '-' . $arcSlug;

            $compiledArc = [
                'slug'                    => $arcSlug,
                'series_slug'             => $seriesSlug,
                'series_title'            => $seriesTitle,
                'backstage_playlist_slug' => $backstagePlaylistSlug,
                'backstage_playlist_url'  => 'https://backstage.raggiesoft.com/arcs/' . $backstagePlaylistSlug . '/',
                'title'                   => $arcTitle,
                'subtitle'                => $arcSubtitle,
                'description'             => $arcDesc,
                'image'                   => $arcImage,
                'start_url'               => $arcStartUrl,
                'part_count'              => $arcPartCount,
                'backstage_count'         => $arcBackstageCount,
                'stop_count'              => count($compiledStops),
                'word_count'              => $arcWordCount,
                'reading_minutes'         => $arcReadingMinutes,
                'reading_hours'           => $arcReadingHours,
                'stops'                   => $compiledStops,
            ];
            $storyArcs[] = $compiledArc;
            $globalStoryArcs[] = $compiledArc;

            $arcSummary = $compiledArc;
            unset($arcSummary['stops']);
            $storyArcSummaries[] = $arcSummary;
        }
    }

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
        'illustration_count'  => $seriesIllustrationCount,
        'story_arc_count'     => count($storyArcs),
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
        $newRouteData['common']['story_arcs'] = $storyArcs;
        if (!empty($compiledCrossroadsList)) {
            $newRouteData['common']['crossroads'] = $compiledCrossroadsList;
            // Select 3-directional vs 2-directional Story Crossroads brand assets automatically
            $maxCxDirections = 2;
            foreach ($compiledCrossroadsList as $cxCheck) {
                if (count($cxCheck['options'] ?? []) >= 3) {
                    $maxCxDirections = 3;
                    break;
                }
            }
            $newRouteData['common']['navbarBrandLogo'] = "/raggiesoft-books/images/logos/story-crossroads-seal-{$maxCxDirections}way.svg";
            $newRouteData['common']['story_crossroads_logo'] = "/raggiesoft-books/images/logos/story-crossroads-logo-{$maxCxDirections}way-512.png";
            $newRouteData['common']['story_crossroads_seal'] = "/raggiesoft-books/images/logos/story-crossroads-seal-{$maxCxDirections}way.svg";
        }

        foreach ($routeData as $key => $val) {
            if ($key === 'common') continue;
            // Adjust paths for the standalone book library routing scheme
            $newKey = str_replace('/raggiesoft-books/books', '', $key);
            if (isset($val['prevUrl'])) {
                $val['prevUrl'] = str_replace('/raggiesoft-books/books', '', $val['prevUrl']);
            }
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
            'story_arcs' => $storyArcs,
            'eras' => $tocBooks
        ];
        if (!empty($compiledCrossroadsList)) {
            $generatedToc['crossroads']      = $compiledCrossroadsList;
            $generatedToc['root_segment_id'] = '__root__';
            $generatedToc['segments']        = $compiledSegmentsMap;
            $generatedToc['trunk_eras']      = $trunkEras;
            $generatedToc['paths']           = $compiledPathsMap;
        }
        $tocDestFile = $assetDestDir . '/' . $seriesSlug . '/toc.json';
        file_put_contents($tocDestFile, json_encode($generatedToc, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        $arcLogNote = count($storyArcs) > 0 ? (", " . count($storyArcs) . " story arcs") : '';
        $cxLogNote  = count($compiledCrossroadsList) > 0 ? (", " . count($compiledCrossroadsList) . " crossroads / " . count($compiledPathsMap) . " coequal paths") : '';
        echo "  [Assets] Saved auto-discovered Table of Contents (with {$seriesIllustrationCount} illustrations{$arcLogNote}{$cxLogNote}, " . number_format($seriesStoryWordCount) . " story words & eBook sizes) to toc.json\n";

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
        'story_arc_count' => count($storyArcs),
        'story_arcs' => $storyArcSummaries,
        'word_stats' => $seriesWordStats
    ];
}

// Write the master catalog file containing all series
$catalogFile = $assetDestDir . '/catalog.json';
file_put_contents($catalogFile, json_encode($masterCatalog, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
echo "\n  [Catalog] Master Catalog saved to: {$catalogFile}\n";

// --- COMPILE LIVE LIBRARY-WIDE WORD COUNT & SCALE TELEMETRY (`library-stats.json`) ---
// Sums deduplicated prose words across shared universe lore (`universal-lore/`, `character-list/`,
// `rules/`, `backstage/corporations`, `backstage/locations`), standalone band liner notes, and
// song lyrics—strictly separating `Mapped` artists (`$bookMusicArtistMap`) from `Other` bands so
// zero words are ever counted twice!
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

// Sort books largest-to-smallest by `story_word_count` (`$sb <=> $sa` reverses `<=>` for descending order!),
// breaking ties by `combined_word_count` for `https://books.raggiesoft.com/stats`.
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

// Industry trade publishing conversions:
// - `275` words ≈ 1 standard trade paperback page
// - `15,000` words ≈ 1 hour of comfortable adult reading (`250` words/minute)
// - `90,000` words ≈ 1 standard contemporary full-length novel
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

// Write the global Story Arcs (Reading Playlists) manifest for books.raggiesoft.com, Backstage, and native apps
$storyArcsPayload = [
    'generated_at' => gmdate('c'),
    'arc_count'    => count($globalStoryArcs),
    'book_count'   => count(array_unique(array_column($globalStoryArcs, 'series_slug'))),
    'arcs'         => $globalStoryArcs,
];
$storyArcsJson = json_encode($storyArcsPayload, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
$storyArcsLocalFile = $booksAppDir . '/data/story-arcs.json';
$storyArcsCdnFile   = $assetDestDir . '/../json/story-arcs.json';
file_put_contents($storyArcsLocalFile, $storyArcsJson);
if (is_dir(dirname($storyArcsCdnFile))) {
    file_put_contents($storyArcsCdnFile, $storyArcsJson);
}
echo "  [Arcs] Compiled " . count($globalStoryArcs) . " Story Arc playlists saved to: {$storyArcsLocalFile}\n";

// --- STEP B: COMPILE THE LISTENING ROOM (music.raggiesoft.com) HOVERCARD PREVIEWS ---
// WHY THIS CROSS-DOMAIN HOVERCARD INDEX EXISTS:
//   Inside novel prose (especially `books/stardust-engine` and `books/aubrie`), characters
//   write and perform songs linked to `https://music.raggiesoft.com/<artist>/<album>/<track>`.
//   When a reader hovers (or taps) a music link inside `books.raggiesoft.com`, `oliver.php`
//   looks up `music://<artist>/<album>/<track>` in `link-previews.json` to display an instant
//   Wikipedia-style preview card showing album art, release year, track number, runtime, and studio lore!
$errCatalogFile = $serverRoot . '/raggiesoft-assets/engine-room-records/catalog.json';
if (is_file($errCatalogFile)) {
    $errCatalog = json_decode((string)@file_get_contents($errCatalogFile), true) ?: [];
    $artistRollup = [];
    $liveCatalogAlbums = [];
    $liveArtistTrackUrls = [];
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

        // Register album-level preview card and mark as a live Listening Room album
        $liveCatalogAlbums["{$artistSlug}/{$albumSlug}"] = true;
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

        // Helper: Resolves the canonical clean song slug matching `buildCanonicalTrackSlug`
        // in `subdomains/music/scripts/build-catalog.js` so every cross-domain music link
        // resolves directly to `https://music.raggiesoft.com/[artist]/[album]/[track]`
        // without `?track=` query strings.
        $resolveCanonicalTrackSlug = static function (array $trackItem, string $fileName): string {
            $explicitSlug = trim((string)($trackItem['slug'] ?? ''));
            if ($explicitSlug !== '') {
                return $explicitSlug;
            }
            $cleaned = preg_replace('/\.mp3$/i', '', trim($fileName));
            $cleaned = preg_replace('/^\d+-\d+-/', '', (string)$cleaned);
            $cleaned = preg_replace('/^\d+-/', '', (string)$cleaned);
            $cleaned = strtolower(trim((string)preg_replace('/[^a-z0-9]+/i', '-', (string)$cleaned), '-'));
            return $cleaned !== '' ? $cleaned : 'track';
        };

        // Register track-level preview cards (indexed under both canonical path & legacy ?track= key)
        foreach ($tracksList as $tIdx => $trackItem) {
            $fileName = trim((string)($trackItem['fileName'] ?? ''));
            if ($fileName === '') {
                continue;
            }
            $trackSlug = $resolveCanonicalTrackSlug($trackItem, $fileName);
            $canonicalTrackUrl = "https://music.raggiesoft.com/{$artistSlug}/{$albumSlug}/{$trackSlug}";

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

            $trackPreviewCard = [
                'kind' => 'music',
                'kicker' => 'The Listening Room • ' . $artistName,
                'title' => $trackTitle,
                'date' => $albumYear !== '' ? "Released {$albumYear}" : 'Engine Room Records',
                'location' => $trackLocation,
                'image' => $albumPreviewImg,
                'excerpt' => $trackLore,
                'url' => $canonicalTrackUrl
            ];

            $allLinkPreviews["music://{$artistSlug}/{$albumSlug}/{$trackSlug}"] = $trackPreviewCard;
            $allLinkPreviews["music://{$artistSlug}/{$albumSlug}?track={$fileName}"] = $trackPreviewCard;
            if (!isset($liveArtistTrackUrls[$artistSlug][$trackSlug])) {
                $liveArtistTrackUrls[$artistSlug][$trackSlug] = $canonicalTrackUrl;
            }
        }
    }

    // Also scan any artist/album folders in `raggiesoft-assets/engine-room-records/artists/`
    // that have `album.json` / `tracks.json` so legacy `music://` hovercard keys still work,
    // while strictly skipping non-album asset folders (`images/`, `story/`, `fleet/`) and
    // resolving retired/split album folders to live Listening Room URLs so zero 404s occur.
    $artistFolders = glob($serverRoot . '/raggiesoft-assets/engine-room-records/artists/*', GLOB_ONLYDIR) ?: [];
    foreach ($artistFolders as $artistFolder) {
        $artistSlug = basename($artistFolder);
        $albumFolders = glob($artistFolder . '/*', GLOB_ONLYDIR) ?: [];
        foreach ($albumFolders as $albumFolder) {
            // Skip non-album media subfolders (e.g., `images`, `story`, `fleet`, `social-media-images`)
            if (!is_file($albumFolder . '/album.json') && !is_file($albumFolder . '/tracks.json')) {
                continue;
            }
            $albumSlug = basename($albumFolder);
            $isLiveCatalogAlbum = !empty($liveCatalogAlbums["{$artistSlug}/{$albumSlug}"]);
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

            $fallbackAlbumUrl = $isLiveCatalogAlbum
                ? "https://music.raggiesoft.com/{$artistSlug}/{$albumSlug}"
                : "https://music.raggiesoft.com/{$artistSlug}";

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
                    'url' => $fallbackAlbumUrl
                ];
            }

            foreach ($tracksList as $tIdx => $trackItem) {
                $fileName = trim((string)($trackItem['fileName'] ?? ''));
                if ($fileName === '') continue;
                $cleanedFallback = preg_replace('/\.mp3$/i', '', $fileName);
                $cleanedFallback = preg_replace('/^\d+-\d+-/', '', (string)$cleanedFallback);
                $cleanedFallback = preg_replace('/^\d+-/', '', (string)$cleanedFallback);
                $trackSlug = trim((string)($trackItem['slug'] ?? '')) ?: (strtolower(trim((string)preg_replace('/[^a-z0-9]+/i', '-', (string)$cleanedFallback), '-')) ?: 'track');
                $canonicalTrackKey = "music://{$artistSlug}/{$albumSlug}/{$trackSlug}";
                $legacyTrackKey = "music://{$artistSlug}/{$albumSlug}?track={$fileName}";
                if (isset($allLinkPreviews[$canonicalTrackKey]) && isset($allLinkPreviews[$legacyTrackKey])) continue;

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

                $fallbackTrackUrl = $isLiveCatalogAlbum
                    ? "https://music.raggiesoft.com/{$artistSlug}/{$albumSlug}/{$trackSlug}"
                    : ($liveArtistTrackUrls[$artistSlug][$trackSlug] ?? "https://music.raggiesoft.com/{$artistSlug}");

                $fallbackCard = [
                    'kind' => 'music',
                    'kicker' => 'The Listening Room • ' . $artistName,
                    'title' => $trackTitle,
                    'date' => $albumYear !== '' ? "Released {$albumYear}" : 'Engine Room Records',
                    'location' => $trackLoc,
                    'image' => $albumPreviewImg,
                    'excerpt' => $trackLore,
                    'url' => $fallbackTrackUrl
                ];
                if (!isset($allLinkPreviews[$canonicalTrackKey])) {
                    $allLinkPreviews[$canonicalTrackKey] = $fallbackCard;
                }
                if (!isset($allLinkPreviews[$legacyTrackKey])) {
                    $allLinkPreviews[$legacyTrackKey] = $fallbackCard;
                }
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

// ============================================================================
// SECTION 5: XML SITEMAPS, ROBOTS.TXT & INDEXNOW KEY COMPILER (`books.raggiesoft.com`)
// ============================================================================
// WHY WE SPLIT SITEMAPS INTO A `<sitemapindex>` + 4 CHILD XML FILES:
//   Search engines (Google, Bing, DuckDuckGo) discover URLs via `/sitemap.xml`.
//   Because Ocean View Archives contains thousands of deep manuscript Part routes,
//   splitting them into 4 clean child sitemaps (`editorial.xml`, `books.xml`,
//   `chapters.xml`, `parts.xml`) referenced by one master `<sitemapindex>` lets search
//   consoles report indexing coverage separately for marketing pages vs. deep chapters!
//   Every `<lastmod>` date is derived directly from real filesystem modification times
//   (`filemtime()`) formatted in UTC ISO-8601 (`YYYY-MM-DD`).
$booksSubdomainDir = $serverRoot . '/raggiesoft.com/subdomains/books';
if (is_dir($booksSubdomainDir)) {
    $booksOrigin = 'https://books.raggiesoft.com';
    $sitemapsDir = $booksSubdomainDir . '/sitemaps';
    if (!is_dir($sitemapsDir)) {
        // `mkdir(..., 0755, true)`: `0755` = owner rwx, world rx; `true` = create parent dirs recursively
        mkdir($sitemapsDir, 0755, true);
    }

    // Closure (`static function` = anonymous function that doesn't bind `$this`):
    // Finds the newest Unix modification timestamp (`@filemtime($p)`, where `@` suppresses warnings
    // on race-deleted files) across an array of candidate file paths and formats it in UTC (`gmdate`).
    $getLatestIsoDate = static function (array $paths, string $fallback = '2026-04-01'): string {
        $maxTs = 0;
        foreach ($paths as $p) {
            if (is_string($p) && $p !== '' && file_exists($p)) {
                $mt = @filemtime($p);
                if ($mt !== false && $mt > $maxTs) {
                    $maxTs = $mt;
                }
            }
        }
        return $maxTs > 0 ? gmdate('Y-m-d', $maxTs) : $fallback;
    };

    // Escapes `&`, `<`, `>`, `"`, and `'` (`ENT_XML1 | ENT_QUOTES`) so every URL is valid XML 1.0:
    $escapeXmlLoc = static function (string $val): string {
        return htmlspecialchars($val, ENT_XML1 | ENT_QUOTES, 'UTF-8');
    };

    // `use ($escapeXmlLoc)` imports the `$escapeXmlLoc` closure from the outer scope into this closure!
    $renderSitemapUrlSet = static function (array $entries) use ($escapeXmlLoc): string {
        $rows = [];
        foreach ($entries as $entry) {
            $rows[] = "  <url>\n    <loc>" . $escapeXmlLoc($entry['loc']) . "</loc>\n    <lastmod>" . $escapeXmlLoc($entry['lastmod']) . "</lastmod>\n  </url>";
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n" . implode("\n", $rows) . "\n</urlset>\n";
    };

    // Index `$masterCatalog` by `slug` in an associative map (`O(1)` lookup per route file):
    $booksCatalogBySlug = [];
    foreach ($masterCatalog as $catEntry) {
        if (!empty($catEntry['slug'])) {
            $booksCatalogBySlug[$catEntry['slug']] = $catEntry;
        }
    }

    // If a PHP view template inside `sophia/` is updated, pages rendered by that template
    // should reflect whichever date is newer: the Markdown manuscript OR the PHP view template!
    $oliverTplPath   = $booksSubdomainDir . '/sophia/oliver.php';
    $landingTplPath  = $booksSubdomainDir . '/sophia/landing.php';
    $tocTplPath      = $booksSubdomainDir . '/sophia/toc.php';
    $illusTplPath    = $booksSubdomainDir . '/sophia/illustrations.php';
    $eraTocTplPath   = $booksSubdomainDir . '/sophia/era-toc.php';
    $chapTocTplPath  = $booksSubdomainDir . '/sophia/chap-toc.php';

    $bookSitemapEntries    = [];
    $chapterSitemapEntries = [];
    $partSitemapEntries    = [];
    $globalLatestBookMod   = '2026-04-01';

    // Read every compiled per-book route map (`<slug>.json`) from disk so even books skipped via
    // `--book=<single-slug>` incremental builds remain 100% present in the global sitemap!
    $routeFilesOnDisk = glob($newRoutesDestDir . '/*.json') ?: [];
    sort($routeFilesOnDisk);

    foreach ($routeFilesOnDisk as $rFile) {
        $sSlug = basename($rFile, '.json');
        $catMeta = $booksCatalogBySlug[$sSlug] ?? null;
        // Skip hidden/unreleased books (`"hide": true` in `ovab.json`):
        if ($catMeta !== null && !empty($catMeta['hide'])) {
            continue;
        }
        $bookFolder = $catMeta['folder'] ?? $sSlug;
        $bookNarrDir = $narrativesRootDir . '/books/' . $bookFolder;
        if (!is_dir($bookNarrDir)) {
            continue;
        }

        $rMap = json_decode((string)@file_get_contents($rFile), true);
        if (!is_array($rMap)) {
            continue;
        }
        $sIllusCount = (int)($rMap['common']['illustration_count'] ?? ($catMeta['illustration_count'] ?? 0));

        // Track maximum content modification timestamp across this book's manuscript files
        $bookMaxMod = $getLatestIsoDate([
            $bookNarrDir . '/ovab.json',
            $bookNarrDir . '/landing.md',
            $rFile
        ]);

        // Pre-scan linear era (`e*`) & chapter (`c*`) folders on disk so each Era/Chapter TOC
        // gets the exact `<lastmod>` of the newest `p*.md` file inside that chapter/era!
        // Note: ISO-8601 `YYYY-MM-DD` strings sort chronologically with normal string `>` comparison!
        $bDirsForMod = glob($bookNarrDir . '/e*', GLOB_ONLYDIR) ?: [];
        sort($bDirsForMod);
        $eraMaxMods = [];
        $chapMaxMods = [];
        foreach ($bDirsForMod as $bIdx => $bPath) {
            $eMod = $getLatestIsoDate([$bPath . '/ovab.json'], $bookMaxMod);
            $cDirsForMod = glob($bPath . '/c*', GLOB_ONLYDIR) ?: [];
            sort($cDirsForMod);
            foreach ($cDirsForMod as $cIdx => $cPath) {
                $pFilesForMod = glob($cPath . '/p*.md') ?: [];
                $cMod = $getLatestIsoDate(array_merge([$cPath . '/ovab.json'], $pFilesForMod), $eMod);
                $chapMaxMods["{$bIdx}|{$cIdx}"] = $cMod;
                if ($cMod > $eMod) {
                    $eMod = $cMod;
                }
                if ($cMod > $bookMaxMod) {
                    $bookMaxMod = $cMod;
                }
            }
            $eraMaxMods[(string)$bIdx] = $eMod;
        }
        // Also pre-scan any Story Crossroads branching `paths/<path-id>/e*/c*` folders for accurate `<lastmod>`
        $pathDirsForMod = glob($bookNarrDir . '/paths/*', GLOB_ONLYDIR) ?: [];
        sort($pathDirsForMod);
        foreach ($pathDirsForMod as $pathDirPath) {
            $pIdKey = basename($pathDirPath);
            $pBDirs = glob($pathDirPath . '/e*', GLOB_ONLYDIR) ?: [];
            sort($pBDirs);
            foreach ($pBDirs as $pBIdx => $pBPath) {
                $peMod = $getLatestIsoDate([$pBPath . '/ovab.json', $bookNarrDir . '/crossroads.json'], $bookMaxMod);
                $pCDirs = glob($pBPath . '/c*', GLOB_ONLYDIR) ?: [];
                sort($pCDirs);
                foreach ($pCDirs as $pCIdx => $pCPath) {
                    $pPFiles = glob($pCPath . '/p*.md') ?: [];
                    $pcMod = $getLatestIsoDate(array_merge([$pCPath . '/ovab.json'], $pPFiles), $peMod);
                    $chapMaxMods["{$pIdKey}|{$pBIdx}|{$pCIdx}"] = $pcMod;
                    if ($pcMod > $peMod) {
                        $peMod = $pcMod;
                    }
                    if ($pcMod > $bookMaxMod) {
                        $bookMaxMod = $pcMod;
                    }
                }
                $eraMaxMods["{$pIdKey}|{$pBIdx}"] = $peMod;
            }
        }
        if ($bookMaxMod > $globalLatestBookMod) {
            $globalLatestBookMod = $bookMaxMod;
        }

        // Classify each route inside `<slug>.json` into the proper child sitemap bucket based on
        // Paige's virtual `filePath` sentinel tokens (`__SERIES_LANDING__`, `__TOC__`, etc.) vs. real `.md` files:
        foreach ($rMap as $routePath => $rCfg) {
            if ($routePath === 'common' || !is_string($routePath) || !str_starts_with($routePath, '/')) {
                continue;
            }
            $cleanPath = ($routePath !== '/') ? rtrim($routePath, '/') : '/';
            $fp = (string)($rCfg['filePath'] ?? '');
            if ($fp === '') {
                continue;
            }

            if ($fp === '__SERIES_LANDING__') {
                // Book overview landing page -> `books.xml`
                $tplMod = $getLatestIsoDate([$landingTplPath], $bookMaxMod);
                $bookSitemapEntries[$cleanPath] = [
                    'loc'     => $booksOrigin . $cleanPath,
                    'lastmod' => max($bookMaxMod, $tplMod)
                ];
            } elseif ($fp === '__TOC__') {
                // Full book Table of Contents -> `books.xml`
                $tplMod = $getLatestIsoDate([$tocTplPath], $bookMaxMod);
                $bookSitemapEntries[$cleanPath] = [
                    'loc'     => $booksOrigin . $cleanPath,
                    'lastmod' => max($bookMaxMod, $tplMod)
                ];
            } elseif ($fp === '__ILLUSTRATIONS__') {
                // Per-book Scene Illustrations gallery (only indexed if the book actually has >= 1 illustration!)
                if ($sIllusCount > 0) {
                    $tplMod = $getLatestIsoDate([$illusTplPath], $bookMaxMod);
                    $bookSitemapEntries[$cleanPath] = [
                        'loc'     => $booksOrigin . $cleanPath,
                        'lastmod' => max($bookMaxMod, $tplMod)
                    ];
                }
            } elseif (str_starts_with($fp, '__ERA_TOC__|')) {
                // Era/Book sub-TOC -> `chapters.xml`
                $eIdxKey = substr($fp, strlen('__ERA_TOC__|'));
                $eBaseMod = $eraMaxMods[$eIdxKey] ?? $bookMaxMod;
                $tplMod = $getLatestIsoDate([$eraTocTplPath], $eBaseMod);
                $chapterSitemapEntries[$cleanPath] = [
                    'loc'     => $booksOrigin . $cleanPath,
                    'lastmod' => max($eBaseMod, $tplMod)
                ];
            } elseif (str_starts_with($fp, '__CHAP_TOC__|')) {
                // Multi-part Chapter TOC -> `chapters.xml`
                $cIdxKey = substr($fp, strlen('__CHAP_TOC__|'));
                $cBaseMod = $chapMaxMods[$cIdxKey] ?? $bookMaxMod;
                $tplMod = $getLatestIsoDate([$chapTocTplPath], $cBaseMod);
                $chapterSitemapEntries[$cleanPath] = [
                    'loc'     => $booksOrigin . $cleanPath,
                    'lastmod' => max($cBaseMod, $tplMod)
                ];
            } else {
                // Deep Manuscript Part (`.md` file) -> `parts.xml`
                // Deduplication Guard: For single-part chapters, the canonical URL omits `/part-1-`,
                // so skip any legacy `/part-1-<slug>` alias if its canonical URL exists in `$rMap`!
                if (preg_match('#^/(.+)/part-1-([^/]+)$#', $cleanPath, $aliasMatch)) {
                    $canonicalCandidate = '/' . $aliasMatch[1] . '/' . $aliasMatch[2];
                    if (isset($rMap[$canonicalCandidate])) {
                        continue;
                    }
                }
                $partDiskPath = $bookNarrDir . '/' . ltrim($fp, '/');
                $partMod = $getLatestIsoDate([$partDiskPath, $oliverTplPath], $bookMaxMod);
                $partSitemapEntries[$cleanPath] = [
                    'loc'     => $booksOrigin . $cleanPath,
                    'lastmod' => $partMod
                ];
            }
        }
    }

    // Sort associative arrays alphabetically by URL path (`ksort` = key sort) for deterministic Git diffs:
    ksort($bookSitemapEntries);
    ksort($chapterSitemapEntries);
    ksort($partSitemapEntries);

    // Top-level editorial & library routes -> `editorial.xml`
    // (`withCatalog => true` bumps `<lastmod>` whenever ANY book in the library updates):
    $editorialRouteDefs = [
        '/'              => ['files' => [$booksSubdomainDir . '/sophia/home.php'],              'withCatalog' => true],
        '/library'       => ['files' => [$booksSubdomainDir . '/sophia/catalog.php'],           'withCatalog' => true],
        '/arcs'          => ['files' => [$booksSubdomainDir . '/sophia/story-arcs.php'],        'withCatalog' => true],
        '/illustrations' => ['files' => [$booksSubdomainDir . '/sophia/all-illustrations.php'], 'withCatalog' => true],
        '/stats'         => ['files' => [$booksSubdomainDir . '/sophia/stats.php'],             'withCatalog' => true],
        '/knox'          => ['files' => [$booksSubdomainDir . '/sophia/knox.php'],              'withCatalog' => false],
        '/aethel-saga'   => ['files' => [$booksSubdomainDir . '/sophia/aethel-saga.php'],       'withCatalog' => false],
        '/about'         => ['files' => [$booksSubdomainDir . '/sophia/about.php'],             'withCatalog' => false],
        '/accessibility' => ['files' => [$booksSubdomainDir . '/sophia/accessibility.php'],     'withCatalog' => false],
    ];
    $editorialSitemapEntries = [];
    foreach ($editorialRouteDefs as $edPath => $edCfg) {
        $fMod = $getLatestIsoDate($edCfg['files'], '2026-04-01');
        $edMod = ($edCfg['withCatalog'] && $globalLatestBookMod > $fMod) ? $globalLatestBookMod : $fMod;
        $editorialSitemapEntries[] = [
            'loc'     => $booksOrigin . ($edPath === '/' ? '/' : $edPath),
            'lastmod' => $edMod
        ];
    }

    // `array_values()` strips string keys into clean 0-indexed lists for `$renderSitemapUrlSet`:
    $childSitemapGroups = [
        'editorial.xml' => array_values($editorialSitemapEntries),
        'books.xml'     => array_values($bookSitemapEntries),
        'chapters.xml'  => array_values($chapterSitemapEntries),
        'parts.xml'     => array_values($partSitemapEntries),
    ];

    // Write each child XML sitemap (`sitemaps/*.xml`) and assemble the `<sitemapindex>` rows:
    $sitemapIndexRows = [];
    $totalIndexedBookUrls = 0;
    foreach ($childSitemapGroups as $smFileName => $smEntries) {
        file_put_contents($sitemapsDir . '/' . $smFileName, $renderSitemapUrlSet($smEntries));
        $maxGroupMod = '2026-04-01';
        foreach ($smEntries as $smItem) {
            if ($smItem['lastmod'] > $maxGroupMod) {
                $maxGroupMod = $smItem['lastmod'];
            }
        }
        $totalIndexedBookUrls += count($smEntries);
        $sitemapIndexRows[] = "  <sitemap>\n    <loc>{$booksOrigin}/sitemaps/{$smFileName}</loc>\n    <lastmod>{$maxGroupMod}</lastmod>\n  </sitemap>";
    }

    $sitemapIndexXml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n" . implode("\n", $sitemapIndexRows) . "\n</sitemapindex>\n";
    file_put_contents($booksSubdomainDir . '/sitemap.xml', $sitemapIndexXml);

    // Emit `robots.txt` welcoming crawlers to all narrative content while excluding reader-local state pages,
    // plus the static `<KEY>.txt` ownership file verified by Bing/Yandex/DuckDuckGo IndexNow pings!
    $robotsTxt = implode("\n", [
        '# Ocean View Archives — RaggieSoft Book Reader (https://books.raggiesoft.com)',
        '# Free CC BY-SA 4.0 serialized novels, scene illustrations, and lore archives by Michael P. Ragsdale.',
        'User-agent: *',
        'Allow: /',
        'Disallow: /bookmarks',
        'Disallow: /settings',
        'Disallow: /welcome',
        'Disallow: /setup',
        '',
        'Sitemap: https://books.raggiesoft.com/sitemap.xml',
        ''
    ]);
    file_put_contents($booksSubdomainDir . '/robots.txt', $robotsTxt);
    $indexNowKey = '726167676965736f6674696e6465786e';
    file_put_contents($booksSubdomainDir . '/' . $indexNowKey . '.txt', $indexNowKey);

    echo "  [Sitemap] Generated robots.txt + IndexNow key + /sitemap.xml index (" . number_format($totalIndexedBookUrls) . " canonical URLs across 4 child sitemaps)\n";
}

echo "========================================================\n";
echo "👩‍🏫 PAIGE: All done, Michael. Every book is indexed and safe on the shelves.\n";
echo "   I'm right here if you need to check anything.\n";
echo "========================================================\n";
?>


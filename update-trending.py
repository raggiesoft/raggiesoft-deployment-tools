"""
================================================================================
ARCHITECTURAL BLOCK: update-trending.py
================================================================================
PLAIN-ENGLISH OVERVIEW (100-LEVEL INTRO):
    On the Ocean View Archives Book Reader (`books.raggiesoft.com`), the home
    screen displays curated horizontal carousels defined in `discover.json`,
    including a `"Trending Now"` shelf. Rather than picking trending books by
    guesswork, this Python script asks the **Google Analytics 4 (GA4) Data API**
    which page paths had the most views over the past 7 days, sums up views per
    book slug, filters strictly against real books in `catalog.json`, updates
    `"Trending Now"` with the top 5 slugs, and—ONLY if the top-5 list actually
    changed—calls `jenna-sync.sh --push` to publish the updated `discover.json`
    to GitHub and the DigitalOcean Spaces CDN!

WHEN IT RUNS:
    Scheduled or on-demand (`python3 update-trending.py`) when
    `GOOGLE_APPLICATION_CREDENTIALS` points to a Google Cloud service-account JSON key.

INPUTS & OUTPUTS:
    - Reads: GA4 Property `389345969` (`screenPageViews` by `pagePath` over `7daysAgo..today`),
      `raggiesoft-assets/raggiesoft-books/books/catalog.json`, and `discover.json`.
    - Writes: `raggiesoft-assets/raggiesoft-books/books/discover.json` (and invokes
      `jenna-sync.sh --push` if and only if the top-5 ranking changed).
================================================================================
"""

import os
import json
import subprocess
# Official Google Analytics Data API v1beta Python SDK (`pip install google-analytics-data`)
from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import (
    DateRange,
    Dimension,
    Metric,
    RunReportRequest,
)

# GA4 numeric Property ID for RaggieSoft Book Reader
PROPERTY_ID = "389345969"
# `os.environ.get("KEY", "")` safely reads an environment variable (defaulting to `""` instead of raising `KeyError`)
CREDENTIALS_PATH = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "")
# `__file__` is Python's built-in variable holding the path to `update-trending.py` itself
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PARENT_DIR = os.path.dirname(BASE_DIR)
SERVER_ROOT = os.path.join(PARENT_DIR, "raggiesoft-servers") if os.path.isdir(os.path.join(PARENT_DIR, "raggiesoft-servers")) else PARENT_DIR
DISCOVER_JSON_PATH = os.path.join(SERVER_ROOT, "raggiesoft-assets/raggiesoft-books/books/discover.json")

def get_trending_books():
    """
    Queries GA4 for the last 7 days of pageviews, aggregates views by top-level
    book slug (`/rachel/...` -> `'rachel'`), and returns the top 5 valid slugs.
    """
    if not CREDENTIALS_PATH or not os.path.exists(CREDENTIALS_PATH):
        print(f"Error: Credentials not found at {CREDENTIALS_PATH}")
        return None

    # `BetaAnalyticsDataClient()` automatically authenticates using `GOOGLE_APPLICATION_CREDENTIALS`
    client = BetaAnalyticsDataClient()
    request = RunReportRequest(
        property=f"properties/{PROPERTY_ID}",
        dimensions=[Dimension(name="pagePath")],
        metrics=[Metric(name="screenPageViews")],
        date_ranges=[DateRange(start_date="7daysAgo", end_date="today")],
    )

    try:
        response = client.run_report(request)
    except Exception as e:
        print(f"Error querying GA4 API: {e}")
        return None

    # Dictionary mapping `book_slug -> total_views_integer`
    book_views = {}
    
    # Load valid book slugs from `catalog.json` into a Python `set` (`O(1)` hash-table lookup!)
    # so non-book routes like `/about`, `/arcs`, `/library`, or bot junk paths are ignored.
    catalog_path = os.path.join(SERVER_ROOT, "raggiesoft-assets/raggiesoft-books/books/catalog.json")
    valid_slugs = set()
    try:
        with open(catalog_path, 'r') as f:
            catalog_data = json.load(f)
            for book in catalog_data:
                valid_slugs.add(book.get("slug"))
    except Exception as e:
        print(f"Error loading catalog.json: {e}")
        return None

    # Aggregate views across every chapter/part URL belonging to the same book slug
    for row in response.rows:
        path = row.dimension_values[0].value
        views = int(row.metric_values[0].value)
        
        # List comprehension `[p for p in path.split('/') if p]` splits `"/katie/era-1/chap-1"`
        # and drops empty strings caused by leading/trailing slashes -> `['katie', 'era-1', 'chap-1']`.
        parts = [p for p in path.split('/') if p]
        if parts:
            slug = parts[0]
            # Strictly filter against valid `catalog.json` slugs; `.get(slug, 0)` starts new keys at 0
            if slug in valid_slugs:
                book_views[slug] = book_views.get(slug, 0) + views

    # Sort `(slug, views)` tuples by `item[1]` (the view count) from highest to lowest (`reverse=True`)
    sorted_books = sorted(book_views.items(), key=lambda item: item[1], reverse=True)
    
    # Slice `[:5]` to take at most the top 5 books and extract just their slug strings
    return [slug for slug, views in sorted_books[:5]]

def update_discover_json(trending_slugs):
    """
    Rewrites `discover.json` ONLY if the `'Trending Now'` list actually changed
    (an "idempotent" check that avoids noisy no-op Git commits and CDN uploads).
    """
    if not trending_slugs:
        print("No trending books found. Skipping update.")
        return False

    with open(DISCOVER_JSON_PATH, 'r') as f:
        discover_data = json.load(f)

    # Walk the carousel objects until we find `"title": "Trending Now"`
    updated = False
    for carousel in discover_data:
        if carousel.get("title") == "Trending Now":
            # Python compares two lists element-by-element (`!=` checks both order and contents!)
            if carousel.get("books") != trending_slugs:
                carousel["books"] = trending_slugs
                updated = True
            break
    
    if updated:
        with open(DISCOVER_JSON_PATH, 'w') as f:
            json.dump(discover_data, f, indent=4)
        print(f"Updated discover.json with trending books: {trending_slugs}")
        return True
    else:
        print("Trending books haven't changed. No update needed.")
        return False

def push_changes():
    """
    Delegates deployment to `jenna-sync.sh --push` via `subprocess.run` (passing an
    argument list `[script_path, ...]` rather than `shell=True` to prevent shell injection).
    """
    print("Pushing changes to CDN via jenna-sync.sh...")
    workspace_dir = os.path.dirname(__file__)
    script_path = os.path.join(workspace_dir, "jenna-sync.sh")
    
    try:
        # `check=True` raises `CalledProcessError` if `jenna-sync.sh` returns a non-zero exit code
        result = subprocess.run([script_path, "--push", "-m", "Auto-update trending books via GA4 API"], cwd=workspace_dir, check=True, text=True, capture_output=True)
        print(result.stdout)
        print("Push successful!")
    except subprocess.CalledProcessError as e:
        print(f"Push failed: {e}")
        print(e.stderr)

# Standard Python entrypoint guard: runs ONLY when executed directly (`python3 update-trending.py`),
# NOT if another Python module imports helper functions from this file.
if __name__ == "__main__":
    print("Fetching trending books from GA4...")
    trending_slugs = get_trending_books()
    
    if trending_slugs is not None:
        if update_discover_json(trending_slugs):
            push_changes()

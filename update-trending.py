import os
import json
import subprocess
from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import (
    DateRange,
    Dimension,
    Metric,
    RunReportRequest,
)

PROPERTY_ID = "389345969"
CREDENTIALS_PATH = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "")
DISCOVER_JSON_PATH = os.path.join(os.path.dirname(__file__), "../raggiesoft-assets/raggiesoft-books/books/discover.json")

def get_trending_books():
    if not CREDENTIALS_PATH or not os.path.exists(CREDENTIALS_PATH):
        print(f"Error: Credentials not found at {CREDENTIALS_PATH}")
        return None

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

    book_views = {}
    
    # Load valid book slugs from catalog.json
    catalog_path = os.path.join(os.path.dirname(__file__), "../raggiesoft-assets/raggiesoft-books/books/catalog.json")
    valid_slugs = set()
    try:
        with open(catalog_path, 'r') as f:
            catalog_data = json.load(f)
            for book in catalog_data:
                valid_slugs.add(book.get("slug"))
    except Exception as e:
        print(f"Error loading catalog.json: {e}")
        return None

    for row in response.rows:
        path = row.dimension_values[0].value
        views = int(row.metric_values[0].value)
        
        # Extract book slug from path, assuming format /slug/chapter-1 or /slug
        parts = [p for p in path.split('/') if p]
        if parts:
            slug = parts[0]
            # Strictly filter against valid catalog.json slugs
            if slug in valid_slugs:
                book_views[slug] = book_views.get(slug, 0) + views

    # Sort books by views in descending order
    sorted_books = sorted(book_views.items(), key=lambda item: item[1], reverse=True)
    
    # Return top 5 trending slugs
    return [slug for slug, views in sorted_books[:5]]

def update_discover_json(trending_slugs):
    if not trending_slugs:
        print("No trending books found. Skipping update.")
        return False

    with open(DISCOVER_JSON_PATH, 'r') as f:
        discover_data = json.load(f)

    # Find and update the 'Trending Now' carousel
    updated = False
    for carousel in discover_data:
        if carousel.get("title") == "Trending Now":
            # Only update if there's a change to avoid unnecessary deployment
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
    print("Pushing changes to CDN via jenna-sync.sh...")
    workspace_dir = os.path.dirname(__file__)
    script_path = os.path.join(workspace_dir, "jenna-sync.sh")
    
    try:
        result = subprocess.run([script_path, "--push", "-m", "Auto-update trending books via GA4 API"], cwd=workspace_dir, check=True, text=True, capture_output=True)
        print(result.stdout)
        print("Push successful!")
    except subprocess.CalledProcessError as e:
        print(f"Push failed: {e}")
        print(e.stderr)

if __name__ == "__main__":
    print("Fetching trending books from GA4...")
    trending_slugs = get_trending_books()
    
    if trending_slugs is not None:
        if update_discover_json(trending_slugs):
            push_changes()

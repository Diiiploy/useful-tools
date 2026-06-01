#!/usr/bin/env python3
"""wallpaper-scraper.py - Download trending ultrawide wallpapers from multiple sources.

Sources (no API key required):
    - Wallhaven (primary)  — server-side ultrawide filtering, toplist sorting
    - Reddit (secondary)   — community curated from r/widescreenwallpaper, r/wallpaper, etc.

Sources (optional, API key needed):
    - Unsplash  — high quality photography
    - Pixabay   — server-side resolution filtering

Setup:
    pip install requests Pillow

    # Optional API keys via env vars or ~/.config/wallpaper-scraper/config.json:
    export UNSPLASH_ACCESS_KEY="your_key"
    export PIXABAY_API_KEY="your_key"
    export WALLHAVEN_API_KEY="your_key"   # optional, only needed for NSFW

Usage:
    python3 wallpaper-scraper.py                          # All default categories
    python3 wallpaper-scraper.py -c cyberpunk neon space  # Specific categories only
    python3 wallpaper-scraper.py --max-per-category 5     # More per category
    python3 wallpaper-scraper.py --max-total 50           # Cap total downloads
    python3 wallpaper-scraper.py --dry-run                # Preview without downloading
    python3 wallpaper-scraper.py --install-cron            # Set up weekly cron job
    python3 wallpaper-scraper.py --list-categories         # Show available categories
"""

import argparse
import hashlib
import json
import logging
import os
import random
import re
import string
import subprocess
import sys
import tempfile
import time
from io import BytesIO
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode

import requests
from PIL import Image

# ─── Directories & Constants ────────────────────────────────────────────────

WALLS_DIR = Path.home() / "Pictures" / "Walls"
PORTRAIT_DIR = WALLS_DIR / "portrait_walls"
CONFIG_DIR = Path.home() / ".config" / "wallpaper-scraper"
STATE_FILE = CONFIG_DIR / "state.json"
CONFIG_FILE = CONFIG_DIR / "config.json"

MIN_WIDTH = 2560
MIN_HEIGHT = 1080
DEFAULT_MAX_PER_CATEGORY = 3
DEFAULT_MAX_TOTAL = 100

USER_AGENT = "WallpaperScraper/1.0 (Linux; ultrawide-collector)"

# ─── Categories ──────────────────────────────────────────────────────────────
# Format: "file_prefix": ["search term 1", "search term 2", ...]
# file_prefix = used in filename: {prefix}_{NN}_{id}.{ext}
# search terms = sent to source APIs
#
# Edit this dict to add/remove/modify categories.

CATEGORIES = {
    "cyberpunk": ["cyberpunk", "cyberpunk city neon"],
    "retrofuturistic": ["retro futuristic", "retrofuturism synthwave"],
    "nature": ["nature landscape scenic", "nature panoramic wide"],
    "forest": ["forest landscape", "deep forest misty"],
    "mountain": ["mountain landscape", "mountain peak snow"],
    "nightcity": ["night city lights", "city at night urban"],
    "skyline": ["city skyline panoramic", "urban skyline sunset"],
    "tokyo": ["Tokyo city night", "Tokyo street neon"],
    "japan": ["Japan landscape temple", "Japanese scenery photography"],
    "architecture": ["unique architecture modern", "futuristic building design"],
    "space": ["space nebula galaxy", "deep space cosmos stars"],
    "astral": ["astrophotography milky way", "star trail night sky"],
    "neon": ["neon city lights urban", "neon aesthetic glow"],
    "autumn": ["autumn landscape fall", "fall colors forest golden"],
    "nasa": ["NASA space photography", "NASA earth satellite"],
    "spacex": ["SpaceX rocket launch", "SpaceX starship"],
    "robotics": ["humanoid robot futuristic", "robotics android"],
    "gaming": ["gaming aesthetic setup", "gaming RGB neon"],
    "retrogaming": ["retro gaming arcade", "pixel art retro game"],
    "hacking": ["hacking aesthetic matrix", "hacker terminal code"],
    "mrrobot": ["mr robot fsociety", "mr robot aesthetic glitch"],
    "rainforest": ["rainforest tropical lush", "jungle rainforest canopy"],
    "animal": ["wildlife photography stunning", "animal nature portrait"],
}

# Reddit subreddits mapped to categories for targeted searching
SUBREDDIT_MAP = {
    "nature": ["EarthPorn", "wallpaper"],
    "forest": ["EarthPorn", "wallpaper"],
    "mountain": ["EarthPorn", "wallpaper"],
    "space": ["spaceporn", "wallpaper"],
    "astral": ["astrophotography", "spaceporn"],
    "tokyo": ["CityPorn", "japanpics"],
    "japan": ["japanpics", "wallpaper"],
    "skyline": ["CityPorn", "wallpaper"],
    "nightcity": ["CityPorn", "wallpaper"],
    "autumn": ["EarthPorn", "AutumnPorn"],
    "rainforest": ["EarthPorn", "wallpaper"],
    "animal": ["wildlifephotography", "NatureIsFuckingLit"],
    "nasa": ["spaceporn", "wallpaper"],
    "spacex": ["spaceporn", "SpaceXLounge"],
}

# ─── Logging Setup ───────────────────────────────────────────────────────────

log = logging.getLogger("wallpaper-scraper")


# ─── Helpers ─────────────────────────────────────────────────────────────────

def generate_id(length: int = 6) -> str:
    """Generate a random alphanumeric ID matching existing naming scheme."""
    chars = string.ascii_lowercase + string.digits
    return "".join(random.choice(chars) for _ in range(length))


def get_next_number(directory: Path, category: str) -> int:
    """Scan directory for highest existing number in a category and return next."""
    pattern = re.compile(rf"^{re.escape(category)}_(\d+)_\w+\.\w+$")
    highest = 0
    if directory.exists():
        for f in directory.iterdir():
            m = pattern.match(f.name)
            if m:
                highest = max(highest, int(m.group(1)))
    return highest + 1


def is_portrait(width: int, height: int) -> bool:
    """Determine if image is portrait orientation."""
    return height > width


def meets_resolution(width: int, height: int) -> bool:
    """Check if image meets minimum resolution requirements."""
    return width >= MIN_WIDTH and height >= MIN_HEIGHT


def is_ultrawide_friendly(width: int, height: int) -> bool:
    """Check if aspect ratio is reasonable for ultrawide (>= 16:9 = 1.78).
    Allows standard widescreen and ultrawide. Rejects square and tall images
    for the landscape directory. Portrait images are handled separately."""
    if height == 0:
        return False
    ratio = width / height
    return ratio >= 1.5  # At least 3:2, ideally 16:9+ or 21:9


def content_hash(data: bytes) -> str:
    """SHA-256 hash of image content for deduplication."""
    return hashlib.sha256(data).hexdigest()


def safe_request(url: str, headers: Optional[dict] = None, timeout: int = 30,
                 max_retries: int = 2) -> Optional[requests.Response]:
    """Make HTTP request with retries and error handling."""
    if headers is None:
        headers = {"User-Agent": USER_AGENT}
    elif "User-Agent" not in headers:
        headers["User-Agent"] = USER_AGENT

    for attempt in range(max_retries + 1):
        try:
            resp = requests.get(url, headers=headers, timeout=timeout)
            if resp.status_code == 429:
                wait = min(2 ** attempt * 5, 60)
                log.warning("Rate limited on %s, waiting %ds...", url[:80], wait)
                time.sleep(wait)
                continue
            resp.raise_for_status()
            return resp
        except requests.exceptions.RequestException as e:
            if attempt < max_retries:
                wait = 2 ** attempt
                log.warning("Request failed (%s), retry %d in %ds...", e, attempt + 1, wait)
                time.sleep(wait)
            else:
                log.error("Request failed permanently: %s — %s", url[:80], e)
    return None


# ─── State Manager ───────────────────────────────────────────────────────────

class StateManager:
    """Track downloaded URLs and content hashes to prevent duplicates."""

    def __init__(self, state_file: Path = STATE_FILE):
        self.state_file = state_file
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state = self._load()

    def _load(self) -> dict:
        if self.state_file.exists():
            try:
                return json.loads(self.state_file.read_text())
            except (json.JSONDecodeError, OSError):
                log.warning("Corrupt state file, starting fresh")
        return {"downloaded_urls": [], "downloaded_hashes": [], "last_run": None}

    def save(self):
        self.state["last_run"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        self.state_file.write_text(json.dumps(self.state, indent=2))

    def is_url_known(self, url: str) -> bool:
        return url in self.state["downloaded_urls"]

    def is_hash_known(self, h: str) -> bool:
        return h in self.state["downloaded_hashes"]

    def record(self, url: str, h: str):
        if url not in self.state["downloaded_urls"]:
            self.state["downloaded_urls"].append(url)
        if h not in self.state["downloaded_hashes"]:
            self.state["downloaded_hashes"].append(h)


# ─── Source: Wallhaven ───────────────────────────────────────────────────────

class WallhavenSource:
    """Wallhaven.cc API — best ultrawide support with server-side filtering."""

    BASE_URL = "https://wallhaven.cc/api/v1"
    RATE_DELAY = 1.5  # seconds between requests (45 req/min limit)

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key
        self.last_request = 0

    def _throttle(self):
        elapsed = time.time() - self.last_request
        if elapsed < self.RATE_DELAY:
            time.sleep(self.RATE_DELAY - elapsed)
        self.last_request = time.time()

    def search(self, query: str, page: int = 1) -> list[dict]:
        """Search Wallhaven for ultrawide wallpapers matching query."""
        self._throttle()
        params = {
            "q": query,
            "categories": "111",        # general + anime + people
            "purity": "100",            # SFW only
            "atleast": f"{MIN_WIDTH}x{MIN_HEIGHT}",
            "ratios": "21x9",
            "sorting": "toplist",
            "topRange": "1M",           # top of the month
            "order": "desc",
            "page": page,
        }
        if self.api_key:
            params["apikey"] = self.api_key

        resp = safe_request(
            f"{self.BASE_URL}/search?{urlencode(params)}"
        )
        if resp is None:
            return []

        try:
            data = resp.json()
        except (json.JSONDecodeError, ValueError):
            return []

        results = []
        for item in data.get("data", []):
            w, h = item.get("resolution", "0x0").split("x")
            results.append({
                "url": item.get("path", ""),
                "width": int(w),
                "height": int(h),
                "source": "wallhaven",
                "source_id": item.get("id", ""),
            })
        return results


# ─── Source: Reddit ──────────────────────────────────────────────────────────

class RedditSource:
    """Reddit JSON API — community curated wallpapers, no auth required."""

    RATE_DELAY = 2.0  # seconds between requests
    MIN_SCORE = 50    # minimum upvotes for quality filtering

    def __init__(self):
        self.last_request = 0

    def _throttle(self):
        elapsed = time.time() - self.last_request
        if elapsed < self.RATE_DELAY:
            time.sleep(self.RATE_DELAY - elapsed)
        self.last_request = time.time()

    def search(self, query: str, subreddits: Optional[list[str]] = None) -> list[dict]:
        """Search Reddit for wallpaper posts matching query."""
        if subreddits is None:
            subreddits = ["widescreenwallpaper", "wallpaper"]

        results = []
        for sub in subreddits:
            self._throttle()
            url = (
                f"https://www.reddit.com/r/{sub}/search.json"
                f"?q={requests.utils.quote(query)}"
                f"&restrict_sr=1&sort=top&t=month&limit=25"
            )
            resp = safe_request(url, headers={"User-Agent": USER_AGENT})
            if resp is None:
                continue

            try:
                data = resp.json()
            except (json.JSONDecodeError, ValueError):
                continue

            for post in data.get("data", {}).get("children", []):
                d = post.get("data", {})
                score = d.get("score", 0)
                if score < self.MIN_SCORE:
                    continue

                img_url = d.get("url", "")

                # Direct image links
                if any(img_url.lower().endswith(ext) for ext in (".jpg", ".jpeg", ".png")):
                    # Try to get dimensions from preview
                    w, h = 0, 0
                    preview = d.get("preview", {})
                    if preview:
                        images = preview.get("images", [{}])
                        if images:
                            source = images[0].get("source", {})
                            w = source.get("width", 0)
                            h = source.get("height", 0)

                    results.append({
                        "url": img_url,
                        "width": w,
                        "height": h,
                        "source": "reddit",
                        "source_id": d.get("id", ""),
                        "score": score,
                    })

                # Reddit gallery posts
                elif "gallery_data" in d and "media_metadata" in d:
                    for item in d["gallery_data"].get("items", []):
                        media_id = item.get("media_id", "")
                        meta = d["media_metadata"].get(media_id, {})
                        if meta.get("status") != "valid":
                            continue
                        # Get best resolution
                        s = meta.get("s", {})
                        gallery_url = s.get("u", "").replace("&amp;", "&")
                        if not gallery_url:
                            # Fallback to direct redd.it URL
                            ext = meta.get("m", "image/jpeg").split("/")[-1]
                            gallery_url = f"https://i.redd.it/{media_id}.{ext}"
                        results.append({
                            "url": gallery_url,
                            "width": s.get("x", 0),
                            "height": s.get("y", 0),
                            "source": "reddit",
                            "source_id": media_id,
                            "score": score,
                        })

        # Sort by score descending for quality
        results.sort(key=lambda x: x.get("score", 0), reverse=True)
        return results

    def trending(self, subreddits: Optional[list[str]] = None) -> list[dict]:
        """Get top/hot posts from wallpaper subreddits without keyword search."""
        if subreddits is None:
            subreddits = ["widescreenwallpaper"]

        results = []
        for sub in subreddits:
            self._throttle()
            url = f"https://www.reddit.com/r/{sub}/top.json?t=week&limit=50"
            resp = safe_request(url, headers={"User-Agent": USER_AGENT})
            if resp is None:
                continue

            try:
                data = resp.json()
            except (json.JSONDecodeError, ValueError):
                continue

            for post in data.get("data", {}).get("children", []):
                d = post.get("data", {})
                score = d.get("score", 0)
                if score < self.MIN_SCORE:
                    continue

                img_url = d.get("url", "")
                if any(img_url.lower().endswith(ext) for ext in (".jpg", ".jpeg", ".png")):
                    w, h = 0, 0
                    preview = d.get("preview", {})
                    if preview:
                        images = preview.get("images", [{}])
                        if images:
                            source = images[0].get("source", {})
                            w = source.get("width", 0)
                            h = source.get("height", 0)

                    results.append({
                        "url": img_url,
                        "width": w,
                        "height": h,
                        "source": "reddit",
                        "source_id": d.get("id", ""),
                        "score": score,
                    })

        results.sort(key=lambda x: x.get("score", 0), reverse=True)
        return results


# ─── Source: Unsplash (optional) ─────────────────────────────────────────────

class UnsplashSource:
    """Unsplash API — high quality photography. Requires API key."""

    BASE_URL = "https://api.unsplash.com"
    RATE_DELAY = 1.5

    def __init__(self, access_key: str):
        self.access_key = access_key
        self.last_request = 0

    def _throttle(self):
        elapsed = time.time() - self.last_request
        if elapsed < self.RATE_DELAY:
            time.sleep(self.RATE_DELAY - elapsed)
        self.last_request = time.time()

    def search(self, query: str, page: int = 1, per_page: int = 30) -> list[dict]:
        """Search Unsplash for landscape photos matching query."""
        self._throttle()
        resp = safe_request(
            f"{self.BASE_URL}/search/photos"
            f"?query={requests.utils.quote(query)}"
            f"&orientation=landscape&order_by=relevant"
            f"&per_page={per_page}&page={page}",
            headers={
                "Authorization": f"Client-ID {self.access_key}",
                "User-Agent": USER_AGENT,
            },
        )
        if resp is None:
            return []

        try:
            data = resp.json()
        except (json.JSONDecodeError, ValueError):
            return []

        results = []
        for photo in data.get("results", []):
            w = photo.get("width", 0)
            h = photo.get("height", 0)
            if not meets_resolution(w, h):
                continue
            # Use raw URL with width param for best quality
            raw_url = photo.get("urls", {}).get("raw", "")
            if raw_url:
                # Request at original resolution
                dl_url = raw_url + "&q=85&fm=jpg"
            else:
                dl_url = photo.get("urls", {}).get("full", "")

            results.append({
                "url": dl_url,
                "width": w,
                "height": h,
                "source": "unsplash",
                "source_id": photo.get("id", ""),
            })
        return results


# ─── Source: Pixabay (optional) ──────────────────────────────────────────────

class PixabaySource:
    """Pixabay API — server-side resolution filtering. Requires API key."""

    BASE_URL = "https://pixabay.com/api/"
    RATE_DELAY = 0.7

    def __init__(self, api_key: str):
        self.api_key = api_key
        self.last_request = 0

    def _throttle(self):
        elapsed = time.time() - self.last_request
        if elapsed < self.RATE_DELAY:
            time.sleep(self.RATE_DELAY - elapsed)
        self.last_request = time.time()

    def search(self, query: str, page: int = 1, per_page: int = 50) -> list[dict]:
        """Search Pixabay for landscape photos with minimum resolution."""
        self._throttle()
        resp = safe_request(
            f"{self.BASE_URL}"
            f"?key={self.api_key}"
            f"&q={requests.utils.quote(query)}"
            f"&image_type=photo&orientation=horizontal"
            f"&min_width={MIN_WIDTH}&min_height={MIN_HEIGHT}"
            f"&order=popular&safesearch=true"
            f"&per_page={per_page}&page={page}",
        )
        if resp is None:
            return []

        try:
            data = resp.json()
        except (json.JSONDecodeError, ValueError):
            return []

        results = []
        for hit in data.get("hits", []):
            results.append({
                "url": hit.get("largeImageURL", ""),
                "width": hit.get("imageWidth", 0),
                "height": hit.get("imageHeight", 0),
                "source": "pixabay",
                "source_id": str(hit.get("id", "")),
            })
        return results


# ─── Wallpaper Downloader (Orchestrator) ─────────────────────────────────────

class WallpaperDownloader:
    """Orchestrates searching, filtering, downloading, and naming wallpapers."""

    def __init__(self, categories: dict, max_per_category: int = DEFAULT_MAX_PER_CATEGORY,
                 max_total: int = DEFAULT_MAX_TOTAL, dry_run: bool = False):
        self.categories = categories
        self.max_per_category = max_per_category
        self.max_total = max_total
        self.dry_run = dry_run
        self.state = StateManager()
        self.total_downloaded = 0
        self.stats = {"downloaded": 0, "skipped_dup": 0, "skipped_res": 0, "errors": 0}

        # Initialize sources
        self.sources = []
        self._init_sources()

        # Ensure directories exist
        WALLS_DIR.mkdir(parents=True, exist_ok=True)
        PORTRAIT_DIR.mkdir(parents=True, exist_ok=True)

    def _init_sources(self):
        """Initialize available sources based on configured API keys."""
        # Wallhaven — always available (no key required for SFW)
        wh_key = self._get_key("WALLHAVEN_API_KEY")
        self.sources.append(("wallhaven", WallhavenSource(api_key=wh_key)))
        log.info("Source enabled: Wallhaven%s", " (with API key)" if wh_key else "")

        # Reddit — always available (no auth needed)
        self.sources.append(("reddit", RedditSource()))
        log.info("Source enabled: Reddit")

        # Unsplash — optional
        unsplash_key = self._get_key("UNSPLASH_ACCESS_KEY")
        if unsplash_key:
            self.sources.append(("unsplash", UnsplashSource(unsplash_key)))
            log.info("Source enabled: Unsplash")

        # Pixabay — optional
        pixabay_key = self._get_key("PIXABAY_API_KEY")
        if pixabay_key:
            self.sources.append(("pixabay", PixabaySource(pixabay_key)))
            log.info("Source enabled: Pixabay")

        if not self.sources:
            log.error("No sources available!")
            sys.exit(1)

    def _get_key(self, env_name: str) -> Optional[str]:
        """Get API key from environment variable or config file."""
        # Check env first
        val = os.environ.get(env_name)
        if val:
            return val
        # Check config file
        if CONFIG_FILE.exists():
            try:
                cfg = json.loads(CONFIG_FILE.read_text())
                return cfg.get(env_name)
            except (json.JSONDecodeError, OSError):
                pass
        return None

    def run(self):
        """Main download loop — iterate categories and sources."""
        log.info("=" * 60)
        log.info("Wallpaper Scraper starting — %d categories, max %d/cat, max %d total",
                 len(self.categories), self.max_per_category, self.max_total)
        log.info("Sources: %s", ", ".join(name for name, _ in self.sources))
        log.info("Output: %s", WALLS_DIR)
        log.info("=" * 60)

        for cat_name, search_terms in self.categories.items():
            if self.total_downloaded >= self.max_total:
                log.info("Reached max total (%d), stopping", self.max_total)
                break

            cat_downloaded = 0
            log.info("\n--- Category: %s ---", cat_name)

            # Collect candidates from all sources
            candidates = []
            for source_name, source in self.sources:
                for term in search_terms:
                    if source_name == "wallhaven":
                        candidates.extend(source.search(term))
                    elif source_name == "reddit":
                        subs = SUBREDDIT_MAP.get(cat_name, ["widescreenwallpaper", "wallpaper"])
                        candidates.extend(source.search(term, subreddits=subs))
                    elif source_name == "unsplash":
                        candidates.extend(source.search(term))
                    elif source_name == "pixabay":
                        candidates.extend(source.search(term))

            log.info("  Found %d candidates from all sources", len(candidates))

            # Deduplicate candidates by URL
            seen_urls = set()
            unique_candidates = []
            for c in candidates:
                if c["url"] and c["url"] not in seen_urls:
                    seen_urls.add(c["url"])
                    unique_candidates.append(c)
            candidates = unique_candidates

            for candidate in candidates:
                if cat_downloaded >= self.max_per_category:
                    break
                if self.total_downloaded >= self.max_total:
                    break

                url = candidate["url"]
                if not url:
                    continue

                # Skip already downloaded
                if self.state.is_url_known(url):
                    self.stats["skipped_dup"] += 1
                    continue

                # Pre-filter by known dimensions (if available from API)
                w, h = candidate.get("width", 0), candidate.get("height", 0)
                if w > 0 and h > 0 and not meets_resolution(w, h):
                    self.stats["skipped_res"] += 1
                    continue

                if self.dry_run:
                    log.info("  [DRY RUN] Would download: %s (%dx%d) from %s",
                             url[:80], w, h, candidate.get("source", "?"))
                    cat_downloaded += 1
                    self.total_downloaded += 1
                    continue

                # Download and validate
                result = self._download_and_save(url, cat_name, candidate)
                if result:
                    cat_downloaded += 1
                    self.total_downloaded += 1

            log.info("  Category %s: downloaded %d wallpapers", cat_name, cat_downloaded)

        # Save state
        if not self.dry_run:
            self.state.save()

        # Summary
        log.info("\n" + "=" * 60)
        log.info("SUMMARY")
        log.info("  Downloaded: %d", self.stats["downloaded"])
        log.info("  Skipped (duplicate): %d", self.stats["skipped_dup"])
        log.info("  Skipped (resolution): %d", self.stats["skipped_res"])
        log.info("  Errors: %d", self.stats["errors"])
        log.info("=" * 60)

    def _download_and_save(self, url: str, category: str, meta: dict) -> bool:
        """Download image, validate dimensions, save with correct naming."""
        try:
            resp = safe_request(url, timeout=60)
            if resp is None:
                self.stats["errors"] += 1
                return False

            img_data = resp.content
            if len(img_data) < 10000:  # Suspiciously small
                log.warning("  Skipping tiny file (%d bytes): %s", len(img_data), url[:80])
                self.stats["errors"] += 1
                return False

            # Check content hash for deduplication
            h = content_hash(img_data)
            if self.state.is_hash_known(h):
                log.debug("  Skipping duplicate content (hash match): %s", url[:60])
                self.stats["skipped_dup"] += 1
                return False

            # Validate image and get actual dimensions
            try:
                img = Image.open(BytesIO(img_data))
                w, h_px = img.size
            except Exception as e:
                log.warning("  Invalid image from %s: %s", url[:60], e)
                self.stats["errors"] += 1
                return False

            # Resolution check
            if not meets_resolution(w, h_px):
                log.debug("  Below minimum resolution (%dx%d): %s", w, h_px, url[:60])
                self.stats["skipped_res"] += 1
                return False

            # Determine orientation and target directory
            portrait = is_portrait(w, h_px)
            if portrait:
                target_dir = PORTRAIT_DIR
            elif not is_ultrawide_friendly(w, h_px):
                # Skip square/near-square images for landscape — not useful on ultrawide
                log.debug("  Skipping non-widescreen aspect (%dx%d, ratio %.2f): %s",
                          w, h_px, w / h_px if h_px else 0, url[:60])
                self.stats["skipped_res"] += 1
                return False
            else:
                target_dir = WALLS_DIR

            # Determine file extension from content type or URL
            fmt = img.format
            if fmt:
                ext = fmt.lower()
                if ext == "jpeg":
                    ext = "jpg"
            else:
                # Fallback to URL extension
                ext = Path(url.split("?")[0]).suffix.lstrip(".").lower()
                if ext not in ("jpg", "jpeg", "png", "webp"):
                    ext = "jpg"
                if ext == "jpeg":
                    ext = "jpg"

            # Generate filename
            next_num = get_next_number(target_dir, category)
            uid = generate_id(6)
            filename = f"{category}_{next_num:02d}_{uid}.{ext}"
            target_path = target_dir / filename

            # Atomic write: temp file then move
            fd, tmp_path = tempfile.mkstemp(suffix=f".{ext}", dir=str(target_dir))
            try:
                with os.fdopen(fd, "wb") as f:
                    f.write(img_data)
                os.rename(tmp_path, str(target_path))
            except Exception:
                # Clean up temp file on failure
                if os.path.exists(tmp_path):
                    os.unlink(tmp_path)
                raise

            # Record in state
            self.state.record(url, h)

            orient_label = "portrait" if portrait else "landscape"
            log.info("  ✓ %s (%dx%d, %s, %s) → %s",
                     filename, w, h_px, orient_label, meta.get("source", "?"), target_dir.name)
            self.stats["downloaded"] += 1
            return True

        except Exception as e:
            log.error("  ✗ Failed to download %s: %s", url[:60], e)
            self.stats["errors"] += 1
            return False


# ─── Cron Installation ───────────────────────────────────────────────────────

def install_cron():
    """Add weekly cron job to run wallpaper scraper every Sunday at 3 AM."""
    script_path = Path(__file__).resolve()
    log_path = CONFIG_DIR / "cron.log"
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)

    cron_line = (
        f"0 3 * * 0 /usr/bin/python3 {script_path} --quiet "
        f">> {log_path} 2>&1"
    )

    # Check if already installed
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
        existing = result.stdout if result.returncode == 0 else ""
    except FileNotFoundError:
        print("Error: crontab not found")
        return False

    if str(script_path) in existing:
        print(f"Cron job already exists for {script_path}")
        return True

    # Add to crontab
    new_crontab = existing.rstrip("\n") + "\n" + cron_line + "\n"
    proc = subprocess.run(["crontab", "-"], input=new_crontab, text=True,
                          capture_output=True)
    if proc.returncode == 0:
        print(f"✓ Cron job installed: runs every Sunday at 3:00 AM")
        print(f"  Log file: {log_path}")
        print(f"  To remove: crontab -e (and delete the wallpaper-scraper line)")
        return True
    else:
        print(f"✗ Failed to install cron job: {proc.stderr}")
        return False


# ─── CLI ─────────────────────────────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(
        description="Download trending ultrawide wallpapers from multiple sources.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                               Download with all default categories
  %(prog)s -c cyberpunk neon space        Specific categories only
  %(prog)s --max-per-category 5           More per category
  %(prog)s --max-total 50                 Cap total downloads
  %(prog)s --dry-run                      Preview without downloading
  %(prog)s --install-cron                 Set up weekly cron job
  %(prog)s --list-categories              Show available categories
        """,
    )
    parser.add_argument(
        "-c", "--categories", nargs="+", metavar="CAT",
        help="Categories to download (default: all). Use --list-categories to see options.",
    )
    parser.add_argument(
        "--max-per-category", type=int, default=DEFAULT_MAX_PER_CATEGORY,
        help=f"Max wallpapers per category per run (default: {DEFAULT_MAX_PER_CATEGORY})",
    )
    parser.add_argument(
        "--max-total", type=int, default=DEFAULT_MAX_TOTAL,
        help=f"Max total wallpapers per run (default: {DEFAULT_MAX_TOTAL})",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be downloaded without actually downloading",
    )
    parser.add_argument(
        "--install-cron", action="store_true",
        help="Install weekly cron job (Sunday 3 AM)",
    )
    parser.add_argument(
        "--list-categories", action="store_true",
        help="List all available categories and exit",
    )
    parser.add_argument(
        "--quiet", action="store_true",
        help="Reduce output (for cron usage)",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Show debug-level output",
    )
    parser.add_argument(
        "--min-width", type=int, default=MIN_WIDTH,
        help=f"Minimum image width in pixels (default: {MIN_WIDTH})",
    )
    parser.add_argument(
        "--min-height", type=int, default=MIN_HEIGHT,
        help=f"Minimum image height in pixels (default: {MIN_HEIGHT})",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    # Configure logging
    if args.quiet:
        level = logging.WARNING
    elif args.verbose:
        level = logging.DEBUG
    else:
        level = logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Handle special modes
    if args.list_categories:
        print("Available categories:")
        for name, terms in sorted(CATEGORIES.items()):
            print(f"  {name:20s} → {', '.join(terms)}")
        return

    if args.install_cron:
        install_cron()
        return

    # Override resolution if specified
    global MIN_WIDTH, MIN_HEIGHT
    MIN_WIDTH = args.min_width
    MIN_HEIGHT = args.min_height

    # Select categories
    if args.categories:
        selected = {}
        for cat in args.categories:
            cat_lower = cat.lower().replace(" ", "").replace("-", "").replace("_", "")
            # Fuzzy match against known categories
            matched = None
            for key in CATEGORIES:
                if key.lower().replace("_", "") == cat_lower:
                    matched = key
                    break
            if matched:
                selected[matched] = CATEGORIES[matched]
            else:
                log.warning("Unknown category '%s', skipping. Use --list-categories to see options.", cat)
        if not selected:
            log.error("No valid categories selected!")
            sys.exit(1)
    else:
        selected = CATEGORIES

    # Run downloader
    downloader = WallpaperDownloader(
        categories=selected,
        max_per_category=args.max_per_category,
        max_total=args.max_total,
        dry_run=args.dry_run,
    )
    downloader.run()


if __name__ == "__main__":
    main()

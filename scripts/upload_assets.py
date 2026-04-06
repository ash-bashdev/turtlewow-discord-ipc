#!/usr/bin/env python3
"""
Upload Discord Rich Presence assets from assets/ to a Discord application.

Usage:
    python scripts/upload_assets.py

Reads DISCORD_APP_ID and DISCORD_TOKEN from .env (or environment).
You can also pass --app-id and --token as CLI args to override.

Assets are uploaded via:
    POST /api/v10/oauth2/applications/{app_id}/assets
    Body: {"name": "key", "type": "1", "image": "data:image/png;base64,..."}

The asset key is derived from the filename (without extension), lowercased.
Discord automatically lowercases keys on their end too.

Directory structure:
    assets/
        class_icons/
            class_warrior.png   -> key: "class_warrior"
            class_mage.png      -> key: "class_mage"
            ...
        (add more subdirs as needed)
"""

import argparse
import base64
import json
import os
import sys
import time

try:
    import requests
except ImportError:
    print("Missing dependency. Install with: pip install requests")
    sys.exit(1)

API = "https://discord.com/api/v10"
EXTS = {".png", ".jpg", ".jpeg", ".webp"}
MIMES = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
}


def find_images(root):
    """Walk root and return [(key, path), ...] for all image files.

    Key is the path relative to the assets root, without extension.
    e.g. assets/class_icons/class_warrior.png -> "class_icons/class_warrior"

    Discord lowercases keys and allows slashes.
    """
    results = []
    root = os.path.abspath(root)
    for dirpath, _, filenames in os.walk(root):
        for f in sorted(filenames):
            ext = os.path.splitext(f)[1].lower()
            if ext not in EXTS:
                continue
            rel = os.path.relpath(os.path.join(dirpath, f), root)
            key = (
                os.path.splitext(rel)[0].lower().replace(os.sep, "-").replace("/", "-")
            )
            results.append((key, os.path.join(dirpath, f)))
    return results


def get_remote_assets(app_id, headers):
    """Fetch already-uploaded assets. Returns {name: id}."""
    r = requests.get(f"{API}/oauth2/applications/{app_id}/assets", headers=headers)
    if r.status_code == 200:
        return {a["name"]: a["id"] for a in r.json()}
    print(f"Warning: failed to fetch existing assets ({r.status_code})")
    return {}


def upload(app_id, key, path, headers):
    """Upload one image. Returns response."""
    ext = os.path.splitext(path)[1].lower()
    mime = MIMES.get(ext, "image/png")
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    return requests.post(
        f"{API}/oauth2/applications/{app_id}/assets",
        headers=headers,
        json={"name": key, "type": "1", "image": f"data:{mime};base64,{b64}"},
    )


def load_env():
    """Load .env file from project root if it exists."""
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    if not os.path.isfile(env_path):
        return
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            value = value.strip().strip("'\"")
            os.environ.setdefault(key.strip(), value)


def main():
    load_env()

    p = argparse.ArgumentParser(description="Upload Discord Rich Presence assets")
    p.add_argument(
        "--app-id",
        default=os.environ.get("DISCORD_APP_ID"),
        help="Discord Application ID (or set DISCORD_APP_ID in .env)",
    )
    p.add_argument(
        "--token",
        default=os.environ.get("DISCORD_TOKEN"),
        help="Discord auth token (or set DISCORD_TOKEN in .env)",
    )
    p.add_argument(
        "--assets-dir", default=os.path.join(os.path.dirname(__file__), "..", "assets")
    )
    p.add_argument("--dry-run", action="store_true", help="Show what would be uploaded")
    p.add_argument(
        "--delete-stale",
        action="store_true",
        help="Delete remote assets not found locally",
    )
    args = p.parse_args()

    if not args.app_id:
        print("Error: --app-id or DISCORD_APP_ID in .env required")
        sys.exit(1)
    if not args.token:
        print("Error: --token or DISCORD_TOKEN in .env required")
        sys.exit(1)

    assets_dir = os.path.abspath(args.assets_dir)
    if not os.path.isdir(assets_dir):
        print(f"Assets directory not found: {assets_dir}")
        sys.exit(1)

    headers = {"Authorization": args.token, "Content-Type": "application/json"}
    local = find_images(assets_dir)

    if not local:
        print("No images found.")
        return

    print(f"Found {len(local)} local assets:")
    for key, path in local:
        kb = os.path.getsize(path) / 1024
        print(f"  {key:30s} {kb:6.0f} KB  {path}")

    if len(local) > 300:
        print(f"\nWarning: Discord limit is 300 assets, you have {len(local)}")

    print(f"\nFetching remote assets for app {args.app_id}...")
    remote = get_remote_assets(args.app_id, headers)
    print(f"  {len(remote)} already uploaded")

    local_keys = {k for k, _ in local}
    to_upload = [(k, p) for k, p in local if k not in remote]
    skipped = [(k, p) for k, p in local if k in remote]
    stale = {k: v for k, v in remote.items() if k not in local_keys}

    if skipped:
        print(
            f"\nSkipping {len(skipped)} (already exist): {', '.join(k for k, _ in skipped)}"
        )

    if stale:
        print(f"\nStale remote assets (not in local): {', '.join(stale.keys())}")
        if args.delete_stale:
            for key, asset_id in stale.items():
                if args.dry_run:
                    print(f"  Would delete: {key}")
                    continue
                print(f"  Deleting: {key}...", end=" ", flush=True)
                r = requests.delete(
                    f"{API}/oauth2/applications/{args.app_id}/assets/{asset_id}",
                    headers=headers,
                )
                print("ok" if r.status_code == 204 else f"FAILED {r.status_code}")
                time.sleep(0.5)

    if not to_upload:
        print("\nNothing to upload.")
        return

    print(f"\nUploading {len(to_upload)} assets...")
    for i, (key, path) in enumerate(to_upload):
        if args.dry_run:
            print(f"  [{i + 1}/{len(to_upload)}] Would upload: {key}")
            continue

        print(f"  [{i + 1}/{len(to_upload)}] {key}...", end=" ", flush=True)
        r = upload(args.app_id, key, path, headers)

        if r.status_code in (200, 201):
            print("ok")
        elif r.status_code == 429:
            wait = r.json().get("retry_after", 5)
            print(f"rate limited, waiting {wait}s...")
            time.sleep(wait)
            r = upload(args.app_id, key, path, headers)
            print("ok" if r.status_code in (200, 201) else f"FAILED {r.status_code}")
        else:
            print(f"FAILED {r.status_code}: {r.text[:200]}")

        time.sleep(0.5)

    print("\nDone.")


if __name__ == "__main__":
    main()

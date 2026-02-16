# ThumbCompare (macOS SwiftUI)

ThumbCompare is a macOS app that compares your thumbnail/title against recent uploads from competitor YouTube channels in a feed-style grid, then exports a PNG snapshot for quick side-by-side review.

## What It Does
- Loads your thumbnail (A/B supported), title, and channel info.
- Fetches recent videos from competitor handles.
- Filters for feed-friendly videos (non-Shorts with usable thumbnails).
- Displays a mixed comparison feed and lets you export it as PNG.

## API Key Setup (Required)
You must use your own YouTube Data API v3 key.

1. Go to [Google Cloud Console](https://console.cloud.google.com/).
2. Create/select a project.
3. Enable **YouTube Data API v3** for that project.
4. Create an API key in **APIs & Services -> Credentials**.
5. In ThumbCompare, open **Settings** and paste the key.
6. Click **Save**.

The key is stored locally in macOS Keychain via `KeychainStore`.

## Security Notes
- Do not commit or share real API keys.
- This repository includes local secret scanning hooks to reduce accidental leaks.
- Optional search fallback uses more YouTube API quota.

## Fetch flow summary
1. Resolve each handle using `channels.list?forHandle=...`.
2. Optional fallback: if enabled, use `search.list` to find channel ID, then call `channels.list?id=...`.
3. Read `contentDetails.relatedPlaylists.uploads`.
4. Fetch latest N uploads from `playlistItems.list`.
5. Render competitor thumbnails, caching images in memory + disk at Application Support/ThumbCompare/Cache.

## Project layout
- `ThumbCompare/Views/`
- `ThumbCompare/Models/`
- `ThumbCompare/Services/YouTubeAPIService.swift`
- `ThumbCompare/Services/ImageCache.swift`
- `ThumbCompare/Utils/KeychainStore.swift`

## Git secret scan hook
- This repo includes a pre-commit secret scanner in `scripts/check-secrets.sh`.
- Enable the versioned hooks path once per clone:
  - `git config core.hooksPath .githooks`
- The hook blocks commits if staged content looks like API keys/tokens/private keys.
- A matching `pre-push` hook also runs the same scan before push.
- If a match is intentional (for test data), append `secret-scan: allow` on that line.

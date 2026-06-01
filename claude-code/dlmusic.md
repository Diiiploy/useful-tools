---
description: Download YouTube (or any yt-dlp-supported) audio to ~/Music with slug-cased filenames. Wraps the dlmusic terminal command.
argument-hint: "[URL] [-s | --split]"
---

Run the `dlmusic` script (lives at `~/.local/bin/dlmusic`) to download audio
from a YouTube / SoundCloud / Bandcamp / Mixcloud / etc. URL into `~/Music`.

Parse `$ARGUMENTS`:
- If a URL is present, pass it through.
- If `-s` or `--split` appears, include it (splits by YouTube chapters).
- If `$ARGUMENTS` is empty, run `dlmusic` with no args — the script reads
  the URL from the X11 clipboard via `xclip`.

Execute:

```bash
dlmusic $ARGUMENTS
```

Then report to the user in 2-4 lines:
- The slug-cased filename(s) that landed in `~/Music`
- If `--split` was used, the count of chapter files produced
- If the script printed "Skipping (already exists)", surface that plainly
- If yt-dlp failed, surface the exit code and the relevant error from stderr

Features the underlying script delivers (so the user knows what's automatic):
- Auto-slugifies title to `lower-case-with-hyphens.opus`
- Embeds YouTube thumbnail as cover art
- Embeds metadata (title / uploader / etc.)
- Dedupes against files already in `~/Music`
- Fires a desktop notification on done / skip / fail
- With `--split`, removes the full-mix file and keeps only numbered chapters
  like `slug-01-track-name.opus`, `slug-02-...`, etc.

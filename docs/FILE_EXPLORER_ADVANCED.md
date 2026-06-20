# Advanced File Explorer

Phase F extends the restricted SFTP browser while preserving the warm-storage
boundary.

Current status: the app supports direct SFTP browsing, transfer history, write
toggles, capped text/code previews, image previews, external PDF/Office opens,
and configurable background disconnect timing. The server-side restricted SFTP
account remains the real security boundary.

Current additions:

- local SQLite metadata store via `sqflite`
- favorites per SFTP profile
- recent downloads per SFTP profile
- resumable downloads using `.part` files plus stored checkpoints
- bounded recursive remote search
- image, text/code, cached-video, and external PDF/Office preview paths
- gated upload, create-directory, rename, move, and soft-delete controls
- configurable SFTP background timeout: immediate, 1 minute, 5 minutes,
  15 minutes, 30 minutes, or manual disconnect

Text/code preview extensions:

```text
.txt .log .md .json .yaml .yml .xml .csv .py .js .ts .dart .java .cs .cpp
.c .h .html .css .sh .ps1 .sql
```

Text previews are capped at 512 KB. Larger files should be downloaded or opened
externally rather than loaded fully into memory.

PDF and Office files:

```text
.pdf .docx .doc .pptx .ppt .xlsx .xls
```

These are cached locally and opened with Android external-app intents when a
handler is available.

Safety defaults:

- virtual-root enforcement still clamps paths into the configured root
- symlink navigation remains disabled
- uploads and other mutations default to disabled in Settings
- soft delete moves entries into `.tablet-trash` under the virtual root

Manual review before enabling writes:

- confirm the restricted SFTP account is intentionally write-capable
- confirm `.tablet-trash` fits the server cleanup policy
- keep cold storage outside the visible virtual root

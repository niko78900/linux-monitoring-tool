# Advanced File Explorer

Phase F extends the restricted SFTP browser while preserving the warm-storage
boundary.

Current additions:

- local SQLite metadata store via `sqflite`
- favorites per SFTP profile
- recent downloads per SFTP profile
- resumable downloads using `.part` files plus stored checkpoints
- bounded recursive remote search
- image, text, and cached-video preview paths
- gated upload, create-directory, rename, move, and soft-delete controls

Safety defaults:

- virtual-root enforcement still clamps paths into the configured root
- symlink navigation remains disabled
- uploads and other mutations default to disabled in Settings
- soft delete moves entries into `.tablet-trash` under the virtual root

Manual review before enabling writes:

- confirm the restricted SFTP account is intentionally write-capable
- confirm `.tablet-trash` fits the server cleanup policy
- keep cold storage outside the visible virtual root

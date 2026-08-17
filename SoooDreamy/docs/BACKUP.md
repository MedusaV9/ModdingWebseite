# SoooDreamy server backups

> **Deutsch (Kurzfassung):** Der Server legt standardmäßig **stündlich** ein
> verifiziertes Backup unter `DATA_DIR/backups/` an (Aufbewahrung: die letzten
> 10, dazu 48 h stündlich + 14 Tage täglich). Medien sind standardmäßig
> enthalten. Für ein manuelles Backup den Server stoppen, dann `npm run backup`.
> Wiederherstellen: Server stoppen → `npm run restore -- --list` →
> `npm run restore -- --restore <id>` → `npm start`. Vor jeder Migration und
> jedem Restore wird automatisch ein zusätzliches Sicherheits-Backup angelegt.

## What is backed up

A backup is a folder under `DATA_DIR/backups/<id>/` containing:

- `store.json` (manifest: sessions + couple index)
- `segments/*.json` (one checksummed file per couple — messages, photos
  metadata, games, …)
- `backup.json` — the backup's own manifest with a SHA-256 checksum and byte
  size for **every** file
- `media/**` (photos/voice/videos/vault blobs) by default. The explicit
  `--no-media` / `BACKUP_INCLUDE_MEDIA=0` opt-out creates a metadata-only
  backup; `/api/health` then reports `backup_media_unprotected`

Backups are **atomic** (staged in a temp folder, verified byte-for-byte
against what landed on disk, then renamed into place) and **verified again
before every restore** — a tampered or bit-rotten backup is refused instead of
silently restoring garbage.

## Automatic rotation

The running server takes an `auto` backup on an interval and prunes old ones:

| Env var | Default | Meaning |
|---|---|---|
| `BACKUP_INTERVAL_MINUTES` | `60` | interval; `0` disables the scheduler |
| `BACKUP_KEEP_LAST` | `10` | newest N backups always survive pruning |
| `BACKUP_KEEP_HOURLY` | `48` | keep the newest backup of every hour for N hours |
| `BACKUP_KEEP_DAILY` | `14` | keep the newest backup of every day for N days |
| `BACKUP_INCLUDE_MEDIA` | unset (`media` included) | `0` = explicit metadata-only opt-out |

Special backups are created automatically:

- `pre-migration` — before `npm run migrate` changes anything
- `pre-restore` — before a restore replaces the current state (so a restore
  is itself always reversible)

## Commands

```bash
npm run backup                                  # full manual backup + prune (server stopped)
npm run backup -- --reason before-move
npm run backup -- --no-media                    # explicit metadata-only backup
npm run backup -- --data-dir /srv/sooodreamy/data --no-prune

npm run restore -- --list                       # newest first, with reason/size
npm run restore -- --verify <id>                # integrity check only
npm run restore -- --restore <id>               # ⚠️ stop the server first!
```

`--restore` refuses backups that fail their checksum verification, saves the
current state as a `pre-restore` backup, replaces `store.json` +
`segments/`, and clears stale `.bak` generations so nothing old shadows the
restored files. Media is only written when the backup includes media.

**Stop the server before external backup, migration, or restore.** All three
tools acquire the same exclusive `DATA_DIR` lock as the server and fail clearly
instead of racing a live writer. Admin-panel and scheduled backups run inside
the server, flush the store first, and are safe while it is running.

## Where this sits in the corruption story

Backups are the third safety net, in order of engagement:

1. every acknowledged mutation is first committed to `store.wal` with
   file + parent-directory `fsync`; restart replays the journal
2. compaction uses atomic tmp + rename, keeps `<file>.bak`, and checksums
   manifests/segments; unreadable/corrupt files are moved to
   `DATA_DIR/quarantine/` (never deleted) while the rest of the server keeps
   running; affected couples get an honest `503 couple_data_quarantined`
3. `npm run restore` brings a quarantined couple (or everything) back from
   the last good backup

Off-site copies: the whole `DATA_DIR/backups/` folder is plain files — rsync
or snapshot it wherever you like. Restoring on a fresh box = copy `DATA_DIR`
(or a backup folder's contents + `media/`), then `npm start`.

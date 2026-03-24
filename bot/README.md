# linux-monitor Discord Bot

Separate Python service that consumes the existing FastAPI monitoring API and posts to Discord.

## What it does

- Slash commands:
  - `/status` -> uses `GET /api/system` (+ `GET /api/gpu` fallback-aware)
  - `/health` -> uses `GET /api/health`
  - `/docker` -> uses `GET /api/docker`
  - `/gpu` -> uses `GET /api/gpu`
  - `/system` -> uses `GET /api/system`
  - `/status_schedule <interval_minutes>` -> schedule periodic status posts in current channel
  - `/status_schedule_off` -> disable scheduled status posts
  - `/status_schedule_show` -> view current schedule settings
- Background polling with alerting:
  - CPU / memory threshold alerts
  - Disk threshold + disk health alerts (`/api/system`)
  - RAID alerts (`/api/system`, configurable)
  - Physical disk health alerts (`/api/system`)
  - GPU temperature alerts (`/api/gpu`)
  - Docker availability alerts (`/api/docker`, configurable)
  - Backend/endpoint availability alerts
- Alert deduplication and recovery notifications.

## Requirements

- Python 3.11+
- Existing backend reachable at `MONITOR_API_BASE_URL`
- Discord bot token and target channel

## Setup

```bash
cd bot
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

Windows PowerShell:

```powershell
cd bot
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
```

## Environment variables

- `DISCORD_BOT_TOKEN` (required)
- `DISCORD_GUILD_ID` (optional but recommended for fast slash-command sync in one server)
- `DISCORD_CHANNEL_ID` (required; channel for alert messages)
- `MONITOR_API_BASE_URL` (required; example `http://127.0.0.1:4040`)
- `POLL_INTERVAL_SECONDS` (default `30`)
- `CPU_ALERT_THRESHOLD` (default `85`)
- `MEMORY_ALERT_THRESHOLD` (default `90`)
- `DISK_ALERT_THRESHOLD` (default `90`)
- `GPU_TEMP_ALERT_THRESHOLD` (default `80`)
- `ENABLE_DOCKER_ALERTS` (`true`/`false`, default `true`)
- `ENABLE_RAID_ALERTS` (`true`/`false`, default `true`)
- `STATUS_SCHEDULE_STATE_FILE` (optional, default `status_schedule_state.json` in `bot/`)
- `ALERT_STATE_FILE` (optional, default `alert_state.json` in `bot/`)

## Run

```bash
cd bot
python src/bot.py
```

## Tests

```bash
python -m unittest discover tests -v
```

## Notes

- This bot does not duplicate monitoring logic. It only consumes the backend API contract.
- If `DISCORD_GUILD_ID` is set, commands are synced to that guild only.
- If `DISCORD_GUILD_ID` is empty, commands are synced globally (can take longer to appear).
- Scheduled status settings are persisted to disk and restored after bot restart.
- Active alert dedupe state is persisted to disk and restored after bot restart.
- Changing scheduled status settings requires Discord `Manage Server` permission.

# linux-monitor Discord Bot

Separate Python service that consumes the monitoring backend and posts to Discord.

Current boundary: the bot is a presentation client only. The monitoring backend
owns threshold evaluation, alert state, mobile push delivery, and FCM
credentials. The control agent owns privileged host/device/service actions. The
bot does not call the control agent.

## What It Does

- Slash commands:
  - `/status` -> `GET /api/system` plus GPU fallback
  - `/health` -> `GET /api/health`
  - `/docker` -> `GET /api/docker`
  - `/gpu` -> `GET /api/gpu`
  - `/system` -> `GET /api/system`
  - `/status_schedule <interval_minutes>`
  - `/status_schedule_custom <windows_spec>`
  - `/status_schedule_off`
  - `/status_schedule_show`
- Background alert presentation:
  - polls `GET /api/alerts/events`
  - posts backend-generated alert/recovery events in order
  - advances `DISCORD_ALERT_CURSOR_FILE` only after Discord send succeeds
  - keeps a Discord-only backend-unreachable warning because a dead backend cannot report itself

The bot does not own CPU/RAM/GPU/disk threshold evaluation, Firebase credentials, mobile FCM registration, mobile retry state, or mobile push delivery.

## Requirements

- Python 3.11+
- Monitoring backend reachable at `MONITORING_API_BASE_URL`
- `ALERT_CONSUMER_API_TOKEN` matching the backend
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

## Environment Variables

- `DISCORD_BOT_TOKEN` (required)
- `DISCORD_GUILD_ID` (optional, faster slash-command sync for one server)
- `DISCORD_CHANNEL_ID` (required)
- `MONITORING_API_BASE_URL` (required, example `http://127.0.0.1:4040/api`)
- `ALERT_CONSUMER_API_TOKEN` (required)
- `POLL_INTERVAL_SECONDS` (default `30`)
- `DISCORD_ALERT_CURSOR_FILE` (default `discord_alert_cursor.json` in `bot/`, canonical deployment example `/var/lib/linux-monitor/state/bot/discord_alert_cursor.json`)
- `DISCORD_ALERT_REPLAY_ON_FIRST_START` (default `false`)
- `STATUS_SCHEDULE_STATE_FILE` (optional, default `status_schedule_state.json` in `bot/`)

`MONITOR_API_BASE_URL` is still accepted as a legacy alias; if it does not end in `/api`, the bot appends `/api`.

## Run

```bash
cd bot
python src/bot.py
```

## Custom Schedule Format

Use `/status_schedule_custom` with:

`HH:MM-HH:MM=MINUTES;HH:MM-HH:MM=MINUTES;...`

Examples:

- `12:00-15:00=15;15:00-18:00=60;18:00-21:00=45;21:00-06:00=360`
- `08:00-00:00=60;00:00-08:00=180`

Rules:

- Uses 24h time.
- Windows must not overlap.
- Windows may wrap midnight (`21:00-06:00`).
- Bot posts only inside configured windows.

## Tests

```bash
python -m unittest discover tests -v
```

## Notes

- The monitoring backend is the alert source of truth.
- The backend sends mobile FCM notifications directly.
- The bot does not import Firebase Admin SDK.
- The bot does not read backend SQLite files or mobile registry JSON files.
- The bot does not call control-agent host, device, service, Wake-on-LAN, SSH,
  or SFTP APIs.
- Scheduled status settings are persisted to disk and restored after bot restart.
- Changing scheduled status settings requires Discord `Manage Server` permission.

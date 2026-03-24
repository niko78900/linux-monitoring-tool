# Linux Monitoring - Dev Setup

This repository is configured as:

- `backend/`: FastAPI monitoring backend (`/api/*`)
- `frontend/`: Angular dashboard frontend
- `bot/`: Discord bot service (consumes backend API, separate process)

## 1) Start backend (FastAPI)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m ensurepip --upgrade
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe run.py
```

Backend runs on `http://localhost:4040` by default (or your server IP if you bind externally).

## 2) Start frontend (Angular)

Open a second terminal:

```powershell
cd frontend
npm.cmd install
npm.cmd start
```

Frontend runs on `http://localhost:4041` by default.
The dev server binds to `0.0.0.0`, so it is reachable from LAN/Tailscale at
`http://<your-host-ip>:4041`.

In development, frontend API calls use same-origin paths (`/api/*`) and are
proxied to `http://127.0.0.1:4040` via:

- `frontend/proxy.conf.json`

Shared frontend API settings are in:

- `frontend/src/environments/environment.shared.ts`

## 3) Production shape (recommended)

- Build frontend static assets (`npm run build` in `frontend/`).
- Serve frontend and backend behind one reverse proxy origin (for example, `/api` -> backend `127.0.0.1:4040`).
- Keep backend `HOST=127.0.0.1` in production when using a reverse proxy.
- Set strict backend `CORS_ORIGINS` (or keep same-origin only if all API traffic goes through proxy).

## 4) Start Discord bot service (optional)

```powershell
cd bot
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
# fill .env values
.\.venv\Scripts\python.exe src\bot.py
```

Bot details and env configuration are documented in:

- `bot/README.md`

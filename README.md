# Linux Monitoring - Dev Setup

This repository is configured as:

- `backend/`: Flask API (`/api/health`)
- `frontend/`: Angular app with a dev proxy for `/api/*` to Flask

## 1) Start backend (Flask)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m ensurepip --upgrade
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe run.py
```

Backend runs on `http://127.0.0.1:5000`.

## 2) Start frontend (Angular)

Open a second terminal:

```powershell
cd frontend
npm.cmd install
npm.cmd start
```

Frontend runs on `http://localhost:4200`.

`npm.cmd start` uses `proxy.conf.json`, so Angular requests to `/api/*`
are proxied to `http://127.0.0.1:5000`.

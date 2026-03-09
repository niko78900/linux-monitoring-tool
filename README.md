# Linux Monitoring - Dev Setup

This repository is configured as:

- `backend/`: FastAPI monitoring backend (`/api/*`)
- `frontend/`: Angular dashboard frontend

## 1) Start backend (FastAPI)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m ensurepip --upgrade
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe run.py
```

Backend runs on `http://192.168.100.34:4040`.

## 2) Start frontend (Angular)

Open a second terminal:

```powershell
cd frontend
npm.cmd install
npm.cmd start
```

Frontend runs on `http://192.168.100.34:4041`.

`npm.cmd start` uses `proxy.conf.json`, so Angular requests to `/api/*`
are proxied to `http://192.168.100.34:4040`.

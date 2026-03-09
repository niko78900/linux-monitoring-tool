# linux-monitor backend (FastAPI)

Read-only monitoring API for local-network dashboards.

## Project layout

```
backend/
  app/
    api/
      routes/
    core/
    models/
    services/
    main.py
  .env.example
  requirements.txt
  run.py
```

## 1) Create virtual environment

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Windows PowerShell:

```powershell
cd Backend
python -m venv .venv
.\.venv\Scripts\python.exe -m ensurepip --upgrade
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## 2) Configure environment

```bash
cp .env.example .env
```

Adjust `.env` values if needed:

- `CORS_ORIGINS`: comma-separated frontend origins
- `DISK_MOUNTPOINT`: disk mount to report (default `/`)
- `HOST`/`PORT`: bind address and port

## 3) Run the API

```bash
python run.py
```

Default URL:

- API root: `http://localhost:8000/api`
- Docs: `http://localhost:8000/api/docs`

## 4) Test endpoints

```bash
curl http://localhost:8000/api/health
curl http://localhost:8000/api/system
curl http://localhost:8000/api/gpu
curl http://localhost:8000/api/docker
curl http://localhost:8000/api/summary
```

## Notes on permissions

- Docker data requires access to Docker Engine socket (`/var/run/docker.sock` on Linux).
  - Add your user to the `docker` group or run with elevated privileges.
- NVIDIA metrics require:
  - NVIDIA drivers installed
  - NVML library available on host
  - process permission to access NVIDIA device files
- If Docker/NVIDIA access is missing, endpoints return `available: false` style responses instead of crashing.

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
cd backend
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

- API root: `http://localhost:4040/api`
- Docs: `http://localhost:4040/api/docs`

If the backend runs on a homelab server, replace `localhost` with that server IP
(for example `http://192.168.100.34:4040`).

## 4) Test endpoints

```bash
curl http://localhost:4040/api/health
curl http://localhost:4040/api/system
curl http://localhost:4040/api/gpu
curl http://localhost:4040/api/docker
curl http://localhost:4040/api/summary
```

`/api/system` now includes:

- `specs`: static hardware-oriented system specs:
  - `cpu.model_name`, `cpu.vendor`, `cpu.architecture`
  - `cpu.physical_cores`, `cpu.logical_cores`
  - `cpu.min_frequency_mhz`, `cpu.max_frequency_mhz` (when available)
  - `cpu.capabilities` (instruction-set/feature flags from `/proc/cpuinfo` on Linux)
  - `memory_total_bytes`, `swap_total_bytes`
  - `memory`: RAM inventory (total bytes, speed, type, detected vendors, module list when available)
  - `motherboard`: board vendor/model/version and chipset hint (from DMI/sysfs when available)
  - `gpu`: static GPU metadata (brand/model/driver, total VRAM, capability list)
- `disk`: primary disk (configured `DISK_MOUNTPOINT`, kept for compatibility)
- `disks`: all detected mounted disks/partitions with:
  - `device`, `mountpoint`, `fstype`
  - `total`, `used`, `free`, `percent`
  - `available`, `read_only`
  - `raid_array`, `raid_level` when a mounted filesystem is on an MD RAID device
  - `health.status` (`healthy`, `warning`, `critical`, `unknown`) and `health.reason`
- `raid_arrays`: detected Linux MD arrays with level, state, sync status, members, and health
- `physical_disks`: detected physical block devices with:
  - `device`, `model`, `vendor`, `serial`, `size_bytes`
  - `rotational`, `removable`, `state`
  - `mounted_partitions`, `raid_arrays`
  - `health.status` and `health.reason`
- `network.top_speed_mbps`: highest detected link speed from network interfaces (if available)

Disk list intentionally excludes pseudo/system mounts and EFI boot mountpoints such as `/boot/efi`.

## Notes on permissions

- Docker data requires access to Docker Engine socket (`/var/run/docker.sock` on Linux).
  - Add your user to the `docker` group or run with elevated privileges.
- NVIDIA metrics require:
  - NVIDIA drivers installed
  - NVML library available on host
  - process permission to access NVIDIA device files
- If Docker/NVIDIA access is missing, endpoints return `available: false` style responses instead of crashing.

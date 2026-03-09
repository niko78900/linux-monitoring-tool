# Backend (Flask)

## Create virtual environment

```powershell
cd Backend
python -m venv .venv
.\.venv\Scripts\python.exe -m ensurepip --upgrade
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## Run development server

```powershell
.\.venv\Scripts\python.exe run.py
```

The API will be available at `http://127.0.0.1:5000`.

Health endpoint:

`GET http://127.0.0.1:5000/api/health`

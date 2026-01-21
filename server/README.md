# Server

## Setup
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create `.env` from `.env.example` and set `INGEST_TOKEN`.

## Run
```bash
uvicorn app:app --host 0.0.0.0 --port 8787 --reload
```

## Test
```bash
chmod +x test_endpoints.sh
./test_endpoints.sh
```

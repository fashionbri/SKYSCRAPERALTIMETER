import os
import time
import json
import requests

BASE_URL = os.getenv("ALT_BASE_URL", "http://127.0.0.1:8787")

def get(path: str):
    return requests.get(f"{BASE_URL}{path}", timeout=5)

def post(path: str, payload: dict):
    return requests.post(f"{BASE_URL}{path}", json=payload, timeout=5)

def main():
    print(f"[e2e] BASE_URL={BASE_URL}")

    # 1) Health
    r = get("/health")
    assert r.status_code == 200, f"/health status={r.status_code} body={r.text}"
    print("[e2e] /health OK:", r.json() if r.headers.get("content-type","").startswith("application/json") else r.text)

    # 2) Try to push a sample reading (only if endpoint exists)
    sample = {
        "timestamp_ms": int(time.time() * 1000),
        "relative_altitude_m": 1.23,
        "pressure_kpa": 101.3,
        "vertical_gain_m_since_start": 1.23
    }

    # Common ingest paths (adjust if your API differs)
    ingest_paths = ["/ingest", "/update", "/reading"]
    ingest_ok = False
    for p in ingest_paths:
        try:
            rr = post(p, sample)
            if rr.status_code in (200, 201, 202):
                print(f"[e2e] POST {p} OK ({rr.status_code})")
                ingest_ok = True
                break
        except requests.RequestException:
            pass

    if not ingest_ok:
        print("[e2e] No ingest endpoint detected (skipping POST step).")

    # 3) Try to fetch latest JSON (adjust if your API differs)
    latest_paths = ["/latest", "/data", "/altimeter", "/json"]
    latest_ok = False
    for p in latest_paths:
        try:
            rr = get(p)
            if rr.status_code == 200:
                print(f"[e2e] GET {p} OK")
                # best effort JSON parse
                try:
                    print(json.dumps(rr.json(), indent=2)[:1500])
                except Exception:
                    print(rr.text[:1500])
                latest_ok = True
                break
        except requests.RequestException:
            pass

    if not latest_ok:
        print("[e2e] No 'latest' endpoint detected. If expected, add one and update this test.")
    print("[e2e] DONE")

if __name__ == "__main__":
    main()

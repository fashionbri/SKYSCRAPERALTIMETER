import os
import time
from typing import Any, Dict, Optional

from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

load_dotenv()

PORT = int(os.getenv("PORT", "8787"))
INGEST_TOKEN = os.getenv("INGEST_TOKEN")

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"]
)

latest_payload: Optional[Dict[str, Any]] = None


class IngestPayload(BaseModel):
    device_id: str
    timestamp_ms: int
    relative_altitude_m: float
    pressure_kpa: float
    vertical_gain_m: float
    net_change_m: float
    seq: int
    battery_level: Optional[float] = None
    is_charging: Optional[bool] = None
    app_version: Optional[str] = None


@app.on_event("startup")
def startup() -> None:
    if not INGEST_TOKEN:
        raise RuntimeError("INGEST_TOKEN environment variable is required")
    print(f"Server starting on port {PORT}")
    print("Ingest endpoint secured with token authentication")


@app.post("/ingest")
async def ingest(
    payload: IngestPayload,
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> Dict[str, bool]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Unauthorized")
    token = authorization.split("Bearer ", 1)[1]
    if token != INGEST_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")

    received_at_ms = int(time.time() * 1000)
    source_ip = request.client.host if request.client else None

    stored_payload = payload.dict()
    stored_payload["received_at_ms"] = received_at_ms
    stored_payload["source_ip"] = source_ip

    global latest_payload
    latest_payload = stored_payload

    return {"ok": True}


@app.get("/latest")
async def latest() -> Response:
    if latest_payload is None:
        return Response(status_code=204)

    headers = {
        "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
        "Pragma": "no-cache",
        "Expires": "0",
    }

    return JSONResponse(content=latest_payload, headers=headers)


@app.get("/health")
async def health() -> Dict[str, Any]:
    return {
        "ok": True,
        "has_data": latest_payload is not None,
        "last_received_at_ms": latest_payload.get("received_at_ms") if latest_payload else None,
    }

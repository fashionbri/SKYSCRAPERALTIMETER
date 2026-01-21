#!/usr/bin/env bash
set -euo pipefail

BASE_URL=${BASE_URL:-"http://localhost:8787"}
TOKEN=${INGEST_TOKEN:-"your_secure_token_here"}

curl -s -X POST "$BASE_URL/ingest" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-device",
    "timestamp_ms": 1700000000000,
    "relative_altitude_m": 12.3,
    "pressure_kpa": 101.2,
    "vertical_gain_m": 15.0,
    "net_change_m": 10.0,
    "seq": 1,
    "battery_level": 0.88,
    "is_charging": false,
    "app_version": "1.0.0"
  }'

curl -s -X POST "$BASE_URL/ingest" \
  -H "Authorization: Bearer invalid_token" \
  -H "Content-Type: application/json" \
  -d '{
    "device_id": "test-device",
    "timestamp_ms": 1700000000001,
    "relative_altitude_m": 12.4,
    "pressure_kpa": 101.1,
    "vertical_gain_m": 15.1,
    "net_change_m": 10.1,
    "seq": 2
  }' || true

curl -s "$BASE_URL/latest"

echo

curl -s "$BASE_URL/health"

echo

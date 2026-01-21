# API

## POST /ingest
Authenticated with `Authorization: Bearer <token>`.

Required fields:
- device_id (string)
- timestamp_ms (int)
- relative_altitude_m (float)
- pressure_kpa (float)
- vertical_gain_m (float)
- net_change_m (float)
- seq (int)

Optional fields:
- battery_level (float)
- is_charging (bool)
- app_version (string)

## GET /latest
Returns the most recent payload with cache disabled. Returns 204 when no data is available.

## GET /health
Returns server status and last received timestamp.

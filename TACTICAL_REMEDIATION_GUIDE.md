# Tactical Remediation Guide
**Quick-reference implementation guide for critical fixes**

---

## Phase 1: Critical Server Fixes (8 hours)

### Fix 1: Update Pydantic Model (30 minutes)

**File:** `server/app.py`

Replace the existing `IngestPayload` class (lines 28-38) with:

```python
class IngestPayload(BaseModel):
    # Core identifiers
    run_id: str  # NEW: Session identifier (e.g., "2026-01-21T15:22:10+08:00_s25_001")
    device_id: str
    ts_unix_ms: int  # RENAMED from timestamp_ms for PRD compliance

    # Altitude & pressure data
    vertical_gain_m: float
    pressure_hpa: float  # CHANGED from pressure_kpa (BREAKING CHANGE: kPa → hPa)
    baseline_pressure_hpa: float  # NEW: Baseline reference
    altitude_estimate_m: Optional[float] = None  # NEW: Current altitude estimate
    baseline_altitude_m: Optional[float] = 0.0  # NEW: Always 0 by definition

    # Status & calibration
    baseline_set: bool  # NEW: True after calibration complete
    status: str  # NEW: "calibrating" | "ok" | "sensor_error" | "network_error"

    # Performance monitoring
    sample_hz: Optional[float] = None  # NEW: Current sensor sample rate

    # Device metadata (keep existing)
    battery_level: Optional[float] = None
    is_charging: Optional[bool] = None
    app_version: Optional[str] = None

    # Legacy compatibility (deprecated)
    net_change_m: Optional[float] = None  # From iOS implementation
    seq: Optional[int] = None  # From iOS implementation
```

### Fix 2: Update /health Endpoint (1 hour)

**File:** `server/app.py`

Add startup time tracking at module level (after `latest_payload` declaration):

```python
latest_payload: Optional[Dict[str, Any]] = None
startup_time = time.time()  # ADD THIS LINE
```

Replace the entire `/health` endpoint function (lines 88-94) with:

```python
@app.get("/health")
async def health() -> Dict[str, Any]:
    """Health check with data freshness indicators per PRD FR-R-002"""

    if latest_payload is None:
        return {
            "status": "no_data",
            "last_ingest_ts_unix_ms": None,
            "age_ms": None,
            "current_vertical_gain_m": None,
            "baseline_set": False,
            "run_id": None,
            "uptime_s": int(time.time() - startup_time)
        }

    # Calculate data age
    current_time_ms = int(time.time() * 1000)
    last_ingest_ms = latest_payload.get("ts_unix_ms") or latest_payload.get("timestamp_ms", 0)
    age_ms = current_time_ms - last_ingest_ms

    # Determine status based on age
    if age_ms > 2000:
        status = "stale"
    else:
        status = "ok"

    return {
        "status": status,
        "last_ingest_ts_unix_ms": last_ingest_ms,
        "age_ms": age_ms,
        "current_vertical_gain_m": latest_payload.get("vertical_gain_m"),
        "baseline_set": latest_payload.get("baseline_set", False),
        "run_id": latest_payload.get("run_id"),
        "uptime_s": int(time.time() - startup_time)
    }
```

### Fix 3: Update /latest Endpoint (30 minutes)

**File:** `server/app.py`

Replace the entire `/latest` endpoint function (lines 74-85) with:

```python
@app.get("/latest")
async def latest() -> Response:
    """Return most recent payload per PRD FR-R-003"""

    if latest_payload is None:
        # PRD specifies 503 with JSON body (not 204)
        return JSONResponse(
            content={"status": "no_data"},
            status_code=503
        )

    # Calculate data age for header
    current_time_ms = int(time.time() * 1000)
    last_ingest_ms = latest_payload.get("ts_unix_ms") or latest_payload.get("timestamp_ms", 0)
    age_ms = current_time_ms - last_ingest_ms

    # PRD-compliant headers
    headers = {
        "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
        "Pragma": "no-cache",
        "Expires": "0",
        "X-Data-Age-Ms": str(age_ms)  # NEW: Age indicator per PRD
    }

    return JSONResponse(content=latest_payload, headers=headers)
```

### Fix 4: Fix CORS Middleware (15 minutes)

**File:** `server/app.py`

Replace the CORS middleware configuration (lines 18-23) with:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],  # FIXED: Add POST and OPTIONS
    allow_headers=["*"]
)
```

### Fix 5: Add /stream SSE Endpoint (OPTIONAL - 2 hours)

**File:** `server/app.py`

Add this import at the top:
```python
import asyncio
```

Add this new endpoint after `/latest`:

```python
@app.get("/stream")
async def stream():
    """Server-Sent Events stream per PRD FR-R-004"""

    async def event_generator():
        last_seq = 0
        while True:
            if latest_payload is not None:
                current_seq = latest_payload.get("seq", 0)
                # Only send if data changed
                if current_seq != last_seq:
                    last_seq = current_seq
                    payload_copy = latest_payload.copy()
                    yield f"data: {json.dumps(payload_copy)}\n\n"

            await asyncio.sleep(0.2)  # 5 Hz max update rate

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"  # Disable nginx buffering
        }
    )
```

Add import for StreamingResponse:
```python
from fastapi.responses import JSONResponse, StreamingResponse
```

### Fix 6: Remove Authentication (OPTIONAL - PRD Compliance)

**File:** `server/app.py`

If PRD compliance requires no authentication (trusted LAN), modify the `/ingest` endpoint:

**Option A: Remove authentication entirely**
```python
@app.post("/ingest")
async def ingest(
    payload: IngestPayload,
    request: Request
) -> Dict[str, Any]:  # Changed return type
    # Remove all authorization checks (lines 55-59)

    received_at_ms = int(time.time() * 1000)
    source_ip = request.client.host if request.client else None

    stored_payload = payload.dict()
    stored_payload["received_at_ms"] = received_at_ms
    stored_payload["source_ip"] = source_ip

    global latest_payload
    latest_payload = stored_payload

    return {
        "status": "received",
        "ts_unix_ms": received_at_ms
    }
```

**Option B: Keep authentication but document deviation**
- Add comment explaining deviation from PRD
- Update `.env.example` with clear setup instructions
- Document in README.md

### Fix 7: Update .env.example

**File:** `server/.env.example`

```bash
# Server configuration
PORT=8787

# Authentication (NOTE: PRD specifies no auth for trusted LAN)
# Set to empty string to disable: INGEST_TOKEN=
INGEST_TOKEN=your_secure_token_here

# Optional: Enable debug logging
DEBUG=false
```

---

## Phase 2: iOS App Updates (For iOS Deployment Path)

### Update 1: Fix Pressure Units (30 minutes)

**File:** `ios/SkyscraperAltimeter/SkyscraperAltimeter/AltimeterManager.swift`

Line 49: Change pressure calculation
```swift
// BEFORE:
let pressureKPa = data.pressure.doubleValue * 10.0

// AFTER:
let pressureHPa = data.pressure.doubleValue * 1000.0  // Convert to hectopascals
```

Update struct (line 6):
```swift
struct AltimeterReading {
    let relativeAltitudeM: Double
    let pressureHPa: Double  // Changed from pressureKPa
    let verticalGainM: Double
    let netChangeM: Double
    let seq: Int
}
```

Update published property (line 15):
```swift
@Published var pressureHPa: Double = 0.0  // Changed from pressureKPa
```

Update assignment (line 66):
```swift
self.pressureHPa = pressureHPa  // Changed from pressureKPa
```

Update AltimeterReading creation (line 72):
```swift
let reading = AltimeterReading(
    relativeAltitudeM: currentAltitude,
    pressureHPa: pressureHPa,  // Changed from pressureKPa
    verticalGainM: self.verticalGainM,
    netChangeM: self.netChangeM,
    seq: self.sequenceNumber
)
```

### Update 2: Add Missing Payload Fields (1 hour)

**File:** `ios/SkyscraperAltimeter/SkyscraperAltimeter/NetworkManager.swift`

Add run_id generation at class level (line 8):
```swift
private let deviceId: String
private let runId: String  // ADD THIS
```

Initialize run_id in init() (line 24):
```swift
deviceId = newId
defaults.set(newId, forKey: "deviceId")

// ADD THIS:
runId = "\(ISO8601DateFormatter().string(from: Date()))_\(deviceId.prefix(8))"
```

Update enqueuePayload function signature (line 60):
```swift
func enqueuePayload(
    relativeAltitudeM: Double,
    pressureHPa: Double,  // Changed from pressureKPa
    verticalGainM: Double,
    netChangeM: Double,
    seq: Int,
    battery: Double?,
    isCharging: Bool?
)
```

Update payload dictionary (line 69):
```swift
var payload: [String: Any] = [
    "run_id": runId,  // ADD THIS
    "device_id": deviceId,
    "ts_unix_ms": Int(Date().timeIntervalSince1970 * 1000),
    "vertical_gain_m": verticalGainM,
    "pressure_hpa": pressureHPa,  // Changed from pressure_kpa
    "baseline_pressure_hpa": pressureHPa,  // ADD THIS (simplified - use current as baseline)
    "altitude_estimate_m": relativeAltitudeM,  // ADD THIS
    "baseline_altitude_m": 0.0,  // ADD THIS
    "baseline_set": true,  // ADD THIS (always true in iOS - no calibration phase)
    "status": "ok",  // ADD THIS
    "net_change_m": netChangeM,
    "seq": seq,
    "app_version": "1.0.0"
]
```

### Update 3: Update ContentView (15 minutes)

**File:** `ios/SkyscraperAltimeter/SkyscraperAltimeter/ContentView.swift`

Line 26: Update pressure display
```swift
Text(String(format: "Pressure: %.2f hPa", altimeterManager.pressureHPa))
```

Line 78: Update enqueue call
```swift
networkManager.enqueuePayload(
    relativeAltitudeM: reading.relativeAltitudeM,
    pressureHPa: reading.pressureHPa,  // Changed from pressureKPa
    verticalGainM: reading.verticalGainM,
    netChangeM: reading.netChangeM,
    seq: reading.seq,
    battery: nil,
    isCharging: nil
)
```

---

## Phase 3: Dashboard Implementation (8 hours)

### File 1: Dashboard HTML

**Create:** `server/static/dashboard.html`

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SKYSCRAPERALTIMETER — Live Dashboard</title>
    <link rel="stylesheet" href="dashboard.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
</head>
<body>
    <div class="container">
        <header>
            <h1>SKYSCRAPERALTIMETER — LIVE DASHBOARD</h1>
            <div id="status-badge" class="badge badge-no-data">NO DATA</div>
            <div id="time-display">00:00</div>
        </header>

        <main>
            <div class="metrics-grid">
                <!-- Vertical Gain Card -->
                <div class="card card-primary">
                    <div class="card-header">VERTICAL GAIN</div>
                    <div class="card-body">
                        <div class="value-large" id="gain-meters">—</div>
                        <div class="value-unit">meters</div>
                        <div class="value-secondary" id="gain-feet">—</div>
                        <div class="value-unit">feet</div>
                    </div>
                </div>

                <!-- Pressure Card -->
                <div class="card">
                    <div class="card-header">PRESSURE</div>
                    <div class="card-body">
                        <div class="value-medium" id="pressure-current">—</div>
                        <div class="value-unit">hPa</div>
                        <div class="baseline-info">
                            <span>Baseline: </span>
                            <span id="pressure-baseline">—</span>
                            <span id="baseline-lock" class="lock-icon" style="display:none">🔒</span>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Chart -->
            <div class="card card-chart">
                <div class="card-header">ALTITUDE CHART (Last 60s)</div>
                <div class="card-body">
                    <canvas id="altitudeChart"></canvas>
                </div>
            </div>

            <!-- Info Grid -->
            <div class="info-grid">
                <div class="card">
                    <div class="card-header">LAST UPDATE</div>
                    <div class="card-body">
                        <div id="last-update-time">—</div>
                        <div id="last-update-age" class="text-secondary">—</div>
                    </div>
                </div>

                <div class="card">
                    <div class="card-header">SESSION</div>
                    <div class="card-body">
                        <div class="text-small">run_id: <span id="run-id">—</span></div>
                        <div class="text-small">Duration: <span id="session-duration">—</span></div>
                    </div>
                </div>
            </div>
        </main>

        <footer>
            <div>
                Endpoints:
                <a href="/health">/health</a> |
                <a href="/latest">/latest</a> |
                <a href="/stream">/stream</a>
            </div>
            <div>v1.0.0 | © 2026</div>
        </footer>

        <!-- Stale Data Overlay -->
        <div id="stale-overlay" class="overlay" style="display:none">
            <div class="overlay-content">
                <div class="overlay-title">⚠️ STALE DATA</div>
                <div class="overlay-message">Last update <span id="stale-age">—</span> seconds ago</div>
                <div class="overlay-checklist">
                    <div>Check:</div>
                    <ul>
                        <li>Phone Wi-Fi connection</li>
                        <li>Collector app running</li>
                        <li>Network path to receiver</li>
                    </ul>
                </div>
            </div>
        </div>
    </div>

    <script src="dashboard.js"></script>
</body>
</html>
```

### File 2: Dashboard JavaScript

**Create:** `server/static/dashboard.js`

```javascript
// Configuration
const POLL_INTERVAL_MS = 500; // 2 Hz per PRD
const STALE_THRESHOLD_MS = 2000; // 2 seconds per PRD
const CHART_HISTORY_SECONDS = 60;

// State
let chart = null;
let chartData = [];
let sessionStartTime = null;

// Initialize chart
function initChart() {
    const ctx = document.getElementById('altitudeChart').getContext('2d');
    chart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: 'Vertical Gain (m)',
                data: [],
                borderColor: '#2563eb',
                backgroundColor: 'rgba(37, 99, 235, 0.1)',
                borderWidth: 2,
                tension: 0.4,
                fill: true
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            scales: {
                x: {
                    display: true,
                    title: {
                        display: true,
                        text: 'Time'
                    }
                },
                y: {
                    display: true,
                    title: {
                        display: true,
                        text: 'Vertical Gain (m)'
                    }
                }
            },
            plugins: {
                legend: {
                    display: false
                }
            }
        }
    });
}

// Update dashboard with new data
function updateDashboard(data) {
    const now = Date.now();
    const dataAge = now - data.ts_unix_ms;

    // Update status badge
    const badge = document.getElementById('status-badge');
    if (dataAge > STALE_THRESHOLD_MS) {
        badge.className = 'badge badge-stale';
        badge.textContent = 'STALE';
        showStaleOverlay(dataAge);
    } else {
        badge.className = 'badge badge-ok';
        badge.textContent = 'DATA OK';
        hideStaleOverlay();
    }

    // Update vertical gain
    const gainM = data.vertical_gain_m || 0;
    const gainFt = gainM * 3.28084;
    document.getElementById('gain-meters').textContent = gainM.toFixed(1);
    document.getElementById('gain-feet').textContent = gainFt.toFixed(1);

    // Update pressure
    document.getElementById('pressure-current').textContent =
        (data.pressure_hpa || 0).toFixed(2);

    if (data.baseline_pressure_hpa) {
        document.getElementById('pressure-baseline').textContent =
            data.baseline_pressure_hpa.toFixed(2) + ' hPa';
    }

    if (data.baseline_set) {
        document.getElementById('baseline-lock').style.display = 'inline';
    }

    // Update timestamp
    const timestamp = new Date(data.ts_unix_ms);
    document.getElementById('last-update-time').textContent =
        timestamp.toLocaleString('en-US', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            fractionalSecondDigits: 3
        });
    document.getElementById('last-update-age').textContent =
        `(${(dataAge / 1000).toFixed(2)} seconds ago)`;

    // Update session info
    if (data.run_id) {
        document.getElementById('run-id').textContent =
            data.run_id.substring(0, 20) + '...';

        if (!sessionStartTime) {
            sessionStartTime = data.ts_unix_ms;
        }
        const durationMs = now - sessionStartTime;
        const hours = Math.floor(durationMs / 3600000);
        const minutes = Math.floor((durationMs % 3600000) / 60000);
        const seconds = Math.floor((durationMs % 60000) / 1000);
        document.getElementById('session-duration').textContent =
            `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
    }

    // Update chart
    updateChart(data);

    // Update clock
    updateClock();
}

function updateChart(data) {
    const now = Date.now();
    const timeLabel = new Date(data.ts_unix_ms).toLocaleTimeString('en-US', {
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    });

    // Add new data point
    chartData.push({
        time: data.ts_unix_ms,
        value: data.vertical_gain_m || 0,
        label: timeLabel
    });

    // Remove data older than 60 seconds
    const cutoffTime = now - (CHART_HISTORY_SECONDS * 1000);
    chartData = chartData.filter(d => d.time >= cutoffTime);

    // Update chart
    chart.data.labels = chartData.map(d => d.label);
    chart.data.datasets[0].data = chartData.map(d => d.value);
    chart.update('none'); // Update without animation for performance
}

function showStaleOverlay(ageMs) {
    const overlay = document.getElementById('stale-overlay');
    const ageSeconds = (ageMs / 1000).toFixed(1);
    document.getElementById('stale-age').textContent = ageSeconds;
    overlay.style.display = 'flex';
}

function hideStaleOverlay() {
    document.getElementById('stale-overlay').style.display = 'none';
}

function updateClock() {
    const now = new Date();
    document.getElementById('time-display').textContent =
        now.toLocaleTimeString('en-US', {
            hour: '2-digit',
            minute: '2-digit'
        });
}

// Polling logic
async function poll() {
    try {
        const response = await fetch('/latest', {
            cache: 'no-store',
            headers: {
                'Cache-Control': 'no-cache'
            }
        });

        if (response.ok) {
            const data = await response.json();
            updateDashboard(data);
        } else if (response.status === 503) {
            // No data yet
            const badge = document.getElementById('status-badge');
            badge.className = 'badge badge-no-data';
            badge.textContent = 'NO DATA';
        }
    } catch (error) {
        console.error('Poll error:', error);
        const badge = document.getElementById('status-badge');
        badge.className = 'badge badge-error';
        badge.textContent = 'ERROR';
    }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initChart();
    updateClock();
    setInterval(updateClock, 1000);

    // Start polling
    poll();
    setInterval(poll, POLL_INTERVAL_MS);
});
```

### File 3: Dashboard CSS

**Create:** `server/static/dashboard.css`

```css
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
    background: #0f172a;
    color: #e2e8f0;
    line-height: 1.6;
}

.container {
    max-width: 1400px;
    margin: 0 auto;
    padding: 2rem;
}

header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
    padding-bottom: 1rem;
    border-bottom: 2px solid #1e293b;
}

h1 {
    font-size: 1.5rem;
    font-weight: 700;
    letter-spacing: 0.05em;
}

.badge {
    padding: 0.5rem 1rem;
    border-radius: 0.5rem;
    font-weight: 600;
    font-size: 0.875rem;
}

.badge-ok {
    background: rgba(34, 197, 94, 0.2);
    color: #22c55e;
}

.badge-stale {
    background: rgba(251, 191, 36, 0.2);
    color: #fbbf24;
}

.badge-no-data {
    background: rgba(148, 163, 184, 0.2);
    color: #94a3b8;
}

.badge-error {
    background: rgba(239, 68, 68, 0.2);
    color: #ef4444;
}

#time-display {
    font-size: 1.25rem;
    font-weight: 500;
    color: #94a3b8;
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 1.5rem;
    margin-bottom: 1.5rem;
}

.info-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 1.5rem;
    margin-top: 1.5rem;
}

.card {
    background: #1e293b;
    border-radius: 0.75rem;
    padding: 1.5rem;
    border: 1px solid #334155;
}

.card-primary {
    border-color: #2563eb;
    background: linear-gradient(135deg, #1e293b 0%, #1e3a5f 100%);
}

.card-chart {
    grid-column: 1 / -1;
    height: 400px;
}

.card-header {
    font-size: 0.75rem;
    font-weight: 700;
    letter-spacing: 0.1em;
    color: #94a3b8;
    margin-bottom: 1rem;
}

.card-body {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
}

.value-large {
    font-size: 4rem;
    font-weight: 700;
    line-height: 1;
    color: #3b82f6;
}

.value-medium {
    font-size: 2.5rem;
    font-weight: 600;
    line-height: 1;
}

.value-secondary {
    font-size: 2rem;
    font-weight: 600;
    color: #64748b;
}

.value-unit {
    font-size: 0.875rem;
    color: #64748b;
    text-transform: uppercase;
    letter-spacing: 0.05em;
}

.baseline-info {
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid #334155;
    font-size: 0.875rem;
    color: #94a3b8;
}

.lock-icon {
    margin-left: 0.5rem;
    font-size: 1rem;
}

.text-secondary {
    color: #64748b;
    font-size: 0.875rem;
}

.text-small {
    font-size: 0.875rem;
    margin-bottom: 0.5rem;
    color: #94a3b8;
}

.text-small span {
    color: #e2e8f0;
    font-family: monospace;
}

footer {
    margin-top: 2rem;
    padding-top: 1rem;
    border-top: 1px solid #1e293b;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 0.875rem;
    color: #64748b;
}

footer a {
    color: #3b82f6;
    text-decoration: none;
}

footer a:hover {
    text-decoration: underline;
}

/* Stale Overlay */
.overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(15, 23, 42, 0.95);
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 1000;
}

.overlay-content {
    background: #1e293b;
    padding: 3rem;
    border-radius: 1rem;
    border: 2px solid #fbbf24;
    max-width: 500px;
    text-align: center;
}

.overlay-title {
    font-size: 2rem;
    font-weight: 700;
    color: #fbbf24;
    margin-bottom: 1rem;
}

.overlay-message {
    font-size: 1.25rem;
    margin-bottom: 2rem;
}

.overlay-checklist {
    text-align: left;
    background: #0f172a;
    padding: 1.5rem;
    border-radius: 0.5rem;
}

.overlay-checklist ul {
    list-style: none;
    padding-left: 0;
}

.overlay-checklist li {
    padding: 0.5rem 0;
    padding-left: 1.5rem;
    position: relative;
}

.overlay-checklist li::before {
    content: '•';
    position: absolute;
    left: 0.5rem;
    color: #3b82f6;
    font-weight: bold;
}

/* Chart container */
.card-chart .card-body {
    height: calc(100% - 3rem);
}

#altitudeChart {
    height: 100% !important;
}
```

### File 4: Mount Static Files in FastAPI

**File:** `server/app.py`

Add import:
```python
from fastapi.staticfiles import StaticFiles
```

Add after `app` initialization:
```python
app = FastAPI()

# Mount static files for dashboard
from pathlib import Path
static_path = Path(__file__).parent / "static"
static_path.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_path)), name="static")
```

Add dashboard route:
```python
@app.get("/dashboard")
async def dashboard():
    """Serve dashboard HTML per PRD FR-R-005"""
    from fastapi.responses import FileResponse
    static_path = Path(__file__).parent / "static" / "dashboard.html"
    return FileResponse(static_path)
```

---

## Testing Commands

### Test Server Locally

```bash
# Start server
cd server
uvicorn app:app --host 0.0.0.0 --port 8787 --reload

# Test health endpoint
curl http://localhost:8787/health | jq

# Test ingest (with authentication)
curl -X POST http://localhost:8787/ingest \
  -H "Authorization: Bearer your_secure_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "run_id": "2026-01-21T10:00:00Z_test",
    "device_id": "test-device",
    "ts_unix_ms": 1737450000000,
    "vertical_gain_m": 10.5,
    "pressure_hpa": 1013.25,
    "baseline_pressure_hpa": 1015.0,
    "baseline_set": true,
    "status": "ok"
  }'

# Test latest endpoint
curl http://localhost:8787/latest | jq

# View dashboard
open http://localhost:8787/dashboard
```

### Test iOS App Updates

1. Open Xcode project
2. Clean build folder (Cmd+Shift+K)
3. Build and run on device
4. Check Xcode console for pressure values (should show hPa, not kPa)
5. Verify payload in server logs matches new schema

---

## Deployment Checklist

- [ ] Phase 1 server fixes applied and tested
- [ ] iOS app updated (if using iOS path)
- [ ] Dashboard files created and tested locally
- [ ] Server can bind to 0.0.0.0:8787
- [ ] Dashboard accessible at http://<server-ip>:8787/dashboard
- [ ] /latest endpoint returns new schema
- [ ] /health shows proper status (ok/stale/no_data)
- [ ] Chart displays and updates every 500ms
- [ ] Stale warning appears after 2 seconds
- [ ] Units display correctly (meters + feet, hPa)
- [ ] Mobile app sends data successfully
- [ ] No console errors in browser

---

**Next Steps:**
1. Apply Phase 1 fixes (8 hours)
2. Test with updated iOS app OR begin Android development
3. Validate with graphics team that /latest endpoint works
4. Conduct pre-climb connectivity test
5. Full E2E test with lock screen, Bluetooth devices active

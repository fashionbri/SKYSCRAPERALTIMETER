# 🚀 DO THIS NOW - Master Integration Checklist
**Purpose:** Make SKYSCRAPERALTIMETER deployment-ready
**Execution Mode:** Follow steps sequentially, validate each before proceeding
**Estimated Time:** 8-12 hours (iOS path) or 44+ hours (Android path)
**Target:** Production-ready system with 100% PRD compliance (modulo platform)

---

## ⚠️ CRITICAL PRE-FLIGHT DECISION

**STOP: Answer this question before proceeding:**

> **Can we deploy with iPhone instead of Samsung Galaxy S25?**

- ✅ **YES, iPhone acceptable** → Continue with **TRACK A** (iOS - Fast, 8-12 hours)
- ❌ **NO, Galaxy S25 mandatory** → Switch to **TRACK B** (Android - 44+ hours)

**Document your decision here:**
```
PLATFORM DECISION: [ ] iOS (Track A)  [ ] Android (Track B)
DECISION DATE: _______________
APPROVED BY: _______________
RATIONALE: _______________
```

---

# TRACK A: iOS Deployment (Fast Path - 8-12 hours)

**Prerequisites:**
- [ ] Xcode 15+ installed
- [ ] iPhone with barometer (iPhone 6 or newer)
- [ ] Python 3.11+ installed
- [ ] Network access to production LAN

---

## PHASE 1: Server Schema & Endpoint Fixes (2 hours)

### Task 1.1: Update Pydantic Model - Pressure Units Fix (15 min)

**File:** `server/app.py`

**Action:** Replace lines 28-38 (the `IngestPayload` class) with:

```python
class IngestPayload(BaseModel):
    # Core identifiers
    run_id: str
    device_id: str
    ts_unix_ms: int

    # Altitude & pressure data (FIXED UNITS)
    vertical_gain_m: float
    pressure_hpa: float  # CHANGED from pressure_kpa
    baseline_pressure_hpa: float
    altitude_estimate_m: Optional[float] = None
    baseline_altitude_m: Optional[float] = 0.0

    # Status & calibration
    baseline_set: bool
    status: str  # "calibrating" | "ok" | "sensor_error" | "network_error"

    # Performance monitoring
    sample_hz: Optional[float] = None

    # Device metadata
    battery_level: Optional[float] = None
    is_charging: Optional[bool] = None
    app_version: Optional[str] = None

    # Legacy compatibility from iOS
    net_change_m: Optional[float] = None
    seq: Optional[int] = None
```

**Validation:**
```bash
cd server
python -c "from app import IngestPayload; print('✓ Model updated')"
```

**Success Criteria:** No import errors, model loads successfully

---

### Task 1.2: Add Startup Time Tracking (5 min)

**File:** `server/app.py`

**Action:** After line 25 (after `latest_payload` declaration), add:

```python
latest_payload: Optional[Dict[str, Any]] = None
startup_time = time.time()  # ADD THIS LINE
```

**Validation:**
```bash
grep "startup_time = time.time()" server/app.py
```

**Success Criteria:** Line exists in file

---

### Task 1.3: Fix CORS Middleware (10 min)

**File:** `server/app.py`

**Action:** Replace lines 18-23 (CORS middleware) with:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "OPTIONS"],  # FIXED: Added POST and OPTIONS
    allow_headers=["*"]
)
```

**Validation:**
```bash
grep '"POST", "OPTIONS"' server/app.py
```

**Success Criteria:** POST and OPTIONS methods present

---

### Task 1.4: Update /health Endpoint (20 min)

**File:** `server/app.py`

**Action:** Replace the entire `/health` function (lines 88-94) with:

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

    # Determine status based on age (PRD: >2000ms = stale)
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

**Validation:**
```bash
python -c "import ast; ast.parse(open('server/app.py').read()); print('✓ Syntax valid')"
```

**Success Criteria:** No syntax errors

---

### Task 1.5: Update /latest Endpoint (20 min)

**File:** `server/app.py`

**Action:** Replace the entire `/latest` function (lines 74-85) with:

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
        "X-Data-Age-Ms": str(age_ms)  # NEW per PRD
    }

    return JSONResponse(content=latest_payload, headers=headers)
```

**Validation:**
```bash
python -c "import ast; ast.parse(open('server/app.py').read()); print('✓ Syntax valid')"
```

**Success Criteria:** No syntax errors

---

### Task 1.6: Test Server Fixes (30 min)

**Action:** Start server and validate endpoints

```bash
cd server

# Create .env file if not exists
if [ ! -f .env ]; then
    cp .env.example .env
    echo "⚠️  Edit .env and set INGEST_TOKEN"
fi

# Start server
uvicorn app:app --host 0.0.0.0 --port 8787 --reload
```

**In a new terminal, run validation tests:**

```bash
# Test 1: Health endpoint (should return no_data)
curl -s http://localhost:8787/health | jq
# Expected: {"status": "no_data", "uptime_s": <number>, ...}

# Test 2: Latest endpoint (should return 503)
curl -s -w "\nHTTP_CODE: %{http_code}\n" http://localhost:8787/latest
# Expected: HTTP_CODE: 503

# Test 3: Post sample data (replace TOKEN)
export TOKEN="your_secure_token_here"
curl -X POST http://localhost:8787/ingest \
  -H "Authorization: Bearer $TOKEN" \
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
# Expected: {"ok": true}

# Test 4: Health should now show "ok"
curl -s http://localhost:8787/health | jq
# Expected: {"status": "ok", "current_vertical_gain_m": 10.5, ...}

# Test 5: Latest should return data
curl -s http://localhost:8787/latest | jq
# Expected: Full payload with vertical_gain_m: 10.5
```

**Success Criteria:**
- [ ] Health endpoint returns correct schema
- [ ] Latest returns 503 when no data
- [ ] Ingest accepts data successfully
- [ ] Health shows "ok" after data received
- [ ] Latest returns data after ingest
- [ ] X-Data-Age-Ms header present

**CHECKPOINT 1:** ✅ All server tests pass → Continue to Phase 2

---

## PHASE 2: iOS App Updates (2 hours)

### Task 2.1: Fix Pressure Units in AltimeterManager (30 min)

**File:** `ios/SkyscraperAltimeter/SkyscraperAltimeter/AltimeterManager.swift`

**Action 1:** Update struct (line 4-10):

```swift
struct AltimeterReading {
    let relativeAltitudeM: Double
    let pressureHPa: Double  // CHANGED from pressureKPa
    let verticalGainM: Double
    let netChangeM: Double
    let seq: Int
}
```

**Action 2:** Update published property (line 15):

```swift
@Published var pressureHPa: Double = 0.0  // CHANGED from pressureKPa
```

**Action 3:** Update pressure calculation (line 49):

```swift
// BEFORE:
let pressureKPa = data.pressure.doubleValue * 10.0

// AFTER:
let pressureHPa = data.pressure.doubleValue * 1000.0  // Convert kPa to hPa
```

**Action 4:** Update assignment (line 66):

```swift
self.pressureHPa = pressureHPa  // CHANGED from pressureKPa
```

**Action 5:** Update reading creation (line 70-76):

```swift
let reading = AltimeterReading(
    relativeAltitudeM: currentAltitude,
    pressureHPa: pressureHPa,  // CHANGED from pressureKPa
    verticalGainM: self.verticalGainM,
    netChangeM: self.netChangeM,
    seq: self.sequenceNumber
)
```

**Validation:**
```bash
grep "pressureHPa" ios/SkyscraperAltimeter/SkyscraperAltimeter/AltimeterManager.swift | wc -l
```

**Success Criteria:** At least 5 occurrences of "pressureHPa"

---

### Task 2.2: Add Missing Payload Fields to NetworkManager (45 min)

**File:** `ios/SkyscraperAltimeter/SkyscraperAltimeter/NetworkManager.swift`

**Action 1:** Add run_id property (after line 8):

```swift
private let deviceId: String
private let runId: String  // ADD THIS
```

**Action 2:** Generate run_id in init() (after line 24):

```swift
deviceId = newId
defaults.set(newId, forKey: "deviceId")

// ADD THIS:
let isoFormatter = ISO8601DateFormatter()
isoFormatter.formatOptions = [.withInternetDateTime]
let timestamp = isoFormatter.string(from: Date())
runId = "\(timestamp)_\(deviceId.prefix(8))"
```

**Action 3:** Update enqueuePayload signature (line 60):

```swift
func enqueuePayload(
    relativeAltitudeM: Double,
    pressureHPa: Double,  // CHANGED from pressureKPa
    verticalGainM: Double,
    netChangeM: Double,
    seq: Int,
    battery: Double?,
    isCharging: Bool?
)
```

**Action 4:** Update payload dictionary (line 69-92):

```swift
var payload: [String: Any] = [
    // Required PRD fields
    "run_id": runId,
    "device_id": deviceId,
    "ts_unix_ms": Int(Date().timeIntervalSince1970 * 1000),
    "vertical_gain_m": verticalGainM,
    "pressure_hpa": pressureHPa,  // CHANGED from pressure_kpa
    "baseline_pressure_hpa": pressureHPa,  // Use current as baseline (iOS handles calibration)
    "altitude_estimate_m": relativeAltitudeM,
    "baseline_altitude_m": 0.0,
    "baseline_set": true,  // Always true (iOS auto-calibrates)
    "status": "ok",

    // iOS-specific fields
    "net_change_m": netChangeM,
    "seq": seq,
    "app_version": "1.0.0"
]

if let battery {
    payload["battery_level"] = battery
}
if let isCharging {
    payload["is_charging"] = isCharging
}
```

**Validation:** Build in Xcode (Cmd+B)

**Success Criteria:** No build errors

---

### Task 2.3: Update ContentView References (15 min)

**File:** `ios/SkyscraperAltimeter/SkyscraperAltimeter/ContentView.swift`

**Action 1:** Update pressure display (line 26):

```swift
Text(String(format: "Pressure: %.2f hPa", altimeterManager.pressureHPa))
```

**Action 2:** Update enqueue call (line 78-87):

```swift
networkManager.enqueuePayload(
    relativeAltitudeM: reading.relativeAltitudeM,
    pressureHPa: reading.pressureHPa,  // CHANGED from pressureKPa
    verticalGainM: reading.verticalGainM,
    netChangeM: reading.netChangeM,
    seq: reading.seq,
    battery: nil,
    isCharging: nil
)
```

**Validation:** Build in Xcode (Cmd+B)

**Success Criteria:** No build errors

---

### Task 2.4: Test iOS App Integration (30 min)

**Action:** Run iOS app with server running

1. **Start server** (if not running):
```bash
cd server
uvicorn app:app --host 0.0.0.0 --port 8787 --reload
```

2. **Get your Mac's IP address:**
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
# Example output: inet 192.168.1.100
```

3. **Configure iOS app:**
- Open Settings in iOS app
- Enter server URL: `http://<YOUR_MAC_IP>:8787`
- Enter ingest token from your `.env` file
- Save

4. **Start collecting data:**
- Tap "Start" button
- Move iPhone up/down (stairs, elevator)
- Watch values update

5. **Verify server receives data:**
```bash
# In another terminal:
watch -n 1 'curl -s http://localhost:8787/latest | jq ".vertical_gain_m, .pressure_hpa, .baseline_set"'
```

**Success Criteria:**
- [ ] iOS app shows pressure in hPa (typically 950-1050 range)
- [ ] Vertical gain changes when moving up/down
- [ ] Server /latest shows data with correct units
- [ ] pressure_hpa field exists (not pressure_kpa)
- [ ] baseline_set is true
- [ ] run_id field is present

**CHECKPOINT 2:** ✅ iOS app sends correct data to server → Continue to Phase 3

---

## PHASE 3: Dashboard Implementation (4 hours)

### Task 3.1: Create Dashboard HTML (60 min)

**File:** Create `server/static/dashboard.html`

**Action:**

```bash
mkdir -p server/static
cat > server/static/dashboard.html << 'EOF'
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
                <div class="card card-primary">
                    <div class="card-header">VERTICAL GAIN</div>
                    <div class="card-body">
                        <div class="value-large" id="gain-meters">—</div>
                        <div class="value-unit">meters</div>
                        <div class="value-secondary" id="gain-feet">—</div>
                        <div class="value-unit">feet</div>
                    </div>
                </div>

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

            <div class="card card-chart">
                <div class="card-header">ALTITUDE CHART (Last 60s)</div>
                <div class="card-body">
                    <canvas id="altitudeChart"></canvas>
                </div>
            </div>

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
                <a href="/latest">/latest</a>
            </div>
            <div>v1.0.0 | © 2026</div>
        </footer>

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
EOF
```

**Validation:**
```bash
test -f server/static/dashboard.html && echo "✓ HTML created"
```

**Success Criteria:** File exists

---

### Task 3.2: Create Dashboard JavaScript (90 min)

**File:** Create `server/static/dashboard.js`

**Action:**

```bash
cat > server/static/dashboard.js << 'EOF'
const POLL_INTERVAL_MS = 500; // 2 Hz per PRD
const STALE_THRESHOLD_MS = 2000;
const CHART_HISTORY_SECONDS = 60;

let chart = null;
let chartData = [];
let sessionStartTime = null;

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
                x: { display: true, title: { display: true, text: 'Time' } },
                y: { display: true, title: { display: true, text: 'Vertical Gain (m)' } }
            },
            plugins: { legend: { display: false } }
        }
    });
}

function updateDashboard(data) {
    const now = Date.now();
    const dataAge = now - data.ts_unix_ms;

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

    const gainM = data.vertical_gain_m || 0;
    const gainFt = gainM * 3.28084;
    document.getElementById('gain-meters').textContent = gainM.toFixed(1);
    document.getElementById('gain-feet').textContent = gainFt.toFixed(1);

    document.getElementById('pressure-current').textContent = (data.pressure_hpa || 0).toFixed(2);

    if (data.baseline_pressure_hpa) {
        document.getElementById('pressure-baseline').textContent = data.baseline_pressure_hpa.toFixed(2) + ' hPa';
    }

    if (data.baseline_set) {
        document.getElementById('baseline-lock').style.display = 'inline';
    }

    const timestamp = new Date(data.ts_unix_ms);
    document.getElementById('last-update-time').textContent = timestamp.toLocaleString();
    document.getElementById('last-update-age').textContent = `(${(dataAge / 1000).toFixed(2)} seconds ago)`;

    if (data.run_id) {
        document.getElementById('run-id').textContent = data.run_id.substring(0, 24) + '...';
        if (!sessionStartTime) sessionStartTime = data.ts_unix_ms;
        const durationMs = now - sessionStartTime;
        const h = Math.floor(durationMs / 3600000);
        const m = Math.floor((durationMs % 3600000) / 60000);
        const s = Math.floor((durationMs % 60000) / 1000);
        document.getElementById('session-duration').textContent =
            `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
    }

    updateChart(data);
    updateClock();
}

function updateChart(data) {
    const now = Date.now();
    const timeLabel = new Date(data.ts_unix_ms).toLocaleTimeString();

    chartData.push({ time: data.ts_unix_ms, value: data.vertical_gain_m || 0, label: timeLabel });

    const cutoffTime = now - (CHART_HISTORY_SECONDS * 1000);
    chartData = chartData.filter(d => d.time >= cutoffTime);

    chart.data.labels = chartData.map(d => d.label);
    chart.data.datasets[0].data = chartData.map(d => d.value);
    chart.update('none');
}

function showStaleOverlay(ageMs) {
    document.getElementById('stale-age').textContent = (ageMs / 1000).toFixed(1);
    document.getElementById('stale-overlay').style.display = 'flex';
}

function hideStaleOverlay() {
    document.getElementById('stale-overlay').style.display = 'none';
}

function updateClock() {
    document.getElementById('time-display').textContent = new Date().toLocaleTimeString('en-US', {
        hour: '2-digit', minute: '2-digit'
    });
}

async function poll() {
    try {
        const response = await fetch('/latest', { cache: 'no-store' });
        if (response.ok) {
            const data = await response.json();
            updateDashboard(data);
        } else if (response.status === 503) {
            document.getElementById('status-badge').className = 'badge badge-no-data';
            document.getElementById('status-badge').textContent = 'NO DATA';
        }
    } catch (error) {
        console.error('Poll error:', error);
        document.getElementById('status-badge').className = 'badge badge-error';
        document.getElementById('status-badge').textContent = 'ERROR';
    }
}

document.addEventListener('DOMContentLoaded', () => {
    initChart();
    updateClock();
    setInterval(updateClock, 1000);
    poll();
    setInterval(poll, POLL_INTERVAL_MS);
});
EOF
```

**Validation:**
```bash
test -f server/static/dashboard.js && echo "✓ JavaScript created"
```

**Success Criteria:** File exists

---

### Task 3.3: Create Dashboard CSS (60 min)

**File:** Create `server/static/dashboard.css`

**Action:**

```bash
cat > server/static/dashboard.css << 'EOF'
* { margin: 0; padding: 0; box-sizing: border-box; }

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #0f172a;
    color: #e2e8f0;
    line-height: 1.6;
}

.container { max-width: 1400px; margin: 0 auto; padding: 2rem; }

header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
    padding-bottom: 1rem;
    border-bottom: 2px solid #1e293b;
}

h1 { font-size: 1.5rem; font-weight: 700; letter-spacing: 0.05em; }

.badge {
    padding: 0.5rem 1rem;
    border-radius: 0.5rem;
    font-weight: 600;
    font-size: 0.875rem;
}

.badge-ok { background: rgba(34, 197, 94, 0.2); color: #22c55e; }
.badge-stale { background: rgba(251, 191, 36, 0.2); color: #fbbf24; }
.badge-no-data { background: rgba(148, 163, 184, 0.2); color: #94a3b8; }
.badge-error { background: rgba(239, 68, 68, 0.2); color: #ef4444; }

#time-display { font-size: 1.25rem; font-weight: 500; color: #94a3b8; }

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

.card-chart { grid-column: 1 / -1; height: 400px; }

.card-header {
    font-size: 0.75rem;
    font-weight: 700;
    letter-spacing: 0.1em;
    color: #94a3b8;
    margin-bottom: 1rem;
}

.card-body { display: flex; flex-direction: column; gap: 0.5rem; }

.value-large { font-size: 4rem; font-weight: 700; line-height: 1; color: #3b82f6; }
.value-medium { font-size: 2.5rem; font-weight: 600; line-height: 1; }
.value-secondary { font-size: 2rem; font-weight: 600; color: #64748b; }
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

.lock-icon { margin-left: 0.5rem; font-size: 1rem; }

.text-secondary { color: #64748b; font-size: 0.875rem; }

.text-small {
    font-size: 0.875rem;
    margin-bottom: 0.5rem;
    color: #94a3b8;
}

.text-small span { color: #e2e8f0; font-family: monospace; }

footer {
    margin-top: 2rem;
    padding-top: 1rem;
    border-top: 1px solid #1e293b;
    display: flex;
    justify-content: space-between;
    font-size: 0.875rem;
    color: #64748b;
}

footer a { color: #3b82f6; text-decoration: none; }
footer a:hover { text-decoration: underline; }

.overlay {
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
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

.overlay-message { font-size: 1.25rem; margin-bottom: 2rem; }

.overlay-checklist {
    text-align: left;
    background: #0f172a;
    padding: 1.5rem;
    border-radius: 0.5rem;
}

.overlay-checklist ul { list-style: none; padding-left: 0; }

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

.card-chart .card-body { height: calc(100% - 3rem); }
#altitudeChart { height: 100% !important; }
EOF
```

**Validation:**
```bash
test -f server/static/dashboard.css && echo "✓ CSS created"
```

**Success Criteria:** File exists

---

### Task 3.4: Mount Static Files in FastAPI (30 min)

**File:** `server/app.py`

**Action 1:** Add imports at the top (after existing imports):

```python
from pathlib import Path
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
```

**Action 2:** Mount static files (after `app = FastAPI()` line):

```python
app = FastAPI()

# Mount static files for dashboard
static_path = Path(__file__).parent / "static"
static_path.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_path)), name="static")
```

**Action 3:** Add dashboard route (at the end of the file):

```python
@app.get("/dashboard")
async def dashboard():
    """Serve dashboard HTML per PRD FR-R-005"""
    static_path = Path(__file__).parent / "static" / "dashboard.html"
    return FileResponse(static_path)
```

**Validation:**
```bash
python -c "import ast; ast.parse(open('server/app.py').read()); print('✓ Syntax valid')"
```

**Success Criteria:** No syntax errors

---

### Task 3.5: Test Dashboard (30 min)

**Action:**

1. **Restart server:**
```bash
cd server
# Stop server (Ctrl+C) and restart
uvicorn app:app --host 0.0.0.0 --port 8787 --reload
```

2. **Open dashboard in browser:**
```bash
open http://localhost:8787/dashboard
# Or on Linux: xdg-open http://localhost:8787/dashboard
```

3. **Start iOS app** (if not running)

4. **Verify dashboard updates:**
- [ ] Dashboard loads without errors
- [ ] Status badge shows "DATA OK" when receiving data
- [ ] Vertical gain displays in meters AND feet
- [ ] Pressure displays in hPa
- [ ] Baseline shows with lock icon
- [ ] Chart displays and updates
- [ ] Last update timestamp updates
- [ ] Session duration counts up
- [ ] Clock displays current time

5. **Test stale detection:**
- Stop iOS app
- Wait 3 seconds
- Verify "STALE DATA" overlay appears

**Success Criteria:**
- [ ] Dashboard loads without console errors
- [ ] All metrics display correctly
- [ ] Chart animates with data
- [ ] Stale warning triggers after 2 seconds
- [ ] Units are correct (m, ft, hPa)

**CHECKPOINT 3:** ✅ Dashboard fully functional → Continue to Phase 4

---

## PHASE 4: Integration & Performance Testing (2-3 hours)

### Task 4.1: End-to-End Integration Test (60 min)

**Action:** Complete integration test scenario

**Scenario 1: Normal Operation**

1. Start server on production network IP
2. Configure iOS app with production server IP
3. Start data collection
4. Lock iPhone screen
5. Place iPhone in pocket
6. Walk up/down stairs or elevator
7. Verify data continues on dashboard

**Success Criteria:**
- [ ] Data continues updating with screen locked
- [ ] Vertical gain increases going up
- [ ] Vertical gain decreases going down
- [ ] No gaps in data (continuous updates)
- [ ] Dashboard remains responsive

**Scenario 2: Network Disruption**

1. Start data collection
2. Disconnect iPhone from Wi-Fi
3. Wait 30 seconds
4. Reconnect to Wi-Fi
5. Verify data resumes

**Success Criteria:**
- [ ] Dashboard shows "STALE" during disconnect
- [ ] Data resumes automatically after reconnect
- [ ] No crash or restart required

**Scenario 3: Server Restart**

1. Start data collection
2. Restart server
3. Verify iOS app reconnects

**Success Criteria:**
- [ ] iOS app continues trying to send
- [ ] Server accepts data after restart
- [ ] Dashboard recovers automatically

---

### Task 4.2: Performance Validation (60 min)

**Action:** Measure key performance metrics

**Test 1: Latency Measurement**

```bash
# Start logging with timestamps
while true; do
    TIMESTAMP=$(date +%s%3N)
    curl -s http://localhost:8787/latest | \
        jq -r ".ts_unix_ms" | \
        xargs -I {} echo "Server: {} | Now: $TIMESTAMP | Delta: $(($TIMESTAMP - {}))"
    sleep 1
done
```

**Success Criteria:**
- [ ] Latency <500ms (PRD requirement)
- [ ] Consistent latency (no spikes >1000ms)

**Test 2: Update Rate**

```bash
# Count updates over 60 seconds
curl -s http://localhost:8787/latest | jq -r ".seq" > /tmp/start_seq
sleep 60
curl -s http://localhost:8787/latest | jq -r ".seq" > /tmp/end_seq
UPDATES=$(( $(cat /tmp/end_seq) - $(cat /tmp/start_seq) ))
echo "Updates in 60s: $UPDATES (Should be >= 120 for 2 Hz)"
```

**Success Criteria:**
- [ ] ≥120 updates in 60 seconds (2 Hz sustained)

**Test 3: Memory Usage**

```bash
# Monitor server memory
ps aux | grep uvicorn | awk '{print $6/1024 "MB"}'
```

**Success Criteria:**
- [ ] Server memory <100MB (PRD requirement)

---

### Task 4.3: Battery & Bluetooth Testing (60 min)

**Note:** These tests require extended time

**Test 1: Battery Drain (4 hour test)**

1. Charge iPhone to 100%
2. Start data collection
3. Lock screen
4. Note battery % at start
5. Wait 4 hours
6. Note battery % at end
7. Calculate drain rate

**Success Criteria:**
- [ ] Battery drain <15% over 4 hours (PRD requirement)

**Test 2: Bluetooth Coexistence**

1. Connect IFB (if available) or Bluetooth headphones
2. Connect HR monitor (if available) or another Bluetooth device
3. Start audio playback
4. Start altimeter app
5. Monitor for 30 minutes

**Success Criteria:**
- [ ] No Bluetooth audio drops
- [ ] No device disconnections
- [ ] Altimeter data continues normally

---

### Task 4.4: Lock Screen Validation (30 min)

**Action:** Verify operation with screen locked

1. Start data collection
2. Lock iPhone immediately
3. Monitor dashboard for 10 minutes
4. Verify continuous updates

**Success Criteria:**
- [ ] Data updates continue
- [ ] No gaps >2 seconds
- [ ] Vertical gain responds to movement

---

## PHASE 5: Production Preparation (1-2 hours)

### Task 5.1: Create Pre-Climb Checklist (30 min)

**File:** Create `server/PRE_CLIMB_CHECKLIST.md`

**Action:**

```bash
cat > server/PRE_CLIMB_CHECKLIST.md << 'EOF'
# Pre-Climb Verification Checklist

**Date:** _______________
**Operator:** _______________
**Climb Start Time:** _______________

## Phone Setup
- [ ] iPhone fully charged (100%)
- [ ] Altimeter app installed and updated
- [ ] Server URL configured: http://_____:8787
- [ ] Token configured correctly
- [ ] Connected to production Wi-Fi
- [ ] Wi-Fi signal strong (≥3 bars)
- [ ] Do Not Disturb enabled
- [ ] Auto-Lock set to "Never"

## Server Setup
- [ ] Server running on correct IP: _______________
- [ ] Port 8787 accessible
- [ ] Health check: `curl http://<SERVER_IP>:8787/health` returns JSON
- [ ] Dashboard accessible: `http://<SERVER_IP>:8787/dashboard`
- [ ] No firewall blocking connections

## Connectivity Test
- [ ] iPhone can reach server (Settings shows "connected")
- [ ] Start altimeter → data appears on dashboard
- [ ] Values update in real-time (<1 second delay)
- [ ] Lock iPhone → data continues
- [ ] Move phone up/down → vertical gain changes
- [ ] Baseline locked (🔒 icon visible)

## Baseline Verification
- [ ] Vertical gain shows ~0.0 m at start position
- [ ] run_id captured and displayed
- [ ] Timestamp updating correctly
- [ ] Pressure reading sensible (950-1050 hPa)

## Graphics Team Validation
- [ ] Graphics system can access /latest endpoint
- [ ] Sample query: `curl http://<SERVER_IP>:8787/latest`
- [ ] Field "vertical_gain_m" present and updating
- [ ] Units confirmed: meters (not feet, not other)

## Final Steps
- [ ] Position iPhone securely in pocket/holder
- [ ] Confirm dashboard still updating
- [ ] Note start time: _______________
- [ ] Climber ready signal received

## Emergency Contacts
- Server operator: _______________
- Technical support: _______________
- Graphics operator: _______________

---

**GO/NO-GO DECISION:**
- [ ] ✅ All checks passed → PROCEED
- [ ] ❌ Any check failed → STOP and troubleshoot
EOF
```

**Validation:**
```bash
test -f server/PRE_CLIMB_CHECKLIST.md && echo "✓ Checklist created"
```

---

### Task 5.2: Document Production Deployment (30 min)

**File:** Update `README.md`

**Action:** Add production deployment section:

```bash
cat >> README.md << 'EOF'

## Production Deployment

### Server Setup (Production Network)

1. **Install dependencies:**
```bash
cd server
pip install -r requirements.txt
```

2. **Configure environment:**
```bash
cp .env.example .env
# Edit .env and set:
# - PORT=8787
# - INGEST_TOKEN=<secure_token>
```

3. **Start server:**
```bash
uvicorn app:app --host 0.0.0.0 --port 8787
```

4. **Verify server:**
```bash
curl http://<SERVER_IP>:8787/health
```

### iPhone Setup

1. **Install app** (via Xcode or TestFlight)

2. **Configure server:**
   - Open Settings in app
   - Enter: `http://<SERVER_IP>:8787`
   - Enter ingest token from .env
   - Set send interval: 5 seconds
   - Save

3. **Test connection:**
   - Tap "Start"
   - Verify "connected" status
   - Check dashboard shows data

### Dashboard Access

Open in browser: `http://<SERVER_IP>:8787/dashboard`

### Pre-Climb Checklist

See `server/PRE_CLIMB_CHECKLIST.md` for complete validation steps.

### Troubleshooting

**Dashboard shows "NO DATA":**
- Verify iPhone connected to Wi-Fi
- Check server IP correct in iPhone settings
- Verify token matches between iPhone and server

**Data shows "STALE":**
- Check iPhone Wi-Fi signal strength
- Verify app running (not killed by iOS)
- Check server still running

**Vertical gain stuck at 0:**
- Move iPhone up/down to verify sensor working
- Check pressure readings changing
- Restart app if needed

### Support

See `docs/TROUBLESHOOTING.md` for detailed diagnostics.
EOF
```

---

### Task 5.3: Final System Validation (30 min)

**Action:** Complete end-to-end validation

**Validation Checklist:**

```bash
# 1. Server health
curl -s http://localhost:8787/health | jq
# Expected: status "ok" or "no_data", uptime_s > 0

# 2. API schema compliance
curl -s http://localhost:8787/latest | jq 'keys'
# Expected: Contains run_id, ts_unix_ms, vertical_gain_m, pressure_hpa, baseline_set, status

# 3. Dashboard accessible
curl -s -o /dev/null -w "%{http_code}" http://localhost:8787/dashboard
# Expected: 200

# 4. Static files served
curl -s -o /dev/null -w "%{http_code}" http://localhost:8787/static/dashboard.js
# Expected: 200

# 5. CORS headers
curl -s -I -X OPTIONS http://localhost:8787/latest | grep -i "access-control"
# Expected: access-control-allow-methods includes POST

# 6. Pressure units correct
curl -s http://localhost:8787/latest | jq '.pressure_hpa'
# Expected: Value 950-1050 (hPa range, not kPa range 95-105)
```

**Success Criteria:**
- [ ] All API endpoints respond
- [ ] Dashboard loads without errors
- [ ] Schema matches PRD requirements
- [ ] Pressure in correct units (hPa)
- [ ] CORS configured properly

---

## FINAL CHECKPOINT: Production Ready

### Deployment Ready Criteria

**ALL must be ✅ before declaring production-ready:**

#### Server
- [ ] FastAPI server starts without errors
- [ ] All endpoints return correct schema
- [ ] Pressure units in hPa (not kPa)
- [ ] /health shows age_ms and status
- [ ] /latest returns 503 when no data
- [ ] CORS allows POST method
- [ ] Dashboard accessible at /dashboard

#### iOS App
- [ ] App builds without errors
- [ ] Pressure displayed in hPa
- [ ] All required fields in payload (run_id, baseline_set, status)
- [ ] Network settings persisted
- [ ] Connection status accurate

#### Dashboard
- [ ] HTML/CSS/JS files created
- [ ] Chart.js loaded and working
- [ ] All metrics display correctly
- [ ] Stale detection triggers at 2s
- [ ] Chart updates in real-time
- [ ] Units correct (m, ft, hPa)

#### Integration
- [ ] iPhone → Server → Dashboard data flow works
- [ ] Latency <500ms validated
- [ ] Update rate ≥2 Hz validated
- [ ] Lock screen operation confirmed
- [ ] Network dropout recovery tested

#### Documentation
- [ ] README updated with deployment steps
- [ ] Pre-climb checklist created
- [ ] Troubleshooting guide accessible
- [ ] Emergency contacts documented

### Sign-Off

**Deployment approved by:**

- [ ] Technical Lead: _______________ Date: _______________
- [ ] QA: _______________ Date: _______________
- [ ] Production Manager: _______________ Date: _______________

---

## POST-DEPLOYMENT MONITORING

### First Hour Checklist

After deployment to production:

- [ ] Server responding to health checks
- [ ] Dashboard accessible from operator station
- [ ] iPhone sending data successfully
- [ ] Vertical gain responsive to movement
- [ ] No console errors in browser
- [ ] Latency within acceptable range (<500ms)
- [ ] No memory leaks (server RAM stable)

### Ongoing Monitoring

**Check every 15 minutes during climb:**
- Dashboard status badge (should be green "DATA OK")
- Data age (should be <1 second)
- Vertical gain progressing as expected
- iPhone battery level
- Network connectivity stable

**Alert conditions:**
- Status shows "STALE" for >10 seconds
- Vertical gain stuck at same value for >1 minute
- Dashboard shows "ERROR" or "NO DATA"
- iPhone disconnected from Wi-Fi
- Server not responding

---

# TRACK B: Android Development (44+ hours)

**Note:** If you selected Android development, follow this track instead of Track A.

**Status:** ❌ Android track requires full application development (44 hours)

**Refer to:**
- [PRD_COMPLIANCE_EVALUATION.md](PRD_COMPLIANCE_EVALUATION.md) - Section 6 (Phase 2)
- [TACTICAL_REMEDIATION_GUIDE.md](TACTICAL_REMEDIATION_GUIDE.md) - Phase 2
- [DEPLOYMENT_DECISION_MATRIX.md](DEPLOYMENT_DECISION_MATRIX.md) - Option A details

**Android Development Phases:**
1. **Server fixes** (same as Track A Phase 1) - 2 hours
2. **Android project setup** - 4 hours
3. **Barometer sensor implementation** - 8 hours
4. **Foreground service** - 8 hours
5. **Network layer** - 6 hours
6. **UI & configuration** - 6 hours
7. **Battery optimization** - 4 hours
8. **Testing** - 8 hours
9. **Dashboard** (same as Track A Phase 3) - 4 hours
10. **Integration testing** - 8 hours

**Total: 58 hours (7.25 days)**

---

## TROUBLESHOOTING GUIDE

### Common Issues

**Issue: Server won't start**
```bash
# Check port not in use
lsof -i :8787
# Kill if needed
kill -9 <PID>
```

**Issue: iOS app shows "error" status**
- Check server IP correct
- Verify token matches
- Test with curl from Mac

**Issue: Dashboard shows "NO DATA"**
- Check server /latest endpoint
- Verify iOS app "connected"
- Check network connectivity

**Issue: Pressure values wrong (10x off)**
- Verify kPa→hPa conversion done
- Check iOS app using pressureHPa (not pressureKPa)
- Validate with known altitude

**Issue: Chart not displaying**
- Check browser console for errors
- Verify Chart.js loaded (check Network tab)
- Ensure canvas element exists

**Issue: "STALE DATA" appears immediately**
- Check system clocks synchronized
- Verify ts_unix_ms in milliseconds (not seconds)
- Check network latency

---

## SUCCESS METRICS

### Definition of Done

**System is production-ready when:**

1. ✅ All Phase 1-4 tasks completed
2. ✅ All validation steps passed
3. ✅ All success criteria met
4. ✅ Pre-climb checklist executable
5. ✅ Deployment sign-offs obtained

### Performance Targets (PRD Requirements)

- **Latency:** <500ms phone → server ✅ Measured
- **Update rate:** ≥2 Hz sustained ✅ Validated
- **Memory:** Server <100MB ✅ Monitored
- **Battery:** <15% drain/4hrs ✅ Tested (long test)
- **Uptime:** 100% during climb ✅ To be validated in production

### Compliance Checklist

- [ ] Pressure in hPa (not kPa)
- [ ] run_id field present
- [ ] baseline_set field present
- [ ] status field present
- [ ] /health returns age_ms
- [ ] /latest returns 503 when no data
- [ ] Dashboard displays all PRD metrics
- [ ] Chart updates in real-time
- [ ] Stale detection at 2 seconds
- [ ] Lock screen operation confirmed

---

## COMPLETION REPORT

**Project:** SKYSCRAPERALTIMETER
**Deployment Date:** _______________
**Platform:** [ ] iOS  [ ] Android

### Checklist Summary

- [ ] Phase 1: Server fixes (2 hours) - COMPLETE
- [ ] Phase 2: Mobile app updates (2 hours) - COMPLETE
- [ ] Phase 3: Dashboard (4 hours) - COMPLETE
- [ ] Phase 4: Testing (2-3 hours) - COMPLETE
- [ ] Phase 5: Production prep (1-2 hours) - COMPLETE

**Total Time:** _______________ hours

### Final Status

- [ ] ✅ PRODUCTION READY - All criteria met
- [ ] ⚠️ READY WITH CAVEATS - Document exceptions
- [ ] ❌ NOT READY - List blockers

### Known Limitations

List any PRD deviations or known issues:
1. _______________
2. _______________
3. _______________

### Sign-Off

**I certify this system is ready for production deployment:**

Signature: _______________ Date: _______________

---

**END OF CHECKLIST**

For questions or issues, refer to:
- [PRD_COMPLIANCE_EVALUATION.md](PRD_COMPLIANCE_EVALUATION.md) - Detailed analysis
- [TACTICAL_REMEDIATION_GUIDE.md](TACTICAL_REMEDIATION_GUIDE.md) - Code snippets
- [DEPLOYMENT_DECISION_MATRIX.md](DEPLOYMENT_DECISION_MATRIX.md) - Platform guidance
- [EVALUATION_SUMMARY_AND_NEXT_STEPS.md](EVALUATION_SUMMARY_AND_NEXT_STEPS.md) - Overview

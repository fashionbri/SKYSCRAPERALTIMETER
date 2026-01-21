## Step 3 — Server Validation (Pre-Network)
- [ ] Start server locally with no errors
- [ ] Confirm port and bind address are correct
- [ ] Verify `/health` returns JSON (not blank)
- [ ] Confirm server responds before phone connects
- [ ] Log startup configuration (port, env, version)
# SKYSCRAPERALTIMETER — Integration Checklist

## Pre-Flight
- [ ] Confirm phone device and OS (Android / iOS)
- [ ] Confirm barometer/pressure sensor available
- [ ] Confirm HR monitor + IFB paired and stable
- [ ] Confirm no changes to VLAN, Ethernet, or XPression configs

## Server Setup
- [ ] Python environment created and activated
- [ ] `pip install -r server/requirements.txt` completed
- [ ] Server binds to `0.0.0.0` (not localhost)
- [ ] Health endpoint responds: `/health`

## Network
- [ ] Phone and server on same LAN/VLAN
- [ ] Server reachable from phone via IP
- [ ] Firewall not blocking port

## Data Contract
- [ ] Timestamp included
- [ ] Relative

---

## 🚨 SHOW-DAY RED STOP (Hard No-Go Conditions)
Stop and escalate if any are true:

- [ ] `/health` endpoint is blank or non-200
- [ ] Server only reachable on localhost
- [ ] Phone cannot reach server IP:PORT
- [ ] Altitude data freezes for more than 10 seconds
- [ ] Bluetooth instability affects capture
- [ ] Units or field names don’t match graphics
- [ ] Any last-minute network change is requested

---

## Android Appendix (Galaxy S25)

### Sensors
- Use Android `TYPE_PRESSURE` (barometer)
- Compute **relative altitude** from pressure deltas only

### Capture Rules
- Sample rate: fastest stable (GAME)
- Smooth pressure slightly to avoid jitter
- Accumulate **vertical gain since start**
- Buffer briefly if network drops

### Phone Settings
- Disable battery optimization
- Do Not Disturb ON
- Screen stays awake
- Do not touch phone after start


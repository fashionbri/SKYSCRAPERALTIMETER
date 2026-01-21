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



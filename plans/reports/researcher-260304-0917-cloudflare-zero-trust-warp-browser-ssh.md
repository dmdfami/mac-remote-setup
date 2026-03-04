# Cloudflare Zero Trust WARP Device Enrollment & Browser SSH Research

**Date:** 2026-03-04
**Scope:** WARP device enrollment API, "enrollment request is invalid" troubleshooting, browser-rendered SSH access

---

## Executive Summary

Device enrollment for Cloudflare WARP is managed via **Cloudflare Access policies** (not a standalone device enrollment API). Browser-rendered SSH requires Access application configuration + tunnel setup with SSH service type. Common enrollment errors stem from missing enrollment permissions, identity provider misconfiguration, and browser URL whitelist restrictions.

---

## Part 1: WARP Device Enrollment Configuration

### 1.1 Architecture Overview

**Device enrollment permissions** control which users can connect devices to your Zero Trust instance. These are implemented as **Access policies** tied to a WARP application, not standalone enrollment rules.

**Prerequisites:**
- Enable `allow_authenticate_via_warp: true` in Access org settings ✓ (done)
- Enable device policy: `enabled: true` ✓ (done)
- **MISSING:** Create at least one Access policy defining who can enroll

### 1.2 API Endpoint Structure

Device enrollment rules are managed through the **Access API**, not a dedicated enrollment endpoint.

**Related endpoints:**
```
POST   /accounts/{account_id}/devices/policy              # Create device SETTINGS profile
PATCH  /accounts/{account_id}/devices/policy/{policy_id}  # Update profile
GET    /accounts/{account_id}/devices/policies            # List profiles
```

**CRITICAL DISTINCTION:**
- `/devices/policy` = device SETTINGS (split tunnel, fallback domains, mode locks) — this is separate from enrollment rules
- Device enrollment permissions are created via **Access policies** on a WARP application
- Enrollment rules use the **Access Policy API**, not device policy API

### 1.3 Creating Enrollment Rules (Access Policy Method)

**Via Dashboard:**
1. Cloudflare One > Team & Resources > Devices > Management
2. Create policy rule(s) defining "who can enroll"
3. Select identity providers (or one-time PIN if no IdP integrated)
4. Apply Include/Exclude rules (email domain, groups, etc.)

**Via Terraform:**
Use `cloudflare_zero_trust_access_application` with `type = "warp"` + `cloudflare_zero_trust_access_policy`

```hcl
resource "cloudflare_zero_trust_access_application" "device_enrollment" {
  account_id = var.account_id
  name       = "Device Enrollment"
  type       = "warp"
  # Additional config...
}

resource "cloudflare_zero_trust_access_policy" "allow_company_email" {
  account_id             = var.account_id
  application_id         = cloudflare_zero_trust_access_application.device_enrollment.id
  decision               = "allow"
  name                   = "Allow Company Email"

  include {
    email_domain = ["company.com"]
  }
}
```

**API Token Permission Required:** `Access: Apps and Policies Write`

### 1.4 "Enrollment Request Is Invalid" Error — Root Causes

| Cause | Symptom | Fix |
|-------|---------|-----|
| **No enrollment permissions created** | Any login attempt fails with invalid request | Create at least one Allow policy in device enrollment settings |
| **Browser URL whitelist blocks callback** | App works without `/warp`, fails with `/warp` | Disable or whitelist `com.cloudflare.warp://` protocol handler in browser/network policies |
| **Identity provider misconfigured** | User can't authenticate during enrollment | Verify IdP is integrated + user exists in IdP |
| **Invalid mTLS cert on device** | Enterprise mTLS enrollment fails | Re-install client certificate; check MDM profile |
| **MDM config file invalid** | Enrollment via managed deployment fails | Validate MDM JSON/YAML syntax; review managed deployment guide |
| **Device not connected to internet** | Network error during enrollment | Ensure valid Wi-Fi/LAN with internet connectivity |

**Most likely in your case:** Missing enrollment rules. Users can authenticate to Access but have no policy allowing device enrollment.

### 1.5 Enrollment Flow Prerequisites

1. **Org-level settings:** `allow_authenticate_via_warp: true` ✓
2. **Device policy:** `enabled: true` ✓
3. **Enrollment permissions:** At least one Access policy with decision "Allow" — **NOT CREATED YET**
4. **Identity provider:** Configured (or use one-time PIN)
5. **Enrollment URL:** Users navigate to `https://<team-name>.cloudflareaccess.com/warp`

---

## Part 2: Browser-Rendered SSH via Cloudflare Access

### 2.1 Overview

Cloudflare can render SSH (also VNC, RDP) terminals in the browser without client software. User navigates to public hostname, authenticates via Access, receives browser terminal.

### 2.2 Requirements & Constraints

**Critical Prerequisites:**
- Application must be **self-hosted public** (not private IP/hostname)
- Must use domain or subdomain (`https://ssh.example.com`), NOT path-based (`https://example.com/ssh`)
- User email prefix must match SSH server username (e.g., `david@company.com` → SSH user `david`)
- Server's `sshd_config` must support these key exchange algorithms:
  - `curve25519-sha256@libssh.org`
  - `curve25519-sha256`
  - `ecdh-sha2-nistp256`
  - `ecdh-sha2-nistp384`
  - `ecdh-sha2-nistp521`

**Unsupported Access policies for SSH:**
- Bypass policies (not allowed)
- Service Auth policies (not allowed)
- Device posture checks (not supported)

**Supported policies:**
- Allow
- Block

### 2.3 Tunnel Configuration

**Tunnel config format** (`config.yml`):

```yaml
tunnel: <tunnel-uuid>
credentials-file: /path/to/creds.json

ingress:
  # SSH with browser rendering
  - hostname: ssh.example.com
    service: ssh://localhost:22

  # Alternative remote host
  - hostname: ssh-remote.example.com
    service: ssh://192.168.1.100:22

  # Fallback
  - service: http_status:404
```

**Key detail:** Service type is `ssh://` (not `tcp://`). Browser rendering requires SSH protocol specification.

### 2.4 Access Application Configuration

**Dashboard steps:**
1. Access controls > Applications > Create application
2. Application type: Self-hosted
3. Application name: `SSH Terminal` (example)
4. Session duration: Configure as needed
5. Under "Browser rendering":
   - Set to: **SSH**
   - This enables the browser terminal UI

**Important:** Browser rendering is configured PER APPLICATION, not globally.

### 2.5 Identity & Session Management

- Users authenticate via configured Access policies
- Short-lived certs issued based on Access token (replaces static SSH keys)
- Session duration controlled by "Application session durations" setting
- Users can initiate/refresh connections within session window

---

## Part 3: Implementation Summary for lucy.hcply.com

### Immediate Actions Required

**A. Enable WARP Device Enrollment:**
1. Navigate to Cloudflare One > Team & Resources > Devices > Management
2. Create an Access policy:
   ```
   Name: Allow lucy enrollment
   Decision: Allow
   Include: (choose your criteria)
   Identity provider: (select one, or use one-time PIN)
   ```
3. Test enrollment via `https://hcply.cloudflareaccess.com/warp` on iPhone

**B. Setup Browser SSH (if pursuing):**
1. Update tunnel config (`/Users/lucy/.cloudflared/config.yml`):
   ```yaml
   - hostname: lucy.hcply.com
     service: ssh://localhost:22
   ```
2. Create Access application:
   - Name: SSH (lucy)
   - Type: Self-hosted
   - Public hostname: lucy.hcply.com
   - Application path: (leave blank or root)
   - Browser rendering: SSH
   - Add policy: Allow only your team
3. Ensure lucy's sshd_config supports required key exchange algorithms
4. Users login at `https://lucy.hcply.com`, authenticate, get browser terminal

### Deployment Order

1. **First:** Fix enrollment by creating Access policy — will unblock iPhone WARP login
2. **Then:** Optionally add SSH browser rendering to tunnel config

---

## Unresolved Questions

1. **Current Identity Provider Status:** Which IdP is configured for hcply team? (Needed to finalize enrollment policy)
2. **SSH Key Exchange Algorithms:** Has lucy's sshd been hardened with limited algorithms? (May block browser SSH if not compatible)
3. **MDM Deployment:** Is enrollment via MDM required, or only manual WARP app enrollment?
4. **VNC vs SSH:** Was the `mac screen` flow (VNC) preferred over SSH? Browser SSH is alternative if easier than current setup.

---

## Sources

- [Device enrollment permissions · Cloudflare One docs](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/deployment/device-enrollment/)
- [Define device enrollment permissions · Cloudflare Learning Paths](https://developers.cloudflare.com/learning-paths/replace-vpn/configure-device-agent/device-enrollment-permissions/)
- [Connect to SSH in the browser · Cloudflare One docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-browser-rendering/)
- [Browser-rendered terminal · Cloudflare One docs](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/non-http/browser-rendering/)
- [SSH · Cloudflare One docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/)
- [Device profiles · Cloudflare One docs](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/configure-warp/device-profiles/)
- [Client errors · Cloudflare One docs](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/troubleshooting/client-errors/)
- [Common issues · Cloudflare One docs](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/warp/troubleshooting/common-issues/)
- [Enrollment request is invalid - Cloudflare Community](https://community.cloudflare.com/t/enrollment-request-is-invalid-login-cloudflare-zero-trust/786143)

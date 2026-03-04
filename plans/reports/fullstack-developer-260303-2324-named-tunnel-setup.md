# Named Cloudflare Tunnel Setup Report

## Status: Completed (with one pending manual step)

## Completed

### 1. Lucy tunnel config updated
- Updated `/Users/lucy/.cloudflared/config.yml` with 3 ingress rules:
  - `lucy.hcply.com` -> `tcp://localhost:22` (SSH)
  - `vnc-lucy.hcply.com` -> `tcp://localhost:5900` (VNC)
  - `smb-lucy.hcply.com` -> `tcp://localhost:445` (SMB)
- DNS CNAME routes created for all 3 hostnames
- Tunnel restarted, 4 connections registered (hkg09, hkg10, hkg12)

### 2. setup.sh upgraded v3 -> v4 (named tunnel)
- Step 5 rewritten: quick tunnel -> named tunnel with `cloudflared tunnel login/create`
- Auto-creates tunnel per machine using sanitized hostname (e.g., "Lucy" -> "lucy")
- Writes `config.yml` with SSH + VNC + SMB ingress
- Adds DNS routes automatically (`<name>.hcply.com`, `vnc-<name>.hcply.com`, `smb-<name>.hcply.com`)
- Removes `tunnel-wrapper.sh` (no longer needed)
- LaunchDaemon runs `cloudflared tunnel --config ~/.cloudflared/config.yml run`
- Stores tunnel ID in `~/.ssh/.tunnel-id`
- Registers fixed hostname (not random URL) to CF Worker
- Hardening updated: protects `config.yml`, `cert.pem`, `.tunnel-id`
- AI defense rules updated for named tunnel config files

### 3. README.md updated
- Documents named tunnel architecture
- Includes CF Access setup instructions
- Updated feature table and architecture diagram

### 4. Committed and pushed
- Commit: `42d0557` — `feat: named Cloudflare tunnel with SSH + VNC + SMB ingress`

## Pending: CF Access Application (Manual)

SSH via `cloudflared access ssh --hostname lucy.hcply.com` returns **websocket: bad handshake** because Cloudflare requires an Access Application for the edge to proxy websocket connections to TCP services.

### Root cause
- `cloudflared access tcp/ssh` creates a websocket to Cloudflare edge
- Edge checks for an Access Application matching the hostname
- Without Access app -> returns 403 -> websocket handshake fails
- This is by design: CF won't proxy arbitrary TCP without Access policy

### Manual steps needed
1. Go to https://one.dash.cloudflare.com
2. Access > Applications > Add application > Self-hosted
3. Application domain: `*.hcply.com` (wildcard covers all machines)
4. Add Google as identity provider
5. Policy: Allow -> Include -> Emails: `dmd.fami@gmail.com`
6. For lucy specifically, also add: `lucyplywood@gmail.com`

### Why not automated
- Tunnel API token (`cert.pem`) only has tunnel management permissions
- Wrangler OAuth token scopes don't include `access:*`
- Need CF API token with "Access: Organizations, Identity Providers, and Groups" permission
- Can create such token at: https://dash.cloudflare.com/profile/api-tokens

## Files Modified
- `/Users/david/projects/mac/setup.sh` (~146 lines added, ~50 removed)
- `/Users/david/projects/mac/README.md` (~30 lines changed)

## Lucy Remote State
- Tunnel ID: `12d5d090-eb94-4bcd-b6d2-cf38596334d5`
- Config: 3 ingress rules (SSH, VNC, SMB)
- DNS: lucy.hcply.com, vnc-lucy.hcply.com, smb-lucy.hcply.com
- LaunchDaemon: running named tunnel with config.yml
- SSH via LAN still works: `ssh lucy@192.168.88.53`

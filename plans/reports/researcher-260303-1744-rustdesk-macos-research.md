# RustDesk macOS Research Report

**Date**: 2026-03-03 | **Scope**: Headless CLI setup, ID persistence, password config, service/daemon deployment

---

## 1. RustDesk ID Stability & Persistence

### Does RustDesk ID Change?
- **Status**: FIXED per machine (stable across sessions)
- **Mechanism**: ID generated at initial startup based on system identifiers (machine-id)
- **Important caveat**: After OS cloning/disk image duplication, **all cloned machines retain identical RustDesk ID** until RustDesk is reinstalled
- **Cannot change via UI**: No built-in mechanism to change ID through GUI or config files; requires workarounds

### Password Management
- **Type**: Permanent password (different from one-time session password)
- **Persistence**: Stored in RustDesk config after setting
- **No native retrieval**: Cannot retrieve stored permanent password via CLI (can only set it)

---

## 2. macOS Installation Methods

### Option A: Homebrew (Recommended for CLI automation)
```bash
brew install --cask rustdesk
```
- **Version**: 1.4.5+ (requires macOS 12+)
- **Install location**: `/Applications/RustDesk.app`
- **Advantage**: Automatable, single command

### Option B: Manual DMG Download
- Download .dmg from GitHub
- `open /path/to/RustDesk.dmg`
- Drag to Applications
- Security clearance: Must authorize "App Store and identified developers" in System Preferences

---

## 3. CLI-Based Configuration

### Set Permanent Password
```bash
# Using binary directly
/Applications/RustDesk.app/Contents/MacOS/RustDesk --password YOUR_PASSWORD

# Or with sudo
sudo /Applications/RustDesk.app/Contents/MacOS/RustDesk --password YOUR_PASSWORD
```
- **Requirement**: Root/sudo privileges
- **Output on success**: "Done!"
- **When to run**: Can be run before or after service startup
- **Install script shorthand**: `sudo bash install_service.sh -p "YourPassword"`

### Get RustDesk ID Programmatically
```bash
/Applications/RustDesk.app/Contents/MacOS/RustDesk --get-id
```
- **Requirement**: RustDesk service must be running first
- **Important**: `--get-id` only works AFTER first GUI launch (daemon/agent must initialize config)
- **Output format**: Plain text ID (e.g., `1234567890`)
- **Use case**: Retrieve ID for automation, logging, registration

### Get Permanent Password
- **Blocker**: No CLI command available to retrieve stored password
- **Workaround**: Must track password separately in config/env or use installation script logs

---

## 4. Service/Daemon Setup on macOS

### Official Installation Script
RustDesk provides `install_service.sh` for headless deployment (no GUI required).

**Location**: Typically bundled in release or downloaded separately from RustDesk GitHub

**Basic usage**:
```bash
sudo bash install_service.sh
```

**With configuration**:
```bash
# Set permanent password
sudo bash install_service.sh -p "YourPassword"

# Set device ID (note: limited effect—cannot fully override auto-generated ID)
sudo bash install_service.sh -i "DeviceID"

# Specify user (for MDM deployment)
sudo bash install_service.sh -u username
```

### Generated LaunchDaemons/Agents
After running `install_service.sh`, two system services are created:

| Service | Location | User | Purpose |
|---------|----------|------|---------|
| **Daemon** | `/Library/LaunchDaemons/com.carriez.rustdesk_service.plist` | root | Runs at boot, manages IPC config |
| **Agent** | `/Library/LaunchAgents/com.carriez.rustdesk_server.plist` | target user | Runs in GUI session, handles remote connections |

**Critical**: Both must run for full functionality. Screen capture requires GUI session context.

### Management Commands
```bash
# Start service
sudo launchctl load /Library/LaunchDaemons/com.carriez.rustdesk_service.plist

# Stop service
sudo launchctl unload /Library/LaunchDaemons/com.carriez.rustdesk_service.plist

# Check status
launchctl list | grep rustdesk

# View logs
log stream --predicate 'process == "RustDesk"'
```

### Headless Deployment Notes
- Script **does NOT grant permissions** (must deploy via MDM or manual System Preferences)
- Supports `AUTO_CREATE_CONFIG=1` to auto-generate empty config files
- Supports `CLEAR_STOP_SERVICE=1` for clean redeployment
- Designed for SSH remote deploy, MDM batch install, VM imaging

---

## 5. macOS Permissions Required

### Three Critical Permissions
1. **Screen Recording** - Captures display for remote view
2. **Accessibility** - Enables keyboard & mouse remote control + screen functionality
3. **Input Monitoring** - Captures keyboard/mouse input events

### Deployment Methods
- **Manual**: System Preferences → Security & Privacy (no CLI method available)
- **MDM**: Deploy .mobileconfig profile for automated permission grants
- **Post-Install**: Remove & re-add RustDesk in System Preferences to refresh permission detection

### TCC Framework (Privacy Control)
- Permissions stored in `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.carriez.rustdesk.sfl` (or similar)
- SIP (System Integrity Protection) prevents direct TCC.db modification
- No reliable CLI bypass available

---

## 6. Configuration File Locations & Management

### Primary Config Directories
```
~/Library/Preferences/com.carriez.rustdesk.*
~/Library/Application Support/RustDesk/
/var/lib/rustdesk/  (service daemon config)
```

### Configuration via install_service.sh
Script creates config automatically with:
- IPC socket path
- Service management plists
- Optional permanent password storage

### RustDesk Server Pro: Config String Import
```bash
/Applications/RustDesk.app/Contents/MacOS/RustDesk --config "BASE64_CONFIG_STRING"
```
- Generate config string in RustDesk Server Pro console
- Encrypted configuration (ID server, relay server, public key)
- One-time import (modifies preferences)

---

## 7. Headless/Daemon Limitations & Workarounds

### Screen Capture Without GUI Session
**Problem**: GUI session required for screen capture (CoreGraphics), not available in pure headless/SSH context

**Workaround**:
- Use with LoginWindow session (works with locked screen)
- Ensure Agent runs in target user's session
- Cannot capture during system sleep

### Password Retrieval in Automation
**Problem**: No CLI command to read back stored password

**Solutions**:
- Store password in config file (non-standard approach)
- Track via environment variable or separate password manager
- Regenerate password if lost (requires service restart)

### ID Predictability (Image Cloning)
**Problem**: Cloned systems share same RustDesk ID

**Fix**: After imaging, reinstall RustDesk or reset machine-id:
```bash
# Regenerate machine ID (Linux approach, may not work on macOS)
sudo rm /etc/machine-id && sudo systemd-machine-id-setup
```

---

## 8. Quick Reference: Complete Headless Setup

```bash
# 1. Install RustDesk
brew install --cask rustdesk

# 2. Download and run service installer
curl -fsSL https://raw.githubusercontent.com/rustdesk/rustdesk/master/install_service.sh | \
  sudo bash -s -- -p "YOUR_PASSWORD"

# 3. Grant permissions (manual or MDM)
# → System Preferences → Security & Privacy → Screen Recording/Accessibility/Input Monitoring

# 4. Verify service is running
launchctl list | grep rustdesk

# 5. Get ID for registration
/Applications/RustDesk.app/Contents/MacOS/RustDesk --get-id
```

---

## Unresolved Questions & Limitations

1. **Password Retrieval**: Is there a way to read back the stored permanent password programmatically? (Appears NO—password is hashed/encrypted)

2. **ID Override**: Can `install_service.sh -i` reliably override the auto-generated ID? (Limited—ID regenerates on first daemon startup)

3. **TCC Automation**: Is there a non-MDM way to grant Screen Recording/Accessibility permissions via CLI on macOS 15+? (SIP prevents direct TCC.db writes)

4. **Service Startup Timing**: How long does the daemon/agent need to initialize before `--get-id` becomes functional? (Typically 2-5 seconds, not documented)

5. **Config File Format**: What is the exact format/encryption of permanent password storage in RustDesk config files? (Not publicly documented)

---

## Sources
- [RustDesk macOS Documentation](https://rustdesk.com/docs/en/client/mac/)
- [RustDesk macOS Auto-Start Service Setup (GitHub Wiki)](https://github.com/rustdesk/rustdesk/wiki/macOS-Auto%E2%80%90Start-Service-Setup-(for-Remote---MDM-Deployment))
- [RustDesk Homebrew Formula](https://formulae.brew.sh/cask/rustdesk)
- [TechOverflow: RustDesk Permanent Password CLI](https://techoverflow.net/2025/03/01/rustdesk-how-to-set-permanent-password-on-the-command-line/)
- [RustDesk Client Deployment Documentation](https://rustdesk.com/docs/en/self-host/client-deployment/)
- [RustDesk Client Configuration](https://rustdesk.com/docs/en/self-host/client-configuration/)
- [GitHub Issue: RustDesk ID Change](https://github.com/rustdesk/rustdesk/discussions/13098)
- [GitHub Discussion: Command Line Support](https://github.com/rustdesk/rustdesk/discussions/3980)

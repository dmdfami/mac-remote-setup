#!/bin/bash
# ============================================
# DAVID'S MAC REMOTE — Idempotent (chạy bao nhiêu lần cũng OK)
# ============================================
clear
echo "=========================================="
echo "  Mac Remote Setup"
echo "=========================================="

API="https://mac-nodes.dmd-fami.workers.dev"
KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFi38QEU6BlyGvfozRqZh9VKynr51NwUMjUHMOdmM5Gj export@vietnam-plywood.com"
CF="/opt/homebrew/bin/cloudflared"

# 1. Homebrew (skip if exists)
if command -v brew &>/dev/null; then
  echo "[1/6] Homebrew OK (skip)"
else
  echo "[1/6] Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# PATH for SSH sessions (.zshenv is loaded for ALL zsh sessions including non-interactive SSH)
if ! grep -q 'homebrew' ~/.zshenv 2>/dev/null; then
  echo 'export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH' >> ~/.zshenv
fi

# 2. Node.js (skip if exists)
if command -v node &>/dev/null; then
  echo "[2/6] Node.js OK (skip)"
else
  echo "[2/6] Installing Node.js..."
  brew install node 2>/dev/null
fi

# 3. SSH + key (idempotent — grep trước khi thêm)
echo "[3/6] SSH + key..."
sudo systemsetup -setremotelogin on 2>/dev/null
mkdir -p ~/.ssh && chmod 700 ~/.ssh
grep -qF "$KEY" ~/.ssh/authorized_keys 2>/dev/null || echo "$KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 4. Cloudflared (skip if exists)
if [ -f "$CF" ]; then
  echo "[4/6] cloudflared OK (skip)"
else
  echo "[4/6] Installing cloudflared..."
  brew install cloudflared 2>/dev/null
fi

# 5. Tunnel wrapper + LaunchAgent (overwrite = update)
echo "[5/6] Tunnel service..."
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
cat > ~/Library/LaunchAgents/com.cloudflare.tunnel.plist << 'PEOF'
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
    <string>/Users/USERPLACEHOLDER</string>
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
sed -i '' "s|USERPLACEHOLDER|$(whoami)|" ~/Library/LaunchAgents/com.cloudflare.tunnel.plist

# Restart tunnel service
launchctl unload ~/Library/LaunchAgents/com.cloudflare.tunnel.plist 2>/dev/null
pkill -f "cloudflared tunnel" 2>/dev/null
sleep 1
launchctl load ~/Library/LaunchAgents/com.cloudflare.tunnel.plist

# 6. VPS-like access — sudo NOPASSWD + keychain auto-unlock
echo "[6/7] VPS-like access (sudo + keychain)..."
CURRENT_USER=$(whoami)

# 6a. Sudo NOPASSWD (requires password once during setup)
if sudo -n true 2>/dev/null; then
  echo "      sudo NOPASSWD already configured (skip)"
else
  echo "      Setting up sudo NOPASSWD..."
  echo "      Enter your Mac password (one-time only):"
  read -s USER_PASS
  echo "$USER_PASS" | sudo -S sh -c "echo \"$CURRENT_USER ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/$CURRENT_USER && chmod 440 /etc/sudoers.d/$CURRENT_USER" 2>/dev/null
  if sudo -n true 2>/dev/null; then
    echo "      sudo NOPASSWD OK!"

    # 6b. Keychain auto-unlock on SSH login (uses same password)
    mkdir -p ~/.ssh
    echo "$USER_PASS" > ~/.ssh/.keychain-pass
    chmod 600 ~/.ssh/.keychain-pass

    cat > ~/.ssh/unlock-keychain.sh << 'KCEOF'
#!/bin/bash
security unlock-keychain -p "$(cat ~/.ssh/.keychain-pass)" ~/Library/Keychains/login.keychain-db 2>/dev/null
KCEOF
    chmod 700 ~/.ssh/unlock-keychain.sh

    # Add to .zshenv for auto-unlock on SSH
    grep -q "unlock-keychain" ~/.zshenv 2>/dev/null || echo '[ -f ~/.ssh/unlock-keychain.sh ] && ~/.ssh/unlock-keychain.sh' >> ~/.zshenv

    # Unlock now
    security unlock-keychain -p "$USER_PASS" ~/Library/Keychains/login.keychain-db 2>/dev/null
    echo "      Keychain auto-unlock configured!"
  else
    echo "      [WARN] Wrong password — sudo + keychain skipped. Re-run script to retry."
  fi
fi

# 7. Claude CLI — export credentials for SSH access
echo "[7/7] Claude CLI..."
if [ -f /opt/homebrew/bin/claude ] || command -v claude &>/dev/null; then
  # Try Keychain first (GUI login stores here)
  CRED=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  if [ -n "$CRED" ]; then
    mkdir -p ~/.claude
    # Claude CLI reads .credentials.json (NOT .credentials)
    echo "$CRED" > ~/.claude/.credentials.json
    chmod 600 ~/.claude/.credentials.json
    echo "      Credentials exported for SSH access!"
  elif [ -f ~/.claude/.credentials.json ]; then
    echo "      Credentials file OK (skip)"
  elif [ -f ~/.claude/.credentials ]; then
    # Fix: rename old .credentials to .credentials.json
    cp ~/.claude/.credentials ~/.claude/.credentials.json
    chmod 600 ~/.claude/.credentials.json
    echo "      Credentials migrated (.credentials → .credentials.json)"
  else
    echo "      No credentials found. Run 'claude' and /login first, then re-run this script."
  fi
else
  echo "      Installing Claude CLI..."
  npm install -g @anthropic-ai/claude-code 2>/dev/null
  echo "      Claude installed. Run 'claude' to login, then re-run this script."
fi

# Wait for tunnel
echo ""
echo "Waiting for tunnel..."
TUNNEL_URL=""
for i in {1..20}; do
  TUNNEL_URL=$(grep -o 'https://[a-z0-9\-]*\.trycloudflare\.com' /tmp/cf-tunnel.log 2>/dev/null | tail -1)
  if [ -n "$TUNNEL_URL" ]; then break; fi
  sleep 3
done

MY_USER=$(whoami)
MY_LAN=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
MY_HOST=$(scutil --get ComputerName 2>/dev/null || hostname)

echo ""
echo "============================================"
echo "  DONE!"
echo "  Tunnel: ${TUNNEL_URL:-check /tmp/cf-tunnel.log}"
echo "  LAN:    ssh $MY_USER@$MY_LAN"
echo "  Host:   $MY_HOST"
echo "  Reboot: auto-reconnect YES"
SUDO_STATUS="NO"
sudo -n true 2>/dev/null && SUDO_STATUS="YES"
echo "  Sudo:   NOPASSWD=$SUDO_STATUS"
echo "  Keychain: auto-unlock=$([ -f ~/.ssh/unlock-keychain.sh ] && echo YES || echo NO)"
echo "============================================"
read -p "Press Enter to close..."

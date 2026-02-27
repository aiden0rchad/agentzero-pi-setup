#!/bin/bash
# =================================================================
# AgentZero Setup Script for Raspberry Pi 4 (ARM64)
#
# This script installs Python 3.12 via pyenv, sets up a virtual
# environment, installs all AgentZero dependencies with ARM64-
# compatible package versions, applies memory optimizations (swap, TTS disable),
# and creates a systemd service for auto-start.
#
# Usage:
#   chmod +x setup_agentzero.sh && bash setup_agentzero.sh
#
# Estimated time: ~30-40 minutes (Python compilation is slow on Pi)
# =================================================================

set -e

PYTHON_VERSION="3.12.10"
AGENT_DIR="$HOME/agent-zero"

echo "============================================"
echo "  AgentZero Raspberry Pi Setup"
echo "  Installing Python $PYTHON_VERSION via pyenv"
echo "============================================"

# -----------------------------------------------
# STEP 1: System dependencies for pyenv + Python build
# -----------------------------------------------
echo ""
echo "[1/9] Installing build dependencies..."
sudo apt update
sudo apt install -y \
    make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev wget curl \
    llvm libncursesw5-dev xz-utils tk-dev \
    libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    git

# -----------------------------------------------
# STEP 2: Install pyenv
# -----------------------------------------------
echo ""
echo "[2/9] Installing pyenv..."
if [ -d "$HOME/.pyenv" ]; then
    echo "pyenv already installed, skipping..."
else
    curl https://pyenv.run | bash
fi

# Add pyenv to current shell
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Add to .bashrc for future sessions
if ! grep -q 'pyenv init' "$HOME/.bashrc" 2>/dev/null; then
    echo '' >> "$HOME/.bashrc"
    echo '# pyenv' >> "$HOME/.bashrc"
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> "$HOME/.bashrc"
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'eval "$(pyenv init -)"' >> "$HOME/.bashrc"
    echo "Added pyenv to .bashrc"
fi

# -----------------------------------------------
# STEP 3: Install Python 3.12
# -----------------------------------------------
echo ""
echo "[3/9] Installing Python $PYTHON_VERSION (this takes 20-30 min on Pi 4)..."
if pyenv versions 2>/dev/null | grep -q "$PYTHON_VERSION"; then
    echo "Python $PYTHON_VERSION already installed, skipping..."
else
    pyenv install "$PYTHON_VERSION"
fi

# -----------------------------------------------
# STEP 4: Clone AgentZero
# -----------------------------------------------
echo ""
echo "[4/9] Setting up AgentZero repository..."
if [ -d "$AGENT_DIR" ]; then
    echo "agent-zero directory already exists, pulling latest..."
    cd "$AGENT_DIR" && git pull && cd ~
else
    git clone https://github.com/frdel/agent-zero.git "$AGENT_DIR"
fi

# -----------------------------------------------
# STEP 5: Create venv with Python 3.12 and install deps
# -----------------------------------------------
echo ""
echo "[5/9] Creating Python 3.12 virtual environment..."
cd "$AGENT_DIR"

# Remove old venv if it exists (e.g., from a Python 3.13 attempt)
if [ -d "venv" ]; then
    echo "Removing old venv..."
    rm -rf venv
fi

"$HOME/.pyenv/versions/$PYTHON_VERSION/bin/python3" -m venv venv
source venv/bin/activate

echo "Python version in venv: $(python --version)"
pip install --upgrade pip

echo ""
echo "[5b/9] Installing AgentZero requirements (this may take a while)..."
pip install -r requirements.txt
pip install -r requirements2.txt

echo ""
echo "[5c/9] Applying ARM64 compatibility fixes..."
# Fix torch: v2.10.0 uses ARMv8.2+ instructions that Pi 4 (ARMv8.0) lacks
pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
pip install torchvision==0.20.1

# Fix faiss: v1.11.0 has SVE detection issues on Pi 4
pip install faiss-cpu==1.8.0.post1

# Fix sentence-transformers: ensure compatibility with installed transformers
pip install sentence-transformers --upgrade

# -----------------------------------------------
# STEP 6: Apply AgentZero settings.py bug fix
# -----------------------------------------------
echo ""
echo "[6/9] Applying bug fix to settings.py (chpasswd SyntaxError)..."
SETTINGS_PY="$AGENT_DIR/python/helpers/settings.py"

# Fix: positional arg after keyword arg in set_root_password()
# This SyntaxError prevents AgentZero from starting entirely
python3 - << 'PYEOF'
import sys
path = '/home/' + __import__('os').environ.get('USER', 'pi') + '/agent-zero/python/helpers/settings.py'
try:
    with open(path, 'r') as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if 'subprocess.run(env=' in line and '{"PATH"' in line:
            lines[i] = '    _result = subprocess.run(\n'
            lines[i+1] = '        ["chpasswd"],\n'
            lines.insert(i+2, '        env={"PATH": __import__("os").environ.get("PATH", "") + ":/usr/sbin"},\n')
            with open(path, 'w') as f:
                f.writelines(lines)
            print("  ✅ settings.py SyntaxError fixed")
            sys.exit(0)
    print("  ℹ️  settings.py already patched or pattern not found — skipping")
except FileNotFoundError:
    print("  ⚠️  settings.py not found — skipping (may not exist until first run)")
PYEOF

# Also fix: empty root_password guard in _write_sensitive_settings
# Prevents "chpasswd: command failed" error when saving settings with no root password set
python3 - << 'PYEOF'
import sys, os
path = os.path.expanduser('~/agent-zero/python/helpers/settings.py')
try:
    with open(path, 'r') as f:
        content = f.read()
    # Only apply if the old (broken) pattern is present
    old = 'if settings["root_password"] != PASSWORD_PLACEHOLDER:'
    new = 'if settings["root_password"] and settings["root_password"] != PASSWORD_PLACEHOLDER:'
    if old in content and new not in content:
        content = content.replace(old, new, 1)
        with open(path, 'w') as f:
            f.write(content)
        print("  ✅ Empty root_password guard fixed")
    else:
        print("  ℹ️  root_password guard already patched — skipping")
except FileNotFoundError:
    print("  ⚠️  settings.py not found — skipping")
PYEOF

# -----------------------------------------------
# STEP 7: Install Docker (for agent sandbox)
# -----------------------------------------------
echo ""
echo "[7/9] Checking Docker..."
if command -v docker &> /dev/null; then
    echo "Docker is already installed."
else
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "Docker installed. You will need to log out and back in for group permissions."
fi

# -----------------------------------------------
# STEP 8: Create AgentZero's working directory
# -----------------------------------------------
echo ""
echo "[8/9] Creating /a0 working directory..."
# AgentZero expects /a0 as its default working directory (normally inside Docker)
# Without this, every tool call will fail with PermissionError
sudo mkdir -p /a0
sudo chown $USER:$USER /a0
echo "Created /a0 directory."

# -----------------------------------------------
# STEP 9: Memory optimizations for Raspberry Pi
# -----------------------------------------------
echo ""
echo "[9/9] Applying Raspberry Pi memory optimizations..."

# 9a: Add 4GB swap file if it doesn't already exist
# The Pi 4's 4GB RAM is tight for AgentZero + embedding model — real swap prevents OOM crashes
if [ ! -f /swapfile ]; then
    echo "  Creating 4GB swap file..."
    sudo fallocate -l 4G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
    echo "  ✅ 4GB swap file created and enabled"
else
    echo "  ℹ️  Swap file already exists, skipping"
fi

# 9b: Tune swappiness (default 60 is too aggressive; 10 = prefer RAM over swap)
if ! grep -q 'vm.swappiness' /etc/sysctl.conf 2>/dev/null; then
    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf > /dev/null
    sudo sysctl vm.swappiness=10 > /dev/null 2>&1
    echo "  ✅ swappiness set to 10"
fi

# 9c: Disable services that waste RAM on a Pi dedicated to AgentZero
echo "  Disabling unnecessary services..."
for svc in bluetooth ModemManager avahi-daemon; do
    if systemctl is-active --quiet $svc 2>/dev/null; then
        sudo systemctl stop $svc
        sudo systemctl disable $svc 2>/dev/null || true
        echo "  ✅ Disabled $svc"
    else
        echo "  ℹ️  $svc already disabled"
    fi
done

# 9d: Apply Pi-optimized AgentZero settings
echo "  Applying memory-optimized AgentZero settings..."
mkdir -p "$AGENT_DIR/usr"
if [ -f "$AGENT_DIR/usr/settings.json" ]; then
    python3 - << 'PYEOF'
import json, os
path = os.path.expanduser('~/agent-zero/usr/settings.json')
with open(path, 'r') as f:
    s = json.load(f)
# Disable Kokoro TTS: loads a large neural TTS model into RAM at startup (~500-800MB)
# You can re-enable in the web UI if you have enough RAM headroom
s['tts_kokoro'] = False
# Keep all memory/recall features enabled with immediate loading (full agent intelligence)
s['memory_recall_enabled'] = True
s['memory_memorize_enabled'] = True
# Ensure delayed loading is disabled so memory is available from the first message
s.pop('memory_recall_delayed', None)
with open(path, 'w') as f:
    json.dump(s, f, indent=4)
print("  ✅ Applied Pi memory optimizations to settings.json")
print("     - tts_kokoro: disabled (saves ~500-800MB RAM)")
print("     - memory_recall: enabled with eager loading (full intelligence)")
PYEOF
else
    echo "  ℹ️  No settings.json yet — optimizations will be applied on first save"
fi

# 9e: Add TTS disable to .env as a failsafe (survives settings resets)
if [ -f "$AGENT_DIR/usr/.env" ]; then
    if ! grep -q 'A0_SET_tts_kokoro' "$AGENT_DIR/usr/.env"; then
        echo 'A0_SET_tts_kokoro=false' >> "$AGENT_DIR/usr/.env"
        echo "  ✅ Added A0_SET_tts_kokoro=false to .env"
    fi
fi

# -----------------------------------------------
# Create systemd service with memory limits
# -----------------------------------------------
echo ""
echo "[Extra] Setting up systemd service with memory guards..."
SERVICE_FILE="/etc/systemd/system/agentzero.service"

sudo tee "$SERVICE_FILE" > /dev/null << SVCEOF
[Unit]
Description=AgentZero AI Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$AGENT_DIR
ExecStart=$AGENT_DIR/venv/bin/python run_ui.py --dockerized=true
Restart=on-failure
RestartSec=10
Environment=PATH=$AGENT_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin

# Memory guards: prevent AgentZero from crashing the whole OS
# MemoryHigh: soft limit — kernel starts reclaiming caches at this point
# MemoryMax: hard limit — systemd kills AgentZero (not random OS processes) if exceeded
MemoryHigh=2800M
MemoryMax=3200M
# OOMScoreAdjust: tell the kernel to kill this process first (not SSH, systemd, etc.)
OOMScoreAdjust=500

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable agentzero
echo "  ✅ systemd service installed with memory limits (MemoryMax=3200M)"

# -----------------------------------------------
# Create template configuration files
# -----------------------------------------------
echo ""
echo "[Config] Creating configuration templates..."

# Create settings.json template (if not already configured)
if [ ! -f "$AGENT_DIR/usr/settings.json" ]; then
cat > "$AGENT_DIR/usr/settings.json" << 'SETTINGS_EOF'
{
    "chat_model_provider": "openai",
    "chat_model_name": "YOUR_MODEL_NAME",
    "chat_model_api_base": "http://YOUR_LLM_SERVER_IP:PORT/v1",
    "chat_model_ctx_length": 32000,
    "chat_model_vision": false,
    "util_model_provider": "openai",
    "util_model_name": "YOUR_MODEL_NAME",
    "util_model_api_base": "http://YOUR_LLM_SERVER_IP:PORT/v1",
    "util_model_ctx_length": 32000,
    "embed_model_provider": "huggingface",
    "embed_model_name": "sentence-transformers/all-MiniLM-L6-v2",
    "embed_model_api_base": "",
    "browser_model_provider": "openai",
    "browser_model_name": "YOUR_MODEL_NAME",
    "browser_model_api_base": "http://YOUR_LLM_SERVER_IP:PORT/v1",
    "browser_model_vision": false,
    "agent_profile": "agent0",
    "tts_kokoro": false
}
SETTINGS_EOF
echo "Created usr/settings.json template — EDIT THIS with your LLM server details!"
else
    echo "usr/settings.json already exists, skipping..."
fi

# Create .env template
if [ ! -f "$AGENT_DIR/usr/.env" ]; then
cat > "$AGENT_DIR/usr/.env" << 'ENV_EOF'
# API key for OpenAI-compatible providers (use dummy value for local servers)
OPENAI_API_KEY=sk-no-key-required

# Internal communication password
RFC_PASSWORD=change_me_to_any_password

# Bind to all interfaces for network access
WEB_UI_HOST=0.0.0.0

# IMPORTANT: Password-protect the web UI (change this!)
# Without this, anyone on your network can use your agent
A0_AUTH_PASSWORD=change_me_to_a_strong_password

# Pi memory optimization: disable Kokoro TTS (saves ~500-800MB RAM)
A0_SET_tts_kokoro=false
ENV_EOF
echo "Created usr/.env template — CHANGE A0_AUTH_PASSWORD before exposing to network!"
fi

# -----------------------------------------------
# Install Playwright browser dependencies (optional)
# -----------------------------------------------
echo ""
echo "[Optional] Installing browser agent dependencies..."
sudo apt-get install -y libatk1.0-0 libatspi2.0-0 libxcomposite1 \
    libxdamage1 libxfixes3 libxrandr2 libgbm1 libxkbcommon0 2>/dev/null || \
    echo "Some browser deps not available — browser agent may not work (non-critical)."

# -----------------------------------------------
# DONE
# -----------------------------------------------
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  NEXT STEPS:"
echo ""
echo "  1. Edit the config with your LLM server details:"
echo "     nano ~/agent-zero/usr/settings.json"
echo ""
echo "  2. Set a strong web UI password:"
echo "     nano ~/agent-zero/usr/.env"
echo "     (change A0_AUTH_PASSWORD)"
echo ""
echo "  3. Log out and back in (for Docker group), then start AgentZero:"
echo "     sudo systemctl start agentzero"
echo "     sudo journalctl -u agentzero.service -f"
echo ""
echo "  4. Open in your browser:"
echo "     http://<your_pi_ip>:5000"
echo ""
echo "  Memory budget summary:"
echo "     RAM: $(free -h | awk '/^Mem:/{print $2}') total"
echo "     Swap: $(free -h | awk '/^Swap:/{print $2}') total"
echo "     AgentZero limit: 3200MB (hard cap via systemd)"
echo ""
echo "============================================"

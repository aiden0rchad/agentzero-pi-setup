#!/bin/bash
# =================================================================
# AgentZero Setup Script for Raspberry Pi 4 (ARM64)
#
# This script installs Python 3.12 via pyenv, sets up a virtual
# environment, installs all AgentZero dependencies with ARM64-
# compatible package versions, and optionally installs Docker.
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
echo "[1/7] Installing build dependencies..."
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
echo "[2/7] Installing pyenv..."
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
echo "[3/7] Installing Python $PYTHON_VERSION (this takes 20-30 min on Pi 4)..."
if pyenv versions 2>/dev/null | grep -q "$PYTHON_VERSION"; then
    echo "Python $PYTHON_VERSION already installed, skipping..."
else
    pyenv install "$PYTHON_VERSION"
fi

# -----------------------------------------------
# STEP 4: Clone AgentZero
# -----------------------------------------------
echo ""
echo "[4/7] Setting up AgentZero repository..."
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
echo "[5/7] Creating Python 3.12 virtual environment..."
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
echo "[5b/7] Installing AgentZero requirements (this may take a while)..."
pip install -r requirements.txt
pip install -r requirements2.txt

echo ""
echo "[5c/7] Applying ARM64 compatibility fixes..."
# Fix torch: v2.10.0 uses ARMv8.2+ instructions that Pi 4 (ARMv8.0) lacks
pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
pip install torchvision==0.20.1

# Fix faiss: v1.11.0 has SVE detection issues on Pi 4
pip install faiss-cpu==1.8.0.post1

# Fix sentence-transformers: ensure compatibility with installed transformers
pip install sentence-transformers --upgrade

# -----------------------------------------------
# STEP 6: Install Docker (for agent sandbox)
# -----------------------------------------------
echo ""
echo "[6/7] Checking Docker..."
if command -v docker &> /dev/null; then
    echo "Docker is already installed."
else
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "Docker installed. You will need to log out and back in for group permissions."
fi

# -----------------------------------------------
# STEP 7: Create template configuration files
# -----------------------------------------------
echo ""
echo "[7/7] Creating configuration templates..."
mkdir -p "$AGENT_DIR/usr"

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
    "agent_profile": "agent0"
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
ENV_EOF
echo "Created usr/.env template."
fi

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
echo "  1. Log out and back in (for Docker group):"
echo "     exit"
echo ""
echo "  2. Edit the config with your LLM server details:"
echo "     nano ~/agent-zero/usr/settings.json"
echo ""
echo "  3. Start AgentZero:"
echo "     cd ~/agent-zero"
echo "     source venv/bin/activate"
echo "     python run_ui.py --dockerized=true"
echo ""
echo "  4. Open in your browser:"
echo "     http://<your_pi_ip>:5000"
echo ""
echo "============================================"

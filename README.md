# 🤖 AgentZero on Raspberry Pi 4

> **Run [AgentZero](https://github.com/frdel/agent-zero) on a Raspberry Pi 4, powered by a local LLM on a separate GPU server.**

This guide walks you through deploying AgentZero on a Raspberry Pi 4 (ARM64), connecting it to a local LLM running on a separate machine via an OpenAI-compatible API (e.g. llama.cpp, Ollama, vLLM, etc.).

No cloud APIs required. Fully private. Fully local.

---

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Hardware Used](#-hardware-used)
- [Prerequisites](#-prerequisites)
- [Why Python 3.12?](#-why-python-312)
- [Installation](#-installation)
  - [Option A: Automated Setup Script](#option-a-automated-setup-script)
  - [Option B: Manual Step-by-Step](#option-b-manual-step-by-step)
- [Configuration](#-configuration)
- [Running AgentZero](#-running-agentzero)
- [Telegram Integration (Optional)](#-telegram-integration-optional)
- [Troubleshooting](#-troubleshooting)
- [ARM64 Compatibility Notes](#-arm64-compatibility-notes)

---

## 🏗 Architecture Overview

```
┌──────────────────────┐         ┌──────────────────────────┐
│   Raspberry Pi 4     │  HTTP   │   GPU Server (LLM Host)  │
│                      │────────▶│                          │
│  • AgentZero (Web UI)│         │  • llama-server / Ollama │
│  • Python 3.12       │◀────────│  • Your model (GGUF etc) │
│  • Embeddings (local)│         │  • OpenAI-compatible API │
└──────────────────────┘         └──────────────────────────┘
        ▲
        │ Browser / Telegram
        │
   ┌────┴────┐
   │  You 🧑 │
   └─────────┘
```

**The Pi handles**: Agent logic, web UI, local embeddings, tool execution (Docker sandbox)

**The GPU server handles**: LLM inference (the heavy compute)

---

## 🖥 Hardware Used

### Raspberry Pi (Agent Host)

| Component | Spec |
|-----------|------|
| **Model** | Raspberry Pi 4 Model B |
| **RAM** | 4GB+ recommended (8GB ideal) |
| **Storage** | 32GB+ microSD or USB SSD |
| **OS** | Raspberry Pi OS (Debian Bookworm, 64-bit) |
| **Architecture** | ARM64 / aarch64 |

### GPU Server (LLM Host)

Any machine capable of running your chosen LLM. Examples:

| Component | Example Setup |
|-----------|---------------|
| **Machine** | Mini PC, desktop, or server with GPU |
| **GPU** | NVIDIA GPU with 12GB+ VRAM (or CPU-only for smaller models) |
| **Software** | [llama.cpp](https://github.com/ggml-org/llama.cpp), [Ollama](https://ollama.com), [vLLM](https://github.com/vllm-project/vllm), or any OpenAI-compatible server |
| **Model** | Any GGUF/safetensors model (e.g. Qwen, Llama, Mistral) |

> **Note:** The GPU server must be reachable from the Pi over your local network.

---

## ✅ Prerequisites

Before starting, ensure you have:

- [ ] Raspberry Pi 4 with Raspberry Pi OS **64-bit** installed and SSH access
- [ ] A separate machine running an LLM with an **OpenAI-compatible API** endpoint
- [ ] Both machines on the same local network
- [ ] The LLM server's IP address and port (e.g., `http://192.168.1.100:8080`)

---

## ❓ Why Python 3.12?

Raspberry Pi OS (Bookworm) ships with **Python 3.13**, but several AgentZero dependencies are **not compatible** with it:

| Package | Python 3.13 Issue |
|---------|-------------------|
| `kokoro` (TTS) | No wheels available |
| `onnxruntime` | Build failures on ARM64 |
| `langchain-unstructured` | Dependency conflicts |

**Solution:** We install **Python 3.12** via [pyenv](https://github.com/pyenv/pyenv), which compiles from source and provides full compatibility. The system Python 3.13 is left untouched.

### Additional ARM64 Fixes Applied

| Package | Issue on Pi 4 | Fix |
|---------|---------------|-----|
| `torch` | "Illegal instruction" with v2.10.0 (uses ARMv8.2+ instructions Pi 4 lacks) | Pin to `torch==2.5.1` from PyTorch CPU index |
| `faiss-cpu` | SVE detection crash in v1.11.0 | Downgrade to `faiss-cpu==1.8.0.post1` |
| `sentence-transformers` | Import error with `transformers` 4.57+ | Upgrade to latest compatible version |

---

## 🚀 Installation

### Option A: Automated Setup Script

The included `setup_agentzero.sh` handles everything automatically:

```bash
# 1. Copy the script to your Pi (from your local machine)
scp setup_agentzero.sh <pi_user>@<pi_ip>:~/

# 2. SSH into the Pi
ssh <pi_user>@<pi_ip>

# 3. Run the script
chmod +x ~/setup_agentzero.sh
bash ~/setup_agentzero.sh
```

> ⏱ **Estimated time:** 30–40 minutes (Python compilation is the bottleneck)

After the script completes, skip to [Configuration](#-configuration).

---

### Option B: Manual Step-by-Step

#### Step 1: Install Build Dependencies

```bash
sudo apt update
sudo apt install -y make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev wget curl \
    llvm libncursesw5-dev xz-utils tk-dev \
    libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev git
```

#### Step 2: Install pyenv & Python 3.12

```bash
# Install pyenv
curl https://pyenv.run | bash

# Add to shell
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(pyenv init -)"' >> ~/.bashrc
source ~/.bashrc

# Compile Python 3.12 (~20-30 min on Pi 4)
pyenv install 3.12.10
```

#### Step 3: Clone AgentZero & Create Virtual Environment

```bash
git clone https://github.com/frdel/agent-zero.git ~/agent-zero
cd ~/agent-zero

~/.pyenv/versions/3.12.10/bin/python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
```

#### Step 4: Install Dependencies with ARM64 Fixes

```bash
# Install base requirements
pip install -r requirements.txt
pip install -r requirements2.txt

# Fix torch — downgrade to ARM-compatible version
pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
pip install torchvision==0.20.1

# Fix faiss — downgrade to avoid SVE detection crash
pip install faiss-cpu==1.8.0.post1

# Fix sentence-transformers compatibility
pip install sentence-transformers --upgrade
```

#### Step 5: Install Docker (for agent sandbox)

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for group permissions to take effect
```

---

## ⚙ Configuration

### 1. Configure the LLM Connection

Create/edit `usr/settings.json` with your LLM server details:

```bash
mkdir -p ~/agent-zero/usr
nano ~/agent-zero/usr/settings.json
```

**For llama.cpp / llama-server (OpenAI-compatible):**

```json
{
    "chat_model_provider": "openai",
    "chat_model_name": "<YOUR_MODEL_NAME>",
    "chat_model_api_base": "http://<LLM_SERVER_IP>:<PORT>/v1",
    "chat_model_ctx_length": 32000,
    "chat_model_vision": false,
    "util_model_provider": "openai",
    "util_model_name": "<YOUR_MODEL_NAME>",
    "util_model_api_base": "http://<LLM_SERVER_IP>:<PORT>/v1",
    "util_model_ctx_length": 32000,
    "embed_model_provider": "huggingface",
    "embed_model_name": "sentence-transformers/all-MiniLM-L6-v2",
    "embed_model_api_base": "",
    "browser_model_provider": "openai",
    "browser_model_name": "<YOUR_MODEL_NAME>",
    "browser_model_api_base": "http://<LLM_SERVER_IP>:<PORT>/v1",
    "browser_model_vision": false,
    "agent_profile": "agent0"
}
```

> **Tip:** To find your model name, query your LLM server:
> ```bash
> curl http://<LLM_SERVER_IP>:<PORT>/v1/models
> ```

**For Ollama:**

Use `"chat_model_provider": "ollama"` and set `api_base` to your Ollama server URL **without** `/v1`:
```json
{
    "chat_model_provider": "ollama",
    "chat_model_name": "llama3",
    "chat_model_api_base": "http://<OLLAMA_IP>:11434",
    ...
}
```

### 2. Configure Environment Variables

```bash
nano ~/agent-zero/usr/.env
```

Add the following:

```env
# Required for OpenAI-compatible providers (use any dummy value for local servers)
OPENAI_API_KEY=sk-no-key-required

# Required for AgentZero's internal communication
RFC_PASSWORD=any_password_here

# Bind to all interfaces so you can access from other devices
WEB_UI_HOST=0.0.0.0
```

> If using Ollama instead, add `API_KEY_OLLAMA=sk_no_key_required`

---

## ▶ Running AgentZero

```bash
cd ~/agent-zero
source venv/bin/activate
python run_ui.py --dockerized=true
```

Then open in your browser:

```
http://<raspberry_pi_ip>:5000
```

> **Note:** The `--dockerized=true` flag runs AgentZero in production mode, which avoids development-mode RFC calls to a non-existent orchestrator.

### Running as a Background Service (Optional)

To keep AgentZero running after you close SSH:

```bash
# Using nohup
cd ~/agent-zero && source venv/bin/activate
nohup python run_ui.py --dockerized=true > agentzero.log 2>&1 &

# Or using screen
screen -S agentzero
cd ~/agent-zero && source venv/bin/activate
python run_ui.py --dockerized=true
# Detach with Ctrl+A, then D
# Reattach with: screen -r agentzero
```

---

## 📱 Telegram Integration (Optional)

You can bridge AgentZero to Telegram so you can chat with your agent from your phone.

### Setup

1. **Create a Telegram Bot:**
   - Message [@BotFather](https://t.me/BotFather) on Telegram
   - Send `/newbot` and follow prompts to get your **Bot Token**

2. **Get Your User ID:**
   - Message [@userinfobot](https://t.me/userinfobot) on Telegram
   - Copy your numeric **User ID**

3. **Configure the Bridge:**
   ```bash
   # Install the Telegram dependency
   pip install python-telegram-bot

   # Edit the bridge script
   nano telegram_bridge.py
   ```
   Replace `YOUR_TELEGRAM_BOT_TOKEN` and `ALLOWED_USER_ID` with your values.

4. **Run:**
   ```bash
   python telegram_bridge.py
   ```

> ⚠ **Security:** The `ALLOWED_USER_ID` check ensures only YOU can interact with the agent. Never share your bot token publicly.

---

## 🔧 Troubleshooting

### "Illegal instruction" on startup

**Cause:** A compiled library uses CPU instructions the Pi 4's Cortex-A72 (ARMv8.0) doesn't support.

**Fix:** Ensure you're using the pinned versions:
```bash
pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
pip install faiss-cpu==1.8.0.post1
```

### "No RFC password" error

**Fix:** Add `RFC_PASSWORD=any_password_here` to `usr/.env`

### Web UI not accessible from other devices

**Fix:** Add `WEB_UI_HOST=0.0.0.0` to `usr/.env` and restart.

### "404 Not Found" when sending messages

**Cause:** Wrong provider or API base URL.

**Fix:**
- For llama.cpp/llama-server: Use `"openai"` provider with `/v1` in the URL
- For Ollama: Use `"ollama"` provider **without** `/v1`
- Verify your model name matches exactly: `curl http://<server>:<port>/v1/models`

### Chrome can't connect but Safari works

Chrome's "Private Network Access" restrictions may block HTTP connections to local IPs. Use Safari, Firefox, or try Chrome Incognito mode.

### `RequestsDependencyWarning: urllib3 ...`

This is a harmless version mismatch warning. It does not affect functionality.

---

## 📝 ARM64 Compatibility Notes

The Raspberry Pi 4 uses a Cortex-A72 CPU (ARMv8.0-A). Key constraints:

- **No AVX/AVX2/SSE** — x86-only instructions. Many ML libraries compile with these by default.
- **No SVE** — Scalable Vector Extension, available on ARMv8.2+. The Pi 4 does not have this.
- **PyTorch versions > 2.5.x** may use ARMv8.2+ features, causing "Illegal instruction" crashes.
- **Docker images** for AgentZero are `amd64`-only. That's why we do a native install.
- **piwheels.org** provides pre-compiled ARM wheels for many packages, which pip uses automatically on Raspberry Pi OS.

### Tested Working Package Versions

| Package | Version | Notes |
|---------|---------|-------|
| Python | 3.12.10 | Via pyenv |
| torch | 2.5.1 | From PyTorch CPU index |
| faiss-cpu | 1.8.0.post1 | Avoids SVE/numpy.distutils issues |
| sentence-transformers | latest | Must match transformers version |
| onnxruntime | 1.19.2 | ARM64 wheel from PyPI |
| litellm | 1.79.3 | OpenAI/Ollama routing |

---

## 📄 License

This guide is provided as-is under the MIT License. AgentZero itself has its own license — see [frdel/agent-zero](https://github.com/frdel/agent-zero).

---

## 🙏 Acknowledgments

- [AgentZero](https://github.com/frdel/agent-zero) by frdel
- [pyenv](https://github.com/pyenv/pyenv) for painless Python version management
- [llama.cpp](https://github.com/ggml-org/llama.cpp) for efficient local LLM inference
- [piwheels](https://www.piwheels.org/) for pre-built ARM Python wheels

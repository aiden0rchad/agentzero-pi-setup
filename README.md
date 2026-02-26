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
- [Post-Install Fixes](#-post-install-fixes)
- [Configuration](#-configuration)
- [Running AgentZero](#-running-agentzero)
- [Auto-Start on Boot (systemd)](#-auto-start-on-boot-systemd)
- [Remote Access via Tailscale](#-remote-access-via-tailscale)
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

## 🔨 Post-Install Fixes

After installation, apply these fixes before running AgentZero:

### Create the `/a0` Working Directory

AgentZero's code execution tool expects a `/a0` directory (used as the default working directory inside Docker). Since we're running natively, you must create it manually:

```bash
sudo mkdir -p /a0
sudo chown $USER:$USER /a0
```

> **Without this**, every tool call (terminal commands, file operations, browser agent) will fail with `PermissionError: [Errno 13] Permission denied: '/a0'`.

### Install Playwright Browser Dependencies

If you want AgentZero's **browser agent** to work (for web browsing tasks), install the required system libraries:

```bash
sudo apt-get install -y libatk1.0-0 libatspi2.0-0 libxcomposite1 \
    libxdamage1 libxfixes3 libxrandr2 libgbm1 libxkbcommon0
```

Or let Playwright install them automatically:

```bash
cd ~/agent-zero && source venv/bin/activate
playwright install-deps
```

> **Note:** Running a headless browser on a Pi 4 with 4GB RAM is resource-heavy. If you only need chat and code execution, you can skip this.

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

# IMPORTANT: Password-protect the web UI (without this, anyone on your network can use your agent)
API_KEY_AUTH=choose_a_strong_password_here
```

> If using Ollama instead, also add `API_KEY_OLLAMA=sk_no_key_required`

> ⚠️ **Security:** The `API_KEY_AUTH` setting is critical. Without it, anyone who can reach your Pi's IP can use AgentZero to execute commands, browse the web, and access files on your Pi. Always set this to a strong password.

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

---

## 🔄 Auto-Start on Boot (systemd)

To have AgentZero start automatically when the Pi boots and restart if it crashes:

### 1. Create the service file

```bash
sudo nano /etc/systemd/system/agentzero.service
```

Paste:

```ini
[Unit]
Description=AgentZero AI Agent
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=<YOUR_PI_USERNAME>
WorkingDirectory=/home/<YOUR_PI_USERNAME>/agent-zero
ExecStart=/home/<YOUR_PI_USERNAME>/agent-zero/venv/bin/python run_ui.py --dockerized=true
Restart=on-failure
RestartSec=10
Environment=PATH=/home/<YOUR_PI_USERNAME>/agent-zero/venv/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
```

> Replace `<YOUR_PI_USERNAME>` with your actual username (e.g., `pi`).

### 2. Enable and start

```bash
sudo systemctl daemon-reload
sudo systemctl enable agentzero
sudo systemctl start agentzero
```

### 3. Useful commands

```bash
sudo systemctl status agentzero      # Check status
journalctl -u agentzero -f            # View live logs
sudo systemctl restart agentzero      # Restart after config changes
sudo systemctl stop agentzero         # Stop
```

---

## 🌐 Remote Access via Tailscale

To access AgentZero from your phone or from outside your home network, use [Tailscale](https://tailscale.com) — a zero-config VPN.

### Install Tailscale on the Pi

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Follow the printed URL to authorize the Pi in your Tailscale account.

### Get the Pi's Tailscale IP

```bash
tailscale ip -4
```

This returns a `100.x.y.z` address.

### Access from Any Device

With Tailscale running on your phone/laptop, open:

```
http://100.x.y.z:5000
```

This works from anywhere — home, cellular, coffee shop — as long as both devices are connected to your Tailscale network.

> ⚠️ **Security:** Even though Tailscale is encrypted and private, always set `API_KEY_AUTH` in your `.env` to password-protect the web UI. Tailscale ACLs can further restrict which devices can reach the Pi.

---

## 🔒 Security Considerations

AgentZero is an **autonomous AI agent with code execution capabilities**. When self-hosting, keep these security practices in mind:

| Risk | Mitigation |
|------|------------|
| **Unauthenticated web UI** | Always set `API_KEY_AUTH` in `usr/.env` to require a password |
| **Code execution on host** | Enable Docker sandboxing (`CODE_EXEC_DOCKER_ENABLED=true`) so agent code runs in disposable containers, not directly on your Pi |
| **Network exposure** | Use Tailscale instead of port-forwarding. Never expose port 5000 to the public internet |
| **Prompt injection** | Be cautious when asking the agent to visit untrusted URLs or process untrusted content — malicious prompts could instruct the agent to execute harmful commands |
| **Telegram bot token** | Treat your bot token like a password. If compromised, regenerate it immediately via [@BotFather](https://t.me/BotFather) |
| **`/a0` directory** | The agent has full read/write access to `/a0`. Don't store sensitive files there |

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

> ⚠️ **Security:** The `ALLOWED_USER_ID` check ensures only YOU can interact with the agent. Never share your bot token publicly. If your token is ever compromised, regenerate it immediately via [@BotFather](https://t.me/BotFather) — `/revoke` then `/newbot`.

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

### Chrome/Firefox can't connect but Safari works

**Cause:** On **macOS Sequoia** (15.0+), Apple introduced **Local Network Privacy**. Third-party apps (Chrome, Firefox, etc.) need explicit permission to access devices on your local network. Safari and Terminal are system apps that bypass this restriction.

**Fix (Mac):** Go to **System Settings → Privacy & Security → Local Network** and toggle **ON** for Chrome, Firefox, and any other browser you want to use.

**Fix (iPhone):** Go to **Settings → Privacy & Security → Local Network** and ensure your browser is toggled on. If it doesn't appear in the list, try loading the page first — iOS will prompt you to allow local network access.

> **Tip:** If you're still having trouble on mobile, use [Tailscale](#-remote-access-via-tailscale) and access AgentZero via its `100.x.y.z` Tailscale IP instead of the local IP.

### "Memory consolidation timeout for area fragments"

This is a non-critical warning. AgentZero's background memory consolidation system uses the `util_model` to clean up memories, and the default 60-second timeout can be exceeded by larger/slower models.

**Impact:** None — your chat and agent actions are unaffected. Memories are still saved; they just skip being "consolidated" with older ones.

**Fix (optional):** Use a smaller, faster model for `util_model` (e.g., a 3B-8B model on a separate llama-server port) while keeping your main `chat_model` large.

### PermissionError: `/a0` Permission denied

**Cause:** AgentZero expects a `/a0` working directory (the default inside Docker containers). Running natively, this directory doesn't exist.

**Fix:**
```bash
sudo mkdir -p /a0
sudo chown $USER:$USER /a0
sudo systemctl restart agentzero
```

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

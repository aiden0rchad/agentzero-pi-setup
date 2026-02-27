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
- [Memory Optimization (Important for Pi 4)](#-memory-optimization-important-for-pi-4)
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
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=<YOUR_PI_USERNAME>
WorkingDirectory=/home/<YOUR_PI_USERNAME>/agent-zero
ExecStart=/home/<YOUR_PI_USERNAME>/agent-zero/venv/bin/python run_ui.py --dockerized=true
Restart=on-failure
RestartSec=10
Environment=PATH=/home/<YOUR_PI_USERNAME>/agent-zero/venv/bin:/usr/local/bin:/usr/bin:/bin

# Memory guards — critical on Pi 4 to prevent OOM crashes taking down the whole OS
# MemoryHigh: soft limit, kernel starts reclaiming memory at this point
# MemoryMax: hard limit, systemd kills AgentZero cleanly instead of random OS processes
MemoryHigh=2800M
MemoryMax=3200M
# OOMScoreAdjust: sacrifice AgentZero first if memory gets critical system-wide
OOMScoreAdjust=500

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
sudo systemctl status agentzero        # Check status
sudo journalctl -u agentzero.service -f  # View live logs
sudo systemctl restart agentzero       # Restart after config changes
sudo systemctl stop agentzero          # Stop
```

---

## 💾 Memory Optimization (Important for Pi 4)

The Pi 4's 4GB RAM is tight for AgentZero. Without tuning, the Python process can consume 2–2.5GB and trigger a kernel OOM kill, causing random crashes and restart loops. The setup script handles all of this automatically, but here's what it does and why:

### 1. Add a real swap file (most important)

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Tune swappiness: lower = use RAM longer before swapping
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl vm.swappiness=10
```

> **Note:** The default `zram` swap on Pi OS is just compressed RAM — it doesn't add real memory headroom. A real swap file on the SD card does.

### 2. Disable Kokoro TTS (~500–800MB saved)

Kokoro loads a neural TTS model into RAM at startup even if you never use voice output. Disable it:

```bash
# Add to usr/.env (persists across AgentZero updates)
echo 'A0_SET_tts_kokoro=false' >> ~/agent-zero/usr/.env
```

Or in the AgentZero web UI: **Settings → TTS → disable Kokoro**.

> ⚠️ **Important:** Disabling Kokoro only removes the server-side neural TTS model. Your **browser's built-in Web Speech API** may still speak responses using your OS's system voice. To silence this completely, click the **speaker icon** in the AgentZero chat UI to toggle TTS off, or add `A0_SET_tts_enabled=false` to `usr/.env`.

### 3. Use delayed embedding model loading (~400MB saved at startup)

By default, AgentZero loads the `sentence-transformers` model at startup for memory recall. Delayed loading only loads it when memory recall is actually first needed:

In `usr/settings.json`:
```json
{
    "tts_kokoro": false,
    "memory_recall_delayed": true
}
```

All memory/recall features remain fully enabled — the model just loads on-demand instead of at boot.

### 4. Disable unnecessary system services

Services that waste RAM on a Pi dedicated to AgentZero:

```bash
sudo systemctl stop bluetooth ModemManager avahi-daemon
sudo systemctl disable bluetooth ModemManager avahi-daemon
```

### RAM budget after optimization

| Component | Before | After |
|---|---|---|
| Kokoro TTS | ~600MB | 0MB (disabled) |
| Embedding model (startup) | ~450MB | 0MB (lazy-loaded) |
| Bluetooth/Avahi/ModemManager | ~50MB | 0MB |
| **AgentZero headroom** | ~1.1GB | **~2.5GB** |

### Diagnosing OOM crashes

If AgentZero randomly dies and keeps restarting:

```bash
# Check if the OOM killer struck
dmesg | grep -i "oom\|killed process" | tail -10

# Check how many times the service has restarted
sudo journalctl -u agentzero.service | grep -c "Started"

# Watch memory live
watch -n 2 'free -h'
```

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

### AgentZero randomly crashes and keeps restarting (OOM Kill)

**Cause:** The kernel's OOM killer terminated the Python process because it ran out of memory. This is the most common issue on 4GB Pi 4 units.

**Diagnosis:**
```bash
# Confirm it was an OOM kill
dmesg | grep -i "oom\|killed process" | tail -10

# Watch memory live
watch -n 2 'free -h'
```

**Fix:** Follow the [Memory Optimization](#-memory-optimization-important-for-pi-4) section. Key steps:
1. Add a 4GB swap file
2. Disable Kokoro TTS (`A0_SET_tts_kokoro=false` in `.env`)
3. Enable delayed embedding model loading (`memory_recall_delayed: true` in settings)
4. Add `MemoryMax=3200M` to the systemd service (the setup script does this automatically)

---

### `SyntaxError: positional argument follows keyword argument` (settings.py line ~775)

**Cause:** A bug in Agent Zero's `settings.py` — the `set_root_password()` function has a positional argument (`["chpasswd"]`) placed after a keyword argument (`env=...`). This is a Python syntax error that **prevents Agent Zero from starting entirely**.

**Fix:** Run this on the Pi:
```bash
python3 - << 'EOF'
import sys, os
path = os.path.expanduser('~/agent-zero/python/helpers/settings.py')
with open(path, 'r') as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    if 'subprocess.run(env=' in line and '{"PATH"' in line:
        lines[i] = '    _result = subprocess.run(\n'
        lines[i+1] = '        ["chpasswd"],\n'
        lines.insert(i+2, '        env={"PATH": __import__("os").environ.get("PATH", "") + ":/usr/sbin"},\n')
        with open(path, 'w') as f:
            f.writelines(lines)
        print('Fixed!')
        sys.exit(0)
print('Pattern not found — may already be fixed')
EOF

# Verify no syntax errors remain
python3 -c "import ast; ast.parse(open('~/agent-zero/python/helpers/settings.py').read()); print('OK')"
```

> **Note:** The setup script applies this fix automatically.

---

### `Failed to save settings: chpasswd returned non-zero exit status 1`

**Cause:** When you click Save in the AgentZero settings UI with an empty `root_password` field, AgentZero tries to call `chpasswd` to set the Linux root password (a Docker-container feature). It fails because the password is empty and the process doesn't run as root.

**Fix:** The `root_password` field is only relevant inside the official Docker container — not for native Pi installs. Patch the empty-password guard:
```bash
python3 - << 'EOF'
import os
path = os.path.expanduser('~/agent-zero/python/helpers/settings.py')
with open(path, 'r') as f:
    content = f.read()
old = 'if settings["root_password"] != PASSWORD_PLACEHOLDER:'
new = 'if settings["root_password"] and settings["root_password"] != PASSWORD_PLACEHOLDER:'
if old in content and new not in content:
    content = content.replace(old, new, 1)
    with open(path, 'w') as f:
        f.write(content)
    print('Fixed!')
else:
    print('Already patched or pattern not found')
EOF
```

> **Note:** The setup script applies this fix automatically. Just leave the root password field blank in the UI.

---

### "Illegal instruction" on startup

**Cause:** A compiled library uses CPU instructions the Pi 4's Cortex-A72 (ARMv8.0) doesn't support.

**Fix:** Ensure you're using the pinned versions:
```bash
pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
pip install faiss-cpu==1.8.0.post1
```

---

### "No RFC password" error

**Fix:** Add `RFC_PASSWORD=any_password_here` to `usr/.env`

---

### Web UI not accessible from other devices

**Fix:** Add `WEB_UI_HOST=0.0.0.0` to `usr/.env` and restart.

---

### "404 Not Found" when sending messages

**Cause:** Wrong provider or API base URL.

**Fix:**
- For llama.cpp/llama-server: Use `"openai"` provider with `/v1` in the URL
- For Ollama: Use `"ollama"` provider **without** `/v1`
- Verify your model name matches exactly: `curl http://<server>:<port>/v1/models`

---

### Chrome/Firefox can't connect but Safari works

**Cause:** On **macOS Sequoia** (15.0+), Apple introduced **Local Network Privacy**. Third-party browsers need explicit permission.

**Fix (Mac):** Go to **System Settings → Privacy & Security → Local Network** and toggle **ON** for Chrome/Firefox.

**Fix (iPhone):** Go to **Settings → Privacy & Security → Local Network** and enable for your browser.

---

### "Memory consolidation timeout for area fragments"

This is a non-critical warning. AgentZero's background memory consolidation uses `util_model` and can timeout with larger/slower models.

**Impact:** None — chat and agent actions are unaffected. Memories are still saved.

**Fix (optional):** Use a smaller, faster model for `util_model` while keeping `chat_model` large.

---

### PermissionError: `/a0` Permission denied

**Cause:** AgentZero expects a `/a0` working directory (the default inside Docker containers). Running natively, this directory doesn't exist.

**Fix:**
```bash
sudo mkdir -p /a0
sudo chown $USER:$USER /a0
sudo systemctl restart agentzero
```

---

### TTS voice still speaks after disabling Kokoro

**Cause:** Disabling `tts_kokoro` removes the Kokoro neural model from the server, but AgentZero also supports browser-based TTS via the **Web Speech API** (your OS's built-in voice). These are two independent systems.

**Fix:** Toggle the speaker icon in the AgentZero chat UI to disable all TTS output. To make this permanent for all sessions:

```bash
echo 'A0_SET_tts_enabled=false' >> ~/agent-zero/usr/.env
sudo systemctl restart agentzero.service
```

---

### AgentZero stopped itself after being asked to restart in chat

**Cause:** Agent Zero has full code execution access to the host. If you ask it to "restart itself" in the chat, it will use `pkill -f run_ui.py` to kill its own process. Since the service is managed by systemd, this causes systemd to mark it `inactive (dead)` and stop restarting it (if `Restart=on-failure` and the exit was clean).

**Fix:** Always restart AgentZero from your SSH terminal, never through the chat UI:

```bash
sudo systemctl restart agentzero.service
sudo journalctl -u agentzero.service -f
```

> ⚠️ **Tip:** Never ask the agent to "restart yourself", "kill the server", or run `pkill`/`killall` targeting `run_ui.py`. It will comply and take itself down.

---

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

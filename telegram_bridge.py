import os
import time
import subprocess
import threading
import pty
import select
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes

# ===========================================================
# CONFIGURATION — Fill in your values before running!
# ===========================================================

# Get this from Telegram's @BotFather
TELEGRAM_BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"

# Get this from Telegram's @userinfobot (numeric ID)
# This ensures ONLY you can talk to the agent
ALLOWED_USER_ID = 123456789

# Path to the AgentZero directory on your Pi
AGENT_ZERO_DIR = os.path.expanduser("~/agent-zero")

# ===========================================================

# Global references to the AgentZero pty/subprocess session
agent_pty_master = None
agent_subprocess = None


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Handle /start command"""
    if update.effective_user.id != ALLOWED_USER_ID:
        await update.message.reply_text("Unauthorized user.")
        return
    await update.message.reply_text(
        "🤖 AgentZero Bridge Active.\n"
        "Send a message to forward it to the agent.\n"
        "Commands: /restart - Restart AgentZero"
    )


async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Forward user messages from Telegram to AgentZero's stdin"""
    global agent_pty_master

    if update.effective_user.id != ALLOWED_USER_ID:
        return

    user_text = update.message.text
    if agent_pty_master:
        os.write(agent_pty_master, (user_text + '\n').encode('utf-8'))
    else:
        await update.message.reply_text(
            "AgentZero is not running. Use /restart to start it."
        )


async def restart_agent(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    """Kill the current AgentZero process and start a new one"""
    global agent_subprocess
    if update.effective_user.id != ALLOWED_USER_ID:
        return

    if agent_subprocess:
        agent_subprocess.terminate()
        await update.message.reply_text("♻️ AgentZero terminated. Restarting...")

    start_agent_process(context)
    await update.message.reply_text("✅ AgentZero started.")


def read_agent_output(context: ContextTypes.DEFAULT_TYPE):
    """Background thread: reads AgentZero's stdout and sends to Telegram"""
    global agent_pty_master
    import asyncio

    while True:
        if agent_pty_master is None:
            time.sleep(1)
            continue

        r, _, _ = select.select([agent_pty_master], [], [])
        if r:
            try:
                output = os.read(agent_pty_master, 4096).decode('utf-8', errors='replace')
                if output.strip():
                    # Truncate very long outputs to avoid Telegram message limits
                    if len(output) > 4000:
                        output = output[:4000] + "\n... (truncated)"
                    asyncio.run_coroutine_threadsafe(
                        context.bot.send_message(
                            chat_id=ALLOWED_USER_ID, text=output
                        ),
                        context.application.loop
                    )
            except OSError:
                break


def start_agent_process(context: ContextTypes.DEFAULT_TYPE):
    """Fork a new PTY and run AgentZero inside it"""
    global agent_pty_master, agent_subprocess

    master, slave = pty.openpty()
    agent_pty_master = master

    agent_subprocess = subprocess.Popen(
        ['python3', 'main.py'],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        cwd=AGENT_ZERO_DIR,
        close_fds=True
    )
    os.close(slave)

    # Start background thread to read agent output
    t = threading.Thread(target=read_agent_output, args=(context,), daemon=True)
    t.start()


def main() -> None:
    application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()

    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("restart", restart_agent))
    application.add_handler(
        MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message)
    )

    print("Starting Telegram <-> AgentZero Bridge")
    application.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()

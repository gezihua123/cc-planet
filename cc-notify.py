#!/usr/bin/env python3
"""CC 状态监控 - 提取关键内容并通过飞机通知"""
import sys
import json
import re
import subprocess
import os

BASE = os.path.expanduser("~/bin/cc-plane")
BINARY = os.path.join(BASE, "cc-planet")
MAX_MSG = 24


def truncate(s: str) -> str:
    if len(s) > MAX_MSG:
        s = s[:MAX_MSG] + "…"
    return s


def fly(message: str):
    """触发飞机（防并发）"""
    r = subprocess.run(
        ["pgrep", "-f", "cc-plane/cc-planet"],
        capture_output=True, text=True,
    )
    if r.stdout.strip():
        return  # 已有飞机在飞
    subprocess.Popen(
        ["nohup", BINARY, message],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def handle_pre_tool_use(data: dict):
    """PreToolUse 事件"""
    tool = data.get("tool_name", "")
    if tool != "AskUserQuestion":
        return
    questions = data.get("tool_input", {}).get("questions", [])
    if not questions:
        return
    q = questions[0]
    msg = f"{q.get('header', '')}: {q.get('question', '')}"
    fly(truncate(msg))


def handle_stop(data: dict):
    """Stop 事件 - 使用直接传入的 last_assistant_message 通知"""
    last = data.get("last_assistant_message", "").strip()
    if last:
        # 清理 markdown 语法
        text = re.sub(r"```[^`]*```", "", last)
        text = re.sub(r"`([^`]+)`", r"\1", text)
        text = text.replace("\n", " ").replace("\r", " ")
        text = re.sub(r"\s+", " ", text).strip()
        fly(truncate(f"✅ {text}"))


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return

    if data.get("tool_name"):
        handle_pre_tool_use(data)
    elif data.get("session_id") or data.get("stop_reason"):
        handle_stop(data)


if __name__ == "__main__":
    main()

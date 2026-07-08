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


def extract_last_message(transcript_path: str) -> str:
    """从 transcript 文件提取最后一条 assistant 消息"""
    try:
        with open(transcript_path, "r") as f:
            # 读取最后 100 行即可
            lines = f.readlines()[-100:]
    except Exception:
        return ""

    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("type") != "assistant":
            continue

        message = msg.get("message", {})
        content = message.get("content", [])
        text = ""
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text += block.get("text", "") + " "
        elif isinstance(content, str):
            text = content

        # 清理 markdown 语法
        text = re.sub(r"```[^`]*```", "", text)
        text = re.sub(r"`([^`]+)`", r"\1", text)
        text = text.replace("\n", " ").replace("\r", " ")
        text = re.sub(r"\s+", " ", text).strip()
        # 留余量给 "✅ " 前缀和 "…" 后缀
        if len(text) > 24:
            text = text[:24] + "..."
        if text:
            return text
    return ""


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
    """Stop 事件 - 提取最后一条消息并通知"""
    tp = data.get("transcript_path", "")
    if not tp or not os.path.isfile(tp):
        return
    last = extract_last_message(tp)
    if last:
        fly(truncate(f"✅ {last}"))


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

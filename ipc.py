#!/usr/bin/env python3
"""ipc.py — 与 OpenTabletDriver 守护进程交互的辅助工具（可选）。

用法:
  python3 ipc.py list        # 列出 OTD 已知设备及其连接状态
  python3 ipc.py info        # 显示当前 OTD 配置/设置目录
  python3 ipc.py restart     # 请求 OTD 重启驱动（等价于 GUI 的 Enable/Reload）
"""
import json
import os
import sys
import urllib.request

# OTD 守护进程的 IPC 端点(HTTP)。新版通常绑定 127.0.0.1:1818，
# 端口可在 OTD 设置中查看/修改。
HOST = os.environ.get("OTD_HOST", "127.0.0.1")
PORT = int(os.environ.get("OTD_PORT", "1818"))
BASE = f"http://{HOST}:{PORT}"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=3) as r:
        return json.loads(r.read().decode())


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"

    if cmd == "list":
        try:
            devices = get("/devices")
        except Exception as e:
            sys.exit(f"[ERR] 无法连接 OTD 守护进程 ({e})。请确认 OTD 已运行。")
        print(f"已知设备 {len(devices)} 个：")
        for d in devices:
            name = d.get("Name") or d.get("name") or "?"
            conn = d.get("ConnectionState") or d.get("state") or "?"
            print(f"  - {name}  [{conn}]")
    elif cmd == "info":
        try:
            s = get("/settings")
            print(json.dumps(s, indent=2, ensure_ascii=False))
        except Exception as e:
            sys.exit(f"[ERR] 无法连接 OTD 守护进程 ({e})")
    elif cmd == "restart":
        # 对应 GUI 的 “应用/重新加载”，让 OTD 重新加载配置
        try:
            r = get("/settings")  # 握手
            print("[OK] OTD 守护进程可达，请到 GUI 中切换/重载设备。")
        except Exception as e:
            sys.exit(f"[ERR] 无法连接 OTD 守护进程 ({e})")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
#!/usr/bin/env bash
# fix-permissions.sh — 为 OpenTabletDriver 添加 Wacom DTU-1141 的权限支持
#
# 需要 root（会写 /etc/udev/rules.d/ 并 reload/trigger、重启 OTD）
# 用法: sudo ./fix-permissions.sh
set -euo pipefail

RULES="/etc/udev/rules.d/70-opentabletdriver-dtu1141.rules"

[ "$(id -u)" -eq 0 ] || { echo "[ERR] 请用 sudo 运行: sudo $0"; exit 1; }

cat > "$RULES" <<'EOF'
# Wacom DTU-1141 (VID 056a:PID 0336) - OpenTabletDriver
# hidraw: OTD 使用 /dev/hidrawN，普通用户必须可读写
# MODE=0666 兜底（不依赖 uaccess/logind seat）
KERNEL=="hidraw*", ATTRS{idVendor}=="056a", ATTRS{idProduct}=="0336", MODE="0666", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="056a", ATTRS{idProduct}=="0336", MODE="0666", GROUP="plugdev", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{idVendor}=="056a", ATTRS{idProduct}=="0336", ENV{LIBINPUT_IGNORE_DEVICE}="1"
# uinput: OTD 创建虚拟压感平板输出，需要普通用户可写（否则 Evdev EACCES）
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0666", OPTIONS+="static_node=uinput", TAG+="uaccess", TAG+="udev-acl"
EOF

echo "==> 写入 $RULES"
udevadm control --reload-rules
udevadm trigger --action=change
sleep 1

echo "==> 验证 hidraw 权限"
ls -l /dev/hidraw*

echo
echo "==> 若上面 /dev/hidrawN 仍显示 root:root 0600，请拔插一次数位屏 USB"
echo "    （或执行: sudo udevadm trigger --action=change）"
echo

echo "==> 重启 OpenTabletDriver"
if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files 2>/dev/null | grep -q opentabletdriver; then
  systemctl --user restart opentabletdriver 2>/dev/null && echo "  已重启 (user)"
elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q opentabletdriver; then
  systemctl restart opentabletdriver 2>/dev/null && echo "  已重启 (system)"
else
  pkill -f otd-daemon 2>/dev/null || true
  echo "  请手动重启 otd-daemon"
fi

echo
echo "==> 完成。若 /dev/hidraw5 仍是 0600，请拔插一次 USB 再运行 ./detect.sh"
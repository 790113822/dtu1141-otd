#!/usr/bin/env bash
# install.sh — 为 OpenTabletDriver 安装 Wacom DTU-1141 支持
# 用法:
#   sudo ./install.sh          # 自动检测并安装（配置 JSON + udev 规则）
#   ./install.sh --config-only # 只放配置 JSON，不碰 udev/systemd
#   ./install.sh --help
set -euo pipefail

# ---------- 常量 ----------
CONFIG_NAME="DTU1141"
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/${CONFIG_NAME}.json"
OTD_USER="${SUDO_USER:-$USER}"

# OTD 配置目录候选（按优先级）
# 0.6.x:   ~/.config/OpenTabletDriver/Configurations
# 旧版:    ~/.config/OpenTabletDriver
CONFIG_DIRS=(
  "/home/${OTD_USER}/.config/OpenTabletDriver/Configurations"
  "/home/${OTD_USER}/.config/OpenTabletDriver"
)

UDEV_RULES="/etc/udev/rules.d/70-opentabletdriver.rules"

info()  { echo -e "[\e[1;32mINFO\e[0m] $*"; }
warn()  { echo -e "[\e[1;33mWARN\e[0m] $*"; }
die()   { echo -e "[\e[1;31mERR\e[0m] $*" >&2; exit 1; }

usage() {
  sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

[ "${1:-}" = "--help" ] && usage
[ ! -f "$CONFIG_FILE" ] && die "找不到 $CONFIG_FILE，请把它和本脚本放在同一目录。"

# ---------- 1. 安装配置 JSON ----------
install_config() {
  local dest=""
  for d in "${CONFIG_DIRS[@]}"; do
    if [ -d "$d" ] && [ -w "$d" ]; then
      dest="$d/${CONFIG_NAME}.json"
      break
    fi
  done

  # 用户目录若被 sudo 执行，权限可能不允许写入，退回用目标用户
  if [ -z "$dest" ]; then
    for d in "${CONFIG_DIRS[@]}"; do
      if [ -d "$d" ] || sudo -u "$OTD_USER" mkdir -p "$d" 2>/dev/null; then
        dest="$d/${CONFIG_NAME}.json"
        break
      fi
    done
  fi
  [ -z "$dest" ] && die "找不到 OpenTabletDriver 配置目录，请手动复制 ${CONFIG_FILE} 到合适位置。"

  if [ -f "$dest" ] && ! cmp -s "$dest" "$CONFIG_FILE"; then
    warn "目标已存在且内容不同，备份为 ${dest}.bak"
    cp -a "$dest" "${dest}.bak"
  fi
  install -m 0644 -o "$OTD_USER" -g "$OTD_USER" "$CONFIG_FILE" "$dest" \
    || install -m 0644 "$CONFIG_FILE" "$dest"
  info "已安装配置: $dest"
}

# ---------- 2. 安装 udev 规则 ----------
install_udev() {
  # OTD 通过 /dev/hidrawN 访问数位板；必须给 hidraw 节点授权（纯 SUBSYSTEM=="usb" 不覆盖 hidraw）
  cat > "$UDEV_RULES" <<'EOF'
# OpenTabletDriver - Wacom DTU-1141 (VID 056a)
# hidraw: OTD 使用 /dev/hidrawN，需普通用户可读写
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="056a", MODE="0666", GROUP="plugdev", TAG+="uaccess"
# /dev/bus/usb 兜底
SUBSYSTEM=="usb", ATTRS{idVendor}=="056a", MODE="0666", GROUP="plugdev", TAG+="uaccess"
EOF
  info "已写入 udev 规则: $UDEV_RULES"
  udevadm control --reload-rules 2>/dev/null && udevadm trigger 2>/dev/null && \
    info "udev 规则已重载并触发" || warn "请手动执行: sudo udevadm control --reload-rules && sudo udevadm trigger"
}

# ---------- 3. 重启 OTD 守护进程 ----------
restart_daemon() {
  if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files 2>/dev/null | grep -q opentabletdriver; then
    systemctl --user restart opentabletdriver 2>/dev/null && info "已重启 opentabletdriver (systemd user)" \
      || warn "请手动重启 OpenTabletDriver 后台服务"
  elif systemctl list-unit-files 2>/dev/null | grep -q opentabletdriver; then
    systemctl restart opentabletdriver 2>/dev/null && info "已重启 opentabletdriver (systemd system)" \
      || warn "请手动重启 OpenTabletDriver 后台服务"
  else
    warn "未检测到 systemd 服务，请手动重启 OpenTabletDriver"
  fi
}

# ---------- 主流程 ----------
CONFIG_ONLY=0
[ "${1:-}" = "--config-only" ] && CONFIG_ONLY=1

install_config
if [ "$CONFIG_ONLY" -eq 0 ]; then
  install_udev
fi
restart_daemon

info "完成。若 OTD 已运行，请在 GUI 中重新加载/选择 'Wacom DTU-1141'。"
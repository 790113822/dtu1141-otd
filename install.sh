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

# OTD 0.6.x 只扫描 Configurations 子目录；放在应用数据根目录会被静默忽略。
OTD_CONFIG_ROOT="/home/${OTD_USER}/.config/OpenTabletDriver"
CONFIG_DIR="${OTD_CONFIG_ROOT}/Configurations"

# 使用独立文件名，避免覆盖 /usr/lib/udev/rules.d/70-opentabletdriver.rules 官方规则
UDEV_RULES="/etc/udev/rules.d/71-opentabletdriver-dtu1141.rules"
LEGACY_UDEV_RULES="/etc/udev/rules.d/70-opentabletdriver.rules"

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
  # OTD 以当前用户运行，目录属主必须正确（脚本可能通过 sudo 执行）
  if [ "$(id -u)" -eq 0 ] && [ "$OTD_USER" != "root" ]; then
    sudo -u "$OTD_USER" mkdir -p "$CONFIG_DIR" \
      || die "无法创建配置目录 $CONFIG_DIR"
  else
    mkdir -p "$CONFIG_DIR" || die "无法创建配置目录 $CONFIG_DIR"
  fi

  local dest="${CONFIG_DIR}/${CONFIG_NAME}.json"
  if [ -f "$dest" ] && ! cmp -s "$dest" "$CONFIG_FILE"; then
    warn "目标已存在且内容不同，备份为 ${dest}.bak"
    cp -a "$dest" "${dest}.bak"
  fi

  if [ "$(id -u)" -eq 0 ] && [ "$OTD_USER" != "root" ]; then
    install -m 0644 -o "$OTD_USER" "$CONFIG_FILE" "$dest"
  else
    install -m 0644 "$CONFIG_FILE" "$dest"
  fi
  info "已安装配置: $dest"

  # 旧版脚本可能把配置放在应用数据根目录，OTD 不会读取，移到 .bak 以免误判
  local legacy="${OTD_CONFIG_ROOT}/${CONFIG_NAME}.json"
  if [ -f "$legacy" ]; then
    mv -f "$legacy" "${legacy}.bak" 2>/dev/null || rm -f "$legacy"
    warn "已停用旧位置配置 $legacy（OTD 只读取 Configurations 子目录）"
  fi
}

# ---------- 2. 安装 udev 规则 ----------
install_udev() {
  # OTD 通过 /dev/hidrawN 访问数位板；必须给 hidraw 节点授权（纯 SUBSYSTEM=="usb" 不覆盖 hidraw）
  cat > "$UDEV_RULES" <<'EOF'
# OpenTabletDriver - Wacom DTU-1141 (VID 056a:PID 0336)
# hidraw: OTD 使用 /dev/hidrawN，普通用户可读写
KERNEL=="hidraw*", ATTRS{idVendor}=="056a", ATTRS{idProduct}=="0336", MODE="0666", GROUP="plugdev", TAG+="uaccess"
# /dev/bus/usb 兜底
SUBSYSTEM=="usb", ATTRS{idVendor}=="056a", ATTRS{idProduct}=="0336", MODE="0666", GROUP="plugdev", TAG+="uaccess"
# 避免内核 wacom/libinput 抢走设备
SUBSYSTEM=="input", ATTRS{idVendor}=="056a", ATTRS{idProduct}=="0336", ENV{LIBINPUT_IGNORE_DEVICE}="1"
# uinput: OTD 创建虚拟压感平板输出
KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0666", OPTIONS+="static_node=uinput", TAG+="uaccess", TAG+="udev-acl"
EOF

  # 旧版 install.sh 会写入 /etc/udev/rules.d/70-opentabletdriver.rules，
  # 与官方 /usr/lib/udev/rules.d/70-opentabletdriver.rules 同名并覆盖它（影响其它品牌数位板）。
  if [ -f "$LEGACY_UDEV_RULES" ] && \
     head -n1 "$LEGACY_UDEV_RULES" | grep -q 'OpenTabletDriver - Wacom DTU-1141'; then
    rm -f "$LEGACY_UDEV_RULES"
    warn "已删除会覆盖官方规则的旧文件: $LEGACY_UDEV_RULES"
  fi

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
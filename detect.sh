#!/usr/bin/env bash
# detect.sh — 检测 Wacom DTU-1141 是否接入 USB，并校验 OTD 配置的 PID 是否匹配
# 用法:  ./detect.sh
set -uo pipefail

VID="056a"          # Wacom
PID_EXPECT="0336"   # DTU-1141 (内核 wacom_features_0x336 "Wacom DTU1141")
PID_DEC_EXPECT=$((16#0336))

info() { echo -e "[\e[1;32mINFO\e[0m] $*"; }
warn() { echo -e "[\e[1;33mWARN\e[0m] $*"; }

scan_usb() {
  if command -v lsusb >/dev/null 2>&1; then
    lsusb -d "${VID}:" 2>/dev/null
  else
    # 无 lsusb 时从 /sys 兜底
    for d in /sys/bus/usb/devices/*/; do
      [ -f "$d/idVendor" ] || continue
      v=$(cat "$d/idVendor" 2>/dev/null)
      [ "$v" = "$VID" ] || continue
      p=$(cat "$d/idProduct" 2>/dev/null)
      n=$(cat "$d/product" 2>/dev/null || echo "?")
      echo "Bus device $d: $VID:$p  ($n)"
    done
  fi
}

echo "===== 扫描 Wacom 设备 (VID $VID) ====="
found=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  found=1
  echo "$line"
  pid=$(echo "$line" | sed -nE 's/.*ID '"$VID"':([0-9a-fA-F]{4}).*/\1/p')
  [ -z "$pid" ] && pid=$(echo "$line" | grep -oE 'idProduct="?[0-9a-fA-F]{4}' | grep -oE '[0-9a-fA-F]{4}$' | head -1)
  if [ "${pid,,}" = "$PID_EXPECT" ]; then
    info "检测到 DTU-1141 (PID $pid) ✔"
  else
    warn "找到 Wacom 设备但 PID=$pid 不是期望的 $PID_EXPECT"
  fi
done < <(scan_usb)

if [ "$found" -eq 0 ]; then
  warn "未发现任何 Wacom 设备。请确认数位屏已通过 USB 连接。"
  exit 1
fi
echo
echo "===== 校验 OTD 配置中的 PID ====="
cfg="${1:-./DTU1141.json}"
if [ -f "$cfg" ]; then
  grep -q "\"ProductID\": $PID_DEC_EXPECT" "$cfg" \
    && info "配置 $cfg 中的 ProductID=$PID_DEC_EXPECT 与设备匹配 ✔" \
    || warn "配置 $cfg 中的 ProductID 与设备 (${PID_DEC_EXPECT}) 不一致，请修改为 $PID_DEC_EXPECT"
else
  warn "未找到配置 $cfg（可传入路径，如 ./detect.sh /path/to/DTU1141.json）"
fi
echo
echo "提示: 如果 OTD 无法识别，多半是 InputReportLength 或解析器插件问题。"
echo "  1) 确认已执行 sudo ./fix-permissions.sh（/dev/hidraw5 应可读）"
echo "  2) 确认已用 build-plugin.sh 生成并在 Plugins 里有 DTU 解析器 dll"
echo "  3) OTD 日志位于 ~/.config/OpenTabletDriver/Logs/，若报 'Report length X is invalid'，"
echo "     请把配置中的 InputReportLength 改成 X（当前为 64/65）。"
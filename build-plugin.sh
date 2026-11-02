#!/usr/bin/env bash
# build-plugin.sh — 编译 DTU-1141 报告解析器插件 (OpenTabletDriver.DTU.dll)
#
# 前置: 已安装 .NET SDK 8.0+
#   Debian/Ubuntu:  sudo apt install dotnet-sdk-8.0
#   Arch:            sudo pacman -S dotnet-sdk
#   官方:            https://dotnet.microsoft.com/download
#
# 产物: src/bin/Release/net8.0/OpenTabletDriver.DTU.dll
# 然后把该 dll 放入 OTD 插件目录（自动完成）。
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
PROJ="src/Dtu1141.csproj"
OUT="src/bin/Release/net8.0"
PLUGIN_JSON="$PWD/DTU1141.json"
DEST_DIR="${1:-$HOME/.config/OpenTabletDriver/Plugins}"

if ! command -v dotnet >/dev/null 2>&1; then
  echo "[ERR] 未找到 dotnet SDK。请先安装:"
  echo "  Debian/Ubuntu: sudo apt install dotnet-sdk-8.0"
  echo "  Arch:          sudo pacman -S dotnet-sdk"
  exit 1
fi

echo "==> 还原并编译 $PROJ"
dotnet restore "$PROJ"
dotnet build "$PROJ" -c Release

DLL="$OUT/OpenTabletDriver.DTU.dll"
[ -f "$DLL" ] || { echo "[ERR] 编译产物不存在: $DLL"; exit 1; }

CONFIG_DIR="$HOME/.config/OpenTabletDriver/Configurations"

echo "==> 安装到 $DEST_DIR"
# 0.6.x 的插件加载: ~/.config/OpenTabletDriver/Plugins/<插件名>/xxx.dll
mkdir -p "$DEST_DIR/Dtu1141"
cp -v "$DLL" "$DEST_DIR/Dtu1141/OpenTabletDriver.DTU.dll"

# OTD 0.6.x 只从 Configurations 子目录加载设备配置
mkdir -p "$CONFIG_DIR"
cp -v "$PLUGIN_JSON" "$CONFIG_DIR/DTU1141.json"
# 清理旧版脚本放在应用数据根目录的配置（OTD 不会读取）
rm -f "$HOME/.config/OpenTabletDriver/DTU1141.json"

echo
echo "==> 完成。请重启 OTD 并在 GUI 中选择 'Wacom DTU-1141'。"
echo "    若 OTD 日志报 'Unable to find plugin matching name ...'，确认插件目录里的 dll 已被加载。"
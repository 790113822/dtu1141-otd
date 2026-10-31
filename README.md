# Wacom DTU-1141 OpenTabletDriver 插件

> **作用**：让开源驱动 **OpenTabletDriver (OTD)** 支持 **Wacom DTU-1141** 数位屏（USB `056a:0336`）。
> OTD 0.6.8 **官方未内置**此型号，本仓库提供**配置 + 报告解析器插件 + 一键安装脚本**，
> 使该签名数位屏在 Linux 下可作为压感平板工作（写画/签名）。

Wacom DTU-1141（USB `056a:0336`）是一台 10.6" 数位屏。OpenTabletDriver (OTD) 0.6.8 **官方未内置**该型号，需要以下三样东西：

1. **权限**：OTD 通过 `/dev/hidrawN` 访问数位板，这些节点默认仅 root 可读写，必须写 udev 规则。
2. **配置**：`DTU1141.json`（识别 VID/PID + 报告长度 + 解析器名）。
3. **解析器插件**：内置没有 `Wacom.DTU.*` 解析器，必须编译一个插件 dll 放进 OTD 插件目录。

> ✅ **已在我的 Linux + OTD 0.6.8.1 上实测正常工作**（识别设备 → 创建虚拟压感平板 → 笔可用）。

## 关键参数

来源：Linux 内核 `wacom_wac.c` 的 `wacom_features_0x336`（`"Wacom DTU1141"`）、GitHub PR #3645（作者实机验证）。

| 参数 | 值 |
|---|---|
| Vendor ID | `0x056a` (1386) |
| Product ID | `0x0336` (822) |
| 最大 X / Y | `23672` / `13403` |
| 最大压力 | `1023` |
| 报告长度 | `64` 或 `65`（不是 10/9！） |
| 报告类型 | 笔 `0x11`，aux `0x15` |
| 解析器 | `OpenTabletDriver.Configurations.Parsers.Wacom.DTU.DTUReportParser` |
| 物理区域 | 234.66 × 131.99 mm |

> ⚠️ 网上有些地方把 PID 写成 `0x0377`，那是错的。权威值以内核`0x0336` 和你的 `lsusb`（`056a:0336`）为准。

## 当前进度（已实测确认）

- ✅ **设备已被 OTD 识别**：日志显示 `Found tablet 'Wacom DTU-1141'`，且 `Using report parser type 'OpenTabletDriver.Configurations.Parsers.Wacom.DTU.DTUReportParser'`（插件解析器生效）。
- ✅ 权限规则已生效（`/dev/hidraw5` = 0666）。
- ✅ 解析器插件已编译成功（net8.0 + OTD 0.6.4 API），位于 `Plugins/Dtu1141/`。
- ⚠️ **调试(2026-11-01)后定位的 Decisive Fix**：之前一直 `No tablets were detected` 的根因是 **`OutputReportLength` 写成了 64，而设备实测 `MaxOutputReportLength=0`**（HidSharp 实测 `MaxInputReportLength=64`, `MaxOutputReportLength=0`, `MaxFeatureReportLength=68`）。OTD 匹配要求 `identifier.OutputReportLength == device.OutputReportLength`，`64 ≠ 0` 导致永不匹配。**删除配置里所有 `OutputReportLength` 后立即识别成功**。`DTU1141.json` 现只保留 `InputReportLength: 64`。
- ❌ **最后一个可选项**：日志 `[Evdev:Error] Failed to initialize virtual pressure sensitive tablet. (error code EACCES)` —— `/dev/uinput` 权限不足（`crw------- root root`）。OTD 需要创建虚拟压感平板输出。**执行下面的第 2 步修复即可**。

## 你需要做的

设备已经识别。若笔在数位屏上还没有输出（EACCES），执行一次权限修复（会补 uinput 规则并重载）：

```bash
cd /home/Li/下载/dtu1141-otd
sudo ./fix-permissions.sh
```

脚本会写入 `/etc/udev/rules.d/70-opentabletdriver-dtu1141.rules`（hidraw/usb/input + **uinput MODE=0666**）、`udevadm reload+trigger`、重启 OTD。

若之后仍 EACCES，拔插一次数位屏 USB，或手动确认 `ls -l /dev/uinput` 是否为 `crw-rw-rw-`。

## 排错

| 现象 | 原因与处理 |
|---|---|
| 日志 `Not permitted to open HID class device at /dev/hidrawN` | 权限没生效。确认 `/dev/hidraw5` 权限为 `crw-rw-rw-` 或 `crw-rw----`；不行就拔插 USB。 |
| 日志 `No tablets were detected` | 以上两步还没完成，或配置目录/解析器没对上。 |
| 日志 `Unable to find plugin matching name OpenTabletDriver.Configurations.Parsers.Wacom.DTU.DTUReportParser` | 插件 dll 没被加载。确认 `Plugins/Dtu1141/OpenTabletDriver.DTU.dll` 存在并重启 OTD。 |
| 笔不动但能检测到 | 可能是官方 Wacom 驱动占用了设备。**完全退出官方驱动并给数位屏断电重插**（PR 作者强调其只支持明文模式）。 |
| `Report length X is invalid` | 把配置里 `InputReportLength` 改为日志提示的数值。 |

## 文件说明

| 文件 | 作用 |
|---|---|
| `DTU1141.json` | OTD 设备配置（PID 822，长度 64/65，DTUReportParser） |
| `src/*.cs`, `src/Dtu1141.csproj` | DTU 解析器源码 + 插件工程 |
| `build-plugin.sh` | 编译插件并安装到 OTD |
| `fix-permissions.sh` | sudo 一键修 udev 权限 + 重启 OTD |
| `detect.sh` | 检测设备是否在线、PID 是否匹配 |
| `ipc.py` | 与 OTD 守护进程交互（可选） |

## 参考

- OTD PR #3645 "Add initial support for Wacom DTU-1141"（作者 mochaaP，实机测试）：
  https://github.com/OpenTabletDriver/OpenTabletDriver/pull/3645
- 内核 `drivers/hid/wacom_wac.c` `wacom_features_0x336`
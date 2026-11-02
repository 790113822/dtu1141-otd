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
- ✅ 权限规则已生效（`/dev/hidraw4` = 0666，`/dev/uinput` = 0666）。
- ✅ 解析器插件已编译成功（net8.0 + OTD 0.6.4 API），位于 `Plugins/Dtu1141/`。
- ⚠️ **2026-11-02 失效根因**：`DTU1141.json` 被放到了 `~/.config/OpenTabletDriver/` 根目录，而 OTD 0.6.8.1 **只扫描 `~/.config/OpenTabletDriver/Configurations/` 子目录**。因此日志里只有 362 个内置型号，完全没有 `Wacom DTU-1141`，最后报 `No tablets were detected.`。把配置移入 `Configurations/` 后立即识别成功。
  - 旧版 `install.sh` 在 `Configurations/` 不存在时会退回到应用数据根目录，这是设计缺陷，已修正。
  - 旧版 `install.sh` 还会写 `/etc/udev/rules.d/70-opentabletdriver.rules`，与官方 `/usr/lib/udev/rules.d/70-opentabletdriver.rules` **同名并覆盖它**；已改为独立的 `71-opentabletdriver-dtu1141.rules`。
- ✅ **OutputReportLength 必须省略**：OTD 匹配要求 `identifier.OutputReportLength == device.OutputReportLength`，而设备实测 `MaxOutputReportLength=0`。`DTU1141.json` 只保留 `InputReportLength: 64`。
- ✅ **uinput 正常**：日志 `Successfully initialized virtual pressure sensitive tablet. (code NONE)`；`/dev/uinput` 现为 `crw-rw-rw-`。
- ✅ **2026-11-02 已修复并实测**：配置移入 `Configurations/` 后，日志出现 `Found tablet 'Wacom DTU-1141'`，解析器与虚拟压感平板均初始化成功。

## 你需要做的

配置位置已修正，重新打开/重启 OpenTabletDriver 即可。若想顺便清掉旧版脚本生成的冲突 udev 文件（它会覆盖官方 `70-opentabletdriver.rules`），执行一次：

```bash
cd /home/Li/下载/dtu1141-otd-main
sudo ./fix-permissions.sh
```

脚本会写入 `/etc/udev/rules.d/70-opentabletdriver-dtu1141.rules`（hidraw/usb/input + **uinput MODE=0666**）、删除冲突的旧文件、`udevadm reload+trigger`，并尝试重启 OTD。

若之后仍 EACCES，拔插一次数位屏 USB，或手动确认 `ls -l /dev/uinput` 是否为 `crw-rw-rw-`。

## 排错

| 现象 | 原因与处理 |
|---|---|
| 日志 `No tablets were detected.` 且搜索列表里**没有** `Wacom DTU-1141` | 配置文件不在 `~/.config/OpenTabletDriver/Configurations/DTU1141.json`。OTD 0.6.x 不会读取应用数据根目录下的 JSON。用 `./detect.sh` 可直接检查。 |
| 日志 `Not permitted to open HID class device at /dev/hidrawN` | 权限没生效。确认对应 hidraw（DTU-1141 是 `056a:0336` 那个，本机为 `/dev/hidraw4`）权限为 `crw-rw-rw-`；不行就拔插 USB。 |
| 日志 `Unable to find plugin matching name OpenTabletDriver.Configurations.Parsers.Wacom.DTU.DTUReportParser` | 插件 dll 没被加载。确认 `Plugins/Dtu1141/OpenTabletDriver.DTU.dll` 存在并重启 OTD。 |
| 日志 `Evdev: Failed to initialize ... EACCES` | `/dev/uinput` 权限不足，运行 `sudo ./fix-permissions.sh`。 |
| 笔不动但能检测到 | 可能是官方 Wacom 驱动占用了设备。**完全退出官方驱动并给数位屏断电重插**（PR 作者强调其只支持明文模式）。 |
| `Report length X is invalid` | 把配置里 `InputReportLength` 改为日志提示的数值。 |
| 其它品牌数位板突然不工作 | 检查 `/etc/udev/rules.d/` 是否有旧版脚本生成的 `70-opentabletdriver.rules`（会覆盖官方同名规则），删除后执行 `sudo udevadm control --reload-rules && sudo udevadm trigger`。 |

## 文件说明

| 文件 | 作用 |
|---|---|
| `DTU1141.json` | OTD 设备配置（PID 822，长度 64，DTUReportParser）；脚本会安装到 `~/.config/OpenTabletDriver/Configurations/` |
| `src/*.cs`, `src/Dtu1141.csproj` | DTU 解析器源码 + 插件工程 |
| `build-plugin.sh` | 编译插件并安装到 OTD |
| `fix-permissions.sh` | sudo 一键修 udev 权限 + 重启 OTD |
| `detect.sh` | 检测设备是否在线、PID 是否匹配 |
| `ipc.py` | 与 OTD 守护进程交互（可选） |

## 参考

- OTD PR #3645 "Add initial support for Wacom DTU-1141"（作者 mochaaP，实机测试）：
  https://github.com/OpenTabletDriver/OpenTabletDriver/pull/3645
- 内核 `drivers/hid/wacom_wac.c` `wacom_features_0x336`
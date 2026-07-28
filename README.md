# 遥控快捷桥 / Remote Shortcut Bridge

`遥控快捷桥` 把 Xiaomi RC003 蓝牙遥控器当作一个可自定义的外接快捷键控制器。

它不读取遥控器麦克风、不传输音频、不切换系统麦克风，也不需要虚拟音频驱动。语音输入仍由 Typeless 直接使用 DJI Mic Mini；本应用只把 RC003 的语音键转换成 Typeless 的启动/停止快捷键。

## 工作链路

```text
RC003 语音键
  -> macOS Bluetooth HID
  -> 遥控快捷桥
  -> Control + Option
  -> Typeless
  -> DJI Mic Mini
```

默认情况下，每次完整按下并松开 RC003 语音键，会发送一次 `Control + Option`。在 Typeless 中把同一组合设置为语音输入快捷键后，第一次按遥控器开始，第二次按遥控器结束。

## 设备与系统

- Xiaomi Bluetooth Remote 2 Pro / RC003
- macOS 11 或更高版本
- Apple Silicon 或 Intel Mac
- Typeless 与 DJI Mic Mini 由用户在系统和 Typeless 中自行配置

应用只匹配 RC003 的 HID 标识 `VID 0x2717 / PID 0x32B8`。遥控器先由 macOS 蓝牙设置完成配对，本应用本身不建立 BLE 连接。

## 安装

测试版文件名：

```text
遥控快捷桥-0.1.1-test.2-macos.dmg
```

1. 打开 DMG，把 `遥控快捷桥.app` 拖入 `Applications`。
2. 从“应用程序”打开应用。
3. 在系统设置中允许“输入监控”和“辅助功能”。
4. 返回应用，点击重新连接。

本测试版没有 Developer ID，也没有 Apple 公证。本机发布流程优先使用名为 `Remote Shortcut Bridge Local Code Signing` 的自签名身份，以便本机更新时保持稳定的代码身份；其他机器仍会看到未公证应用的安全提示。

## Typeless 与 DJI Mic Mini

1. 在 macOS 或 Typeless 中保持 DJI Mic Mini 为录音输入。
2. 在 Typeless 中把语音输入快捷键设为 `Control + Option`。
3. 按一下 RC003 语音键开始输入。
4. 再按一下结束输入。

应用不接触 DJI Mic Mini 的音频。没有 RC003 时，原来的键盘 `Control + Option` 仍照常工作。

## 默认映射

| RC003 按键 | 默认动作 |
| --- | --- |
| 语音 | Control + Option |
| 电源 | Escape |
| 上 / 下 / 左 / 右 | 对应方向键 |
| OK | Return |
| 返回 | Delete |
| 音量 + / - | 系统音量 + / - |
| 主页 | 显示桌面 |
| 菜单 | Control（可保持） |
| TV | Command + Tab |

按住菜单键再按方向键，会发送 `Control + 方向键`，可直接使用 macOS 的 Mission Control、App Exposé 与桌面切换。遥控器上的修饰键会一直保持到物理松开，因此也能与其他遥控器按键组成快捷键。

设置窗口列出全部 13 个按键。每一项都可以重新录制任意普通按键、组合键或仅修饰键组合；键盘菜单可直接选择 Control、Option、Shift、Command，垃圾桶可清除映射。录制 `Control + Up` 一类系统快捷键时，应用会暂时截获按键，避免 Mission Control 抢先响应。改动自动保存；“恢复默认映射”可恢复上表。

## 权限

- 输入监控：读取 RC003 的 HID 报告。
- 辅助功能：向当前应用发送用户配置的快捷键。

应用不声明麦克风或应用级蓝牙隐私权限。权限被撤销、遥控器断连、映射被修改或应用退出时，运行时会释放所有仍按住的合成按键。

## 本地构建

```bash
./scripts/test.sh
./scripts/swift-package.sh test
./scripts/create-local-signing-identity.sh
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/build-app.sh --universal
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/verify-app.sh --universal
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/build-dmg.sh
RSB_REQUIRE_LOCAL_SIGNING=1 ./scripts/verify-dmg.sh
```

详细流程见 [docs/LOCAL_RELEASE.md](docs/LOCAL_RELEASE.md)。

## 来源与许可

本仓库 fork 自 [nijez/open-voice-bridge](https://github.com/nijez/open-voice-bridge)。RC003 HID 标识与 usage 映射的更早参考来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

代码按 `GPL-3.0-only` 发布。实物图及所示商标的权利仍归各自权利人所有。

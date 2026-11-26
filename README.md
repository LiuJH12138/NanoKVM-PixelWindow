# NanoKVM PixelWindow

我用一台 Mac 和一块 **Sipeed NanoKVM-USB 标准版**操作 Windows 笔记本。Windows 输出 1080p，而 Mac 接的是 4K 显示器。把采集画面铺满屏幕时，文字也被放大了。我想在 Mac 桌面上留一块区域给 Windows，看清小字，旁边还能放自己的应用，于是做了这个 Swift 原生窗口。

窗口里只有被控电脑的画面。默认情况下，一个采集像素对应一个窗口缓冲区像素。在我的 4K 显示器使用 2× 显示缩放时，窗口占 **960 × 540 个 macOS 坐标点**，实际显示 **1920 × 1080 个像素**。也可以拖大窗口看细节，再双击边沿回到原始大小。

## 下载安装

在 macOS 14 或更新版本上，下载 DMG，双击打开，将「NanoKVM 原生窗口」拖入「Applications（应用程序）」文件夹。同一份安装包支持 Intel Mac 和 Apple 芯片 Mac。[下载 v1.1 通用安装包](https://github.com/LiuJH12138/NanoKVM-PixelWindow/releases/download/v1.1/NanoKVM-PixelWindow-1.1-macOS-universal.dmg) · [所有版本与校验值](https://github.com/LiuJH12138/NanoKVM-PixelWindow/releases)

此版本采用本地临时签名，尚未经过 Apple 公证。如果首次打开时 macOS 提示无法验证开发者，请确认下载来源并按[苹果的说明](https://support.apple.com/zh-cn/102445)操作。

## 使用的硬件

这是我为 Sipeed NanoKVM-USB 编写的第三方 macOS 客户端。NanoKVM-USB 硬件和官方软件由 Sipeed 提供。应用通过 AVFoundation 读取 USB 视频，通过 USB 串口把 Mac 的键鼠操作发送到被控电脑。[Sipeed 产品介绍](https://wiki.sipeed.com/hardware/zh/kvm/NanoKVM_USB/introduction.html) · [Sipeed 官方代码仓库](https://github.com/sipeed/NanoKVM-USB)

| 连接 | 用途 |
| --- | --- |
| 主控 Mac → NanoKVM 的 Host USB-C | Mac 接收视频并发送键鼠操作 |
| Windows 笔记本的 HDMI 输出 → NanoKVM 的 HDMI IN | 采集 Windows 桌面 |
| Windows 笔记本的 USB → NanoKVM 的 Target USB-C | Windows 接收键鼠输入 |

显示器可以继续接在 Mac 上。需要用另一块显示器直接看同一路 Windows 画面时，再接 NanoKVM 的 HDMI 环出。[官方接线与上手教程](https://wiki.sipeed.com/hardware/zh/kvm/NanoKVM_USB/quick_start.html)

## 在 Mac 上构建和运行

工程使用 Swift、AppKit、AVFoundation 和 IOKit。部署目标为 macOS 14 或更新版本，编译需要包含 macOS 15 或更新 SDK 的 Xcode 工具链。脚本会为当前 Mac 的处理器架构编译并在本地签名。

```sh
git clone https://github.com/LiuJH12138/NanoKVM-PixelWindow.git
cd NanoKVM-PixelWindow
./build.sh "$PWD/.build/NanoKVM 原生窗口.app"
open "$PWD/.build/NanoKVM 原生窗口.app"
```

首次打开时允许摄像头权限，macOS 会把 HDMI 采集卡识别为 USB 摄像头。再从系统菜单栏的 **控制** 菜单选择 NanoKVM 对应的串口。应用会记住选择。如果之前用过官方浏览器版，请先关闭占用串口的控制页。

## 操作

| 操作 | 效果 |
| --- | --- |
| 在画面内点击、打字或滚动 | 操作被控电脑，画面内的双击也会传给 Windows |
| 按住 Option 拖动画面 | 在 Mac 桌面上移动窗口 |
| 拖动任意边缘或角 | 按视频宽高比缩放 |
| 双击边缘或角 | 恢复原生像素大小，桌面空间不足时等比缩小 |
| Command + W 或 Command + Q | 关闭窗口或退出应用 |

## 兼容范围与画质

我用 Intel Mac、4K 显示器、Windows 笔记本和 NanoKVM-USB 标准版验证了 1080p 采集、边角缩放和双击复原。当前识别的视频设备为 `USB3 Video`（USB ID `345f:2131`），串口为 CH340（`1a86:7523`）。其他硬件版本可能使用不同的标识。

如果小字发糊，先在 Windows 的 **设置 → 系统 → 屏幕 → 高级显示** 中选择 NanoKVM 对应的外接屏。我这台电脑原来用 1920 × 1200 的桌面输出 1920 × 1080 的 HDMI 信号。把「桌面模式」和「活动信号模式」都调成 **1920 × 1080、60 Hz** 后，文字明显更清楚。这里的 60 Hz 指 Windows 输出的刷新率，实际采集帧率还取决于 USB 连接和主控设备。[Sipeed 画质排查说明](https://wiki.sipeed.com/hardware/zh/kvm/NanoKVM_USB/faq.html)

习惯用 Chrome 的用户也可以使用 Sipeed 提供的浏览器版。[官方本地部署教程](https://wiki.sipeed.com/hardware/zh/kvm/NanoKVM_USB/deployment.html)

作者：[LiuJH12138](https://github.com/LiuJH12138)

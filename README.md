# 含章可贞

<p align="center">
  <img src="Resources/AppIcon.png" width="160" alt="含章可贞图标：坤卦">
</p>

macOS 菜单栏休息提醒。默认每工作 25 分钟，全屏停下 1 分钟。

> 含章可贞。或从王事，无成有终。
>
> ——《易·坤》六三

名字取自坤卦。地势坤，君子以厚德载物；六三说的是才德含蓄于内，守正即可。这枚图标因此是 **坤卦䷁**，六条阴爻。

菜单栏与休息画面显示的是 **时卦**：按本地时钟每分钟换一卦，依文王卦序循环六十四卦，并写出卦名与卦辞。工作为行，休息为止。

## 做什么

- 藏在菜单栏，不占 Dock
- 卦象每分钟一变，可见卦名、卦序、卦辞
- 到点后遮住全部屏幕，提醒看向远处
- 可暂停、立刻休息、跳过这次休息
- 可改工作 / 休息时长
- 可选提示音、开机即行
- Mac 睡眠时会暂停计时，醒来再续

系统通知文案：

| 时刻 | 标题 |
| --- | --- |
| 开始休息 | 艮 · 时止则止 |
| 继续工作 | 乾 · 时行则行 |

## 环境

- macOS 14 或更高
- 命令行工具即可（`xcode-select --install`），不必装完整 Xcode
- Apple Silicon 已验证；Intel 未测

## 安装

```bash
git clone https://github.com/kayzhou/coco-timer.git
cd coco-timer
make install
```

会生成 `含章可贞.app` 并复制到 `/Applications`。之后可用聚焦搜索「含章可贞」打开。

只想本地跑一下、不装进应用程序：

```bash
make run
```

## 使用

启动后看屏幕右上角的倒计时。点它：

| 按钮 | 含义 |
| --- | --- |
| 且止 / 再行 | 暂停或继续 |
| 入艮 | 现在就休息 |
| 仍行 | 跳过这次休息 |
| 行 / 止 | 工作和休息时长 |
| 止时遮住屏幕 | 休息时是否全屏遮挡 |
| 钟声 | 提示音 |
| 开机即行 | 登录时自动启动 |
| 重起 | 从一轮工作重新计时 |

休息画面可用 `Esc` 或点「仍行」提前结束。第一次运行时，系统会询问通知权限。

## 从源码构建

```
make app      # 生成 dist/含章可贞.app
make install  # 装到 /Applications
make run      # 构建并打开
make clean
```

`make icon` 会按坤卦重画应用图标。应用本身是 Swift 6 + AppKit，无第三方依赖。

```
Sources/
  YixiApp.swift              入口
  TimerModel.swift           行止计时
  StatusUI.swift             菜单栏与面板
  OverlayController.swift    休息时的全屏遮罩
  Theme.swift                爻画与颜色
  NotificationService.swift  通知与提示音
Resources/Info.plist
scripts/make_icon.swift      坤卦图标
```

## 说明

计时与偏好都存在本机 `UserDefaults`，不联网。全屏遮罩只盖在最上层，不会读取其他应用的内容。开机启动用系统的 `SMAppService`，应用需要在「应用程序」文件夹里才比较稳。

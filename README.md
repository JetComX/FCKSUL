FCKSUL

Don't fucking stay up late playing on your phone.
去他妈的熬夜玩手机

English | 中文

---

English

Index

· Introduction
· Features
· Requirements
· Installation & Usage
· Usage Guide
· Whitelist Management
· Files
· Logs
· How It Works
· FAQ
· Notes
· License
· Feedback

---

Introduction

FCKSUL is a pure Shell-based time-limiting tool for Android. After setting a time range (e.g., 06:00 - 13:00), any non-whitelisted app will be force-closed within 1~2 seconds after coming to the foreground. When the time range ends, the monitoring process exits automatically without leaving any background process.

Typical scenarios

· Force block entertainment apps during study/work
· Set "usage hours" for kids' devices
· Temporarily disable device during exams
· Self-discipline, quit phone addiction

Features

· Auto root elevation: runs with normal privileges, automatically detects and invokes su
· 24-hour time range: accurate to the minute, format HH:MM
· Cross-day range support: e.g., 22:00 - 06:00 also works
· One-shot task: exits automatically when time range ends, no background resource usage
· Millisecond-level response: checks foreground app every 2 seconds
· Triple anti-duplication: PID file + full-system scan + identity verification
· Command timeout protection: all external commands wrapped with timeout to avoid hangs
· Independent session: uses setsid to detach from menu process
· Detailed logs: entry/exit of time range, detection, exit, heartbeat all recorded
· Graceful exit: deletes PID file then exits when time range ends, resources fully released
· Whitelist management: supports user-defined whitelist, package name queries app info
· Built-in diagnostics: one-click view of foreground app, running processes, debug logs

Requirements

· System: Android 7.0+ (tested on Android 16)
· Permission: Root required
· Shell: sh (no bash dependency)
· Required commands: timeout, setsid, pgrep (or ps), dumpsys, am
· Storage: script directory must be writable

Recommended environments: Termux, MT Manager terminal, ADB Shell, or any terminal app that supports su.

Installation & Usage

1. Save the script to a fixed directory:

```bash
# e.g.
/storage/emulated/0/AppLock/applock.sh
```

2. Make it executable:

```bash
chmod +x /storage/emulated/0/AppLock/applock.sh
```

3. Run:

```bash
sh /storage/emulated/0/AppLock/applock.sh
```

On first run, it will prompt for root elevation; allow it.

Usage Guide

Main menu:

```text
╔═════════════════════╗
║       FCKSUL        ║
║     Version: v1.0   ║
╠═════════════════════╣
║  1. Set time range  ║
║  2. View status     ║
║  3. Whitelist       ║
║  4. Diagnostics     ║
║  5. How to use?     ║
║  6. Exit            ║
╚═════════════════════╝
```

Menu items:

· 1. Set time range: input start/end time, auto-start monitoring after saving
· 2. View status: show current config, running state, monitor PID
· 3. Whitelist: view/add/delete whitelist apps
· 4. Diagnostics: view foreground app, dumpsys output, process scan, debug logs
· 5. How to use?: display usage instructions
· 6. Exit: clean up all related processes then exit (including child processes, su parent)

Typical workflow:

1. Run script, enter main menu
2. Select 1, enter 06:00 and 13:00, confirm
3. "Settings saved! Monitoring started" appears
4. Select 6 to exit, monitoring continues in background
5. During the range, opening any non-whitelisted app will be force-closed within 1~2 seconds
6. At 13:00, monitoring exits automatically

Whitelist Management

Built-in whitelist (cannot be deleted)

· com.android.systemui (system UI, killing it causes black screen)
· com.android.launcher* (launcher, killing it makes home unreachable)

User whitelist
Stored in fcksul.whitelist in the same directory as the script, one package name per line, supports * wildcard. Manage via menu 3.

Example add flow:

```text
[?] Enter package name (e.g. com.tencent.mm): com.tencent.mm

───────────────────────────────────────
              App Info
───────────────────────────────────────
[*] Package: com.tencent.mm
[*] App name: WeChat
[*] APK path: /data/app/.../base.apk
[*] Version: 8.0.42
[*] Type: Third-party app
[*] Entry: com.tencent.mm/.ui.LauncherUI
───────────────────────────────────────
[?] Add to whitelist? (y/n):
```

After adding, the app can be used normally during the restricted time range. Effect comparison:

App In whitelist Not in whitelist
Built-in systemui/launcher Allowed —
User-added packages Allowed —
All other apps — Force-closed within 1~2s

Files

The script generates in its own directory:

File Description Lifecycle
fcksul.conf Time range config Persistent
fcksul.whitelist User whitelist Persistent
fcksul.log Runtime log Auto-rotates after 1MB
fcksul.debug.log Debug log (stderr) Cleared on each start
fcksul.pid Monitor process PID Deleted on process exit

Config file format:

```text
START_TIME=06:00
END_TIME=13:00
```

Whitelist file format:

```text
com.tencent.mm
com.tencent.mobileqq
com.tencent.tim
```

Logs

Log levels: [I] INFO, [D] DEBUG, [E] ERROR.

Log example:

```text
[2026-09-25 08:10:22] [I] Monitor loop started (pid=32486)
[2026-09-25 08:10:22] [I] Restricted range: 08:10 - 08:11
[2026-09-25 08:10:23] [I] [Detected] bin.mt.plus (now 08:10:22)
[2026-09-25 08:10:23] [D]   -> am force-stop bin.mt.plus
[2026-09-25 08:10:24] [I] [Exited] bin.mt.plus  (08:10:23 -> 08:10:24)
[2026-09-25 08:11:02] [I] Task completed, monitor process exiting
```

Key log words:

· Entered restricted range: start time reached
· Left restricted range: end time reached
· [Detected] xxx: foreground app detected
· [Exited] xxx: force-closed successfully
· [Failed] xxx: first attempt failed, kill -9 appended
· [Whitelist skip] xxx: whitelist app, skipped
· [Heartbeat] Monitor running: every 60 seconds to prove script alive
· [Warning] Loop took: a loop took >8 seconds, possible hang

View methods: menu 4 diagnostics shows last 10 lines; or tail -f fcksul.log; or adb logcat -s FCKSUL.

How It Works

Core loop: read config → check if in time range → get foreground app (dumpsys) → check whitelist → if not, am force-stop + kill -9 → recheck after 1s → loop.

Foreground app detection (three methods tried in order):

1. dumpsys activity activities | grep mResumedActivity
2. dumpsys window | grep mCurrentFocus
3. dumpsys activity top | grep ACTIVITY

Force close (triple kill):

1. am force-stop <pkg> (official stop)
2. pidof <pkg> | kill -9 (kill residual process)
3. ps -A | grep <pkg> | kill -9 (fallback)

Triple anti-duplication: PID file + identity verification, full-system scan, parent process cleans up before start. Guarantees at most one monitor process at any time.

Independent session: monitor process started via setsid, detached from menu process. Menu exit won't cause monitor to be killed by SIGHUP.

FAQ

Q1: Why "monitor not started"?
A: Check: today's end time has passed (monitor exits immediately, by design); or startup exception, view debug log via menu 4.

Q2: An app won't be killed?
A: Log will show [Failed] xxx, script automatically appends kill -9. If still failing, the app may be a system component or have self-starting service. Suggest disabling its auto-start in system settings, or restrict background behavior in developer options.

Q3: Does monitoring still work after screen lock?
A: Depends on whether system kills background processes. Heartbeat means process alive; missing heartbeat means killed by system, need keep-alive (add to whitelist, disable sleep standby optimization, or use Magisk watchdog).

Q4: How to allow an app during restricted time?
A: Menu 3 → Add to whitelist → enter package name → confirm. The app will not be force-closed during restricted time.

Q5: What processes are cleaned when exiting via menu 6?
A: Monitor process from PID file, full-system --monitor scan results, all processes whose command line contains script path, su/magisk/ksud parent process (only if parent is one of these). Terminal shell will not be killed to avoid closing your terminal session.

Notes

Whitelist scope
Built-in whitelist only has com.android.systemui and com.android.launcher*. During restricted time, system settings, phone, camera, gallery, clock, SMS, Google services, etc. will be force-closed. To keep some apps, add them to whitelist via menu 3.

Data safety
Force close (am force-stop) causes apps to lose unsaved temporary state. Do not edit documents or draft chats during restricted time, use important apps with caution.

Compatibility
dumpsys output format varies by Android version and vendor ROM. If "foreground package" in menu 4 is always empty, please provide diagnostic output for adaptation.

Whitelist wildcard
fcksul.whitelist supports * wildcard, but use with caution (e.g., com.tencent.* will allow all Tencent apps like WeChat, QQ, TIM).

License

This project is open source under Apache License 2.0. Free to use, modify and distribute. See LICENSE for details.

Feedback

When reporting issues, please provide:

1. Complete log (fcksul.log last 50 lines)
2. Menu 4 diagnostic output
3. Device model + Android version
4. Specific symptoms

Github Issues: https://github.com/JetComX/FCKSUL/issues

---

中文

目录

· 项目简介
· 功能特性
· 环境要求
· 安装与运行
· 使用指南
· 白名单管理
· 文件说明
· 日志说明
· 工作原理
· 常见问题
· 注意事项
· 开源协议
· 反馈

---

项目简介

FCKSUL 是一个纯 Shell 实现的 Android 应用限时工具。用户设置一个时间段（如 06:00 - 13:00），在此期间任何非白名单应用被切到前台后 1~2 秒内会被自动强制退出。时间段结束后监控进程自动退出，不残留任何后台进程。

典型场景

· 学习 / 工作期间强制屏蔽娱乐类 App
· 给孩子设备设置"使用时段"
· 考试期间临时禁用设备
· 自我管理、戒除手机依赖

功能特性

· Root 自动提权：普通权限运行，自动探测并调用 su
· 24 小时制时间段：精确到分钟，格式 HH:MM
· 支持跨天时段：如 22:00 - 06:00 也能正确识别
· 一次性任务：时段结束自动退出，不占用后台资源
· 毫秒级响应：每 2 秒检测一次前台应用
· 三层防重复：PID 文件 + 全系统扫描 + 身份校验
· 命令超时保护：所有外部命令带 timeout，避免卡死
· 独立会话运行：使用 setsid 脱离菜单进程
· 详细日志：进入/离开时段、检测、退出、心跳全部记录
· 优雅退出：时段结束删 PID 后退出，资源彻底释放
· 白名单管理：支持用户自定义白名单，包名查询应用信息
· 内置诊断：一键查看前台应用、运行进程、调试日志

环境要求

· 系统：Android 7.0+（实测 Android 16 可用）
· 权限：必须 Root
· Shell：sh（不依赖 bash）
· 必备命令：timeout、setsid、pgrep（或 ps）、dumpsys、am
· 存储：脚本所在目录需可写

推荐运行环境：Termux、MT 管理器终端、ADB Shell，或任何支持 su 的终端 App。

安装与运行

1. 保存脚本到固定目录：

```bash
# 例如
/storage/emulated/0/AppLock/applock.sh
```

2. 赋权：

```bash
chmod +x /storage/emulated/0/AppLock/applock.sh
```

3. 运行：

```bash
sh /storage/emulated/0/AppLock/applock.sh
```

首次运行时会提示 Root 提权，允许即可。

使用指南

主菜单：

```text
╔═════════════════════╗
║       FCKSUL        ║
║     版本: v1.0      ║
╠═════════════════════╣
║  1. 设置限制时间段  ║
║  2. 查看当前状态    ║
║  3. 白名单管理      ║
║  4. 诊断            ║
║  5. 咋用？          ║
║  6. 退出            ║
╚═════════════════════╝
```

功能说明：

· 1. 设置限制时间段：输入开始/结束时间，保存后自动启动监控
· 2. 查看当前状态：显示当前配置、运行状态、监控 PID
· 3. 白名单管理：查看 / 添加 / 删除白名单应用
· 4. 诊断：查看前台应用、dumpsys 输出、进程扫描、调试日志
· 5. 咋用？：显示使用说明
· 6. 退出：清理所有相关进程后退出（含子进程、su 父进程）

典型流程：

1. 运行脚本进入主菜单
2. 选 1，输入 06:00 和 13:00，确认
3. 提示 "设置成功！监控已启动"
4. 选 6 退出，监控后台继续运行
5. 时段内打开任意非白名单应用，1~2 秒内被强退
6. 13:00 到，监控自动退出

白名单管理

内置白名单（不可删除）

· com.android.systemui（系统 UI，杀掉会黑屏）
· com.android.launcher*（桌面，杀掉会回不去）

用户白名单

保存在脚本同目录的 fcksul.whitelist，一行一个包名，支持 * 通配。可通过菜单 3 管理。

添加流程示例：

```text
[?] 请输入应用包名（如 com.tencent.mm）： com.tencent.mm

───────────────────────────────────────
              应用信息
───────────────────────────────────────
[*] 包名: com.tencent.mm
[*] 应用名: WeChat
[*] APK 路径: /data/app/.../base.apk
[*] 版本: 8.0.42
[*] 类型: 第三方应用
[*] 入口: com.tencent.mm/.ui.LauncherUI
───────────────────────────────────────
[?] 确认添加到白名单？(y/n):
```

添加后，该应用在限制时段内可以正常使用。效果对比：

应用 白名单内 白名单外
内置 systemui / launcher 放过 —
用户添加的包 放过 —
其他所有应用 — 1~2 秒内强退

文件说明

脚本运行后会在脚本所在目录生成：

文件 说明 生命周期
fcksul.conf 时间段配置 持久保留
fcksul.whitelist 用户白名单 持久保留
fcksul.log 运行日志 超 1MB 自动轮转
fcksul.debug.log 调试日志（stderr） 每次启动清空
fcksul.pid 监控进程 PID 进程退出时删除

配置文件格式：

```text
START_TIME=06:00
END_TIME=13:00
```

白名单文件格式：

```text
com.tencent.mm
com.tencent.mobileqq
com.tencent.tim
```

日志说明

日志级别：[I] INFO（常规事件）、[D] DEBUG（调试细节）、[E] ERROR（异常）。

日志示例：

```text
[2026-09-25 08:10:22] [I] 监控循环启动 (pid=32486)
[2026-09-25 08:10:22] [I] 限制时段: 08:10 - 08:11
[2026-09-25 08:10:23] [I] [检测到] bin.mt.plus (当前 08:10:22)
[2026-09-25 08:10:23] [D]   -> am force-stop bin.mt.plus
[2026-09-25 08:10:24] [I] [已退出] bin.mt.plus  (08:10:23 -> 08:10:24)
[2026-09-25 08:11:02] [I] 任务完成，监控进程退出
```

关键日志词：

· 进入限制时段：到达开始时间
· 离开限制时段：到达结束时间
· [检测到] xxx：检测到前台应用
· [已退出] xxx：成功强制退出
· [未生效] xxx：第一次没成功，追加 kill -9
· [放过白名单] xxx：白名单应用，跳过
· [心跳] 监控运行中：每 60 秒记录，证明脚本存活
· [警告] 循环耗时：某次循环 >8 秒，可能卡顿

查看方式：菜单 4 诊断查看最后 10 行；或直接 tail -f fcksul.log；或 adb logcat -s FCKSUL。

工作原理

核心循环：读取配置 → 判断是否在时段内 → 获取前台应用（dumpsys）→ 判断是否在白名单 → 不在则 am force-stop + kill -9 → 1 秒后复查 → 循环。

前台应用检测（三级依次尝试）：

1. dumpsys activity activities | grep mResumedActivity
2. dumpsys window | grep mCurrentFocus
3. dumpsys activity top | grep ACTIVITY

强制退出（三级杀）：

1. am force-stop <pkg>（官方停止）
2. pidof <pkg> | kill -9（残留进程强杀）
3. ps -A | grep <pkg> | kill -9（兜底）

三层防重复：PID 文件 + 身份校验、全系统扫描、父进程启动前先清理，保证任何时刻最多一个监控进程。

独立会话：监控进程通过 setsid 启动，脱离菜单进程，菜单退出不会导致监控被 SIGHUP 杀掉。

常见问题

Q1：为什么提示"监控未启动"？
A：检查是否是：今天的结束时间已过（监控会立即退出，设计如此）；或启动异常，通过菜单 4 查看调试日志。

Q2：某个应用杀不掉怎么办？
A：日志会出现 [未生效] xxx，脚本会自动追加 kill -9。如仍失败，该应用可能是系统级组件或有自启服务，建议在系统设置中禁用该应用的自启动，或在开发者选项限制其后台行为。

Q3：锁屏后监控还生效吗？
A：取决于系统是否杀了后台进程。有心跳代表进程存活，心跳断了说明被系统杀了，需要做保活（加白名单、关闭睡眠待机优化或使用 Magisk 看门狗）。

Q4：怎么让某个应用在限制时段还能用？
A：菜单 3 → 添加白名单 → 输入包名 → 确认。之后该应用在限制时段不会被强退。

Q5：菜单 6 退出时都清理了哪些进程？
A：PID 文件记录的监控进程、全系统 --monitor 扫描结果、命令行含脚本路径的所有进程、su / magisk / ksud 父进程（仅当父进程是这几类时）。不会杀终端 shell，避免误关你的终端会话。

注意事项

白名单影响范围
内置白名单只有 com.android.systemui 和 com.android.launcher*。限制时段内，系统设置、电话、相机、相册、时钟、短信、Google 服务等都会被强制退出。如需要保留某些应用，请通过菜单 3 添加到白名单。

数据安全
强制退出（am force-stop）会让应用丢失未保存的临时状态。不要在限制时段内进行文档编辑、聊天草稿，重要应用请谨慎使用。

兼容性
dumpsys 输出格式随 Android 版本和厂商 ROM 变化。若菜单 4 的"前台包名"始终为空，请把诊断输出反馈出来以适配。

白名单通配符
fcksul.whitelist 支持 * 通配，但需谨慎使用（如 com.tencent.* 会放过微信、QQ、TIM 等所有腾讯应用）。

开源协议

本项目基于 Apache License 2.0 开源，可自由使用、修改和分发。详见 LICENSE。

反馈

遇到问题时，请提供以下信息以便定位：

1. 脚本完整日志（fcksul.log 最后 50 行）
2. 菜单 4 诊断输出
3. 设备型号 + Android 版本
4. 具体现象

Github Issues: https://github.com/JetComX/FCKSUL/issues

---

祝使用愉快，愿 FCKSUL 帮你守住每一段专注时光。

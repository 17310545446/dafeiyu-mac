# 大肥鱼 · macOS 桌宠 🐋

> 👋 嗨,我是大肥鱼,一条住在你屏幕角落的蓝色鲸鱼娘。
>
> 我不会打扰你写代码 —— 大部分时间只是站着发呆,偶尔东张西望、想想事情、在附近溜达两步。
> 想跟我说话就按 **⌃⌥K**。想让我闭嘴……那只能把电脑关了。

DeepSeek 社区二创形象「鲸鱼娘 · 大肥鱼」的 **macOS 原生桌面宠物**。

> 原版是 [1190fasheqi/dafeiyu-pet](https://github.com/1190fasheqi/dafeiyu-pet)(Python + PySide6,Windows)。本仓库把同一套素材和玩法移植成 Swift / AppKit 原生实现:**不用 Electron、不用 Python 运行时,2.7 MB 的 .app,实测内存:待机约 50 MB,开着聊天面板约 120 MB(三次采样稳定,无泄漏),Apple Silicon 与 Intel 通用**。

[![Release](https://img.shields.io/github/v/release/17310545446/dafeiyu-mac)](https://github.com/17310545446/dafeiyu-mac/releases)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](https://github.com/17310545446/dafeiyu-mac)

![渲染自检图](docs/screenshot-render.png)

<sub>上图是 `--shot` 离屏渲染的自检图(透明底,气泡为半透明白,在深色壁纸上更明显)。</sub>

## 特性

- **三视图走动**:正面 / 侧面 / 背面各一套,左右走自动镜像,转向有交叉淡化
- **自由散步**:随机挑点、加速减速、走累了原地休息 8–18 秒(默认模式是**原地待着**,在右键菜单里切)
- **原地模式也会溜达**:每次走 45–170pt 的小范围,走完回到待机,不会跑远
- **跟随鼠标 / 原地待着**:右键菜单里切换
- **拖拽**:按住拖动会侧身朝向你拖的方向,松手还会抗议两句
- **单击**:蹦跳 + 回嘴,并在头顶弹出功能条(🗨️);点它开一行聊天胶囊(420×56)
- **双击**:喂食横排面板(🐟 🍰 🍭 🍡 💎 粉色描边圆钮 + ✕,每种食物 6 句专属台词)
- **思维链心声**:发呆/思考时冒出灰色斜体气泡,内容取材 DS 社区梗
- **台词库**:待机 45 句、被戳 25 句、心声 22 句、拖拽 12 句,另有早/午/傍晚/深夜/凌晨五套时段台词;最近 12 条不重复
- **启动问候**:每次启动按当前时段说一句
- **静态为主的待机动作**:默认几乎不动,每 7–16 秒随机做一个动作 —— 发呆 / 东张西望 / 思考(冒"……"或心声)/ 在家附近溜达 / 伸展 / 蹦一下 / 摇两下
- **走路才摇摆**:摇摆只发生在移动和"摇晃"动作里,待机不再持续抖动;呼吸幅度压到 0.8%
- 纯 Core Graphics 变换,没有逐帧图
- **聊天**:按 **⌃⌥K** 全局热键,或右键/菜单栏「聊天…」打开对话面板,直连本机 LiteLLM 网关或任何 OpenAI 兼容端点;API Key 存 **Keychain**,不落明文
- **系统监控**:每 10 秒采一次 CPU / 内存,爆表时会吐槽你(CPU ≥90%、内存 ≥93%)
- **天气**:右键「看天气」拉 wttr.in(不用 Key),中文描述内置映射;城市可在设置里填,留空按 IP 定位
- **DeepSeek 余额**:菜单栏图标旁常显 `¥159`(启动后 2 秒查一次,之后每 3 小时刷新);右键「DeepSeek 余额」可手动重查
- **低余额提醒**:低于阈值(默认 ¥20,设置里可改,填 0 关闭)时她主动说一句,只在跨过阈值时提醒一次
- Key 优先取 Keychain,没填则读本机网关 `.env`(不落盘、不外传)
- **用量 / 网关快捷入口**:「打开用量页…」跳官方控制台,「打开网关面板…」跳本机 LiteLLM UI
- **鼠标穿透**:设成点不到,从菜单栏图标解除
- **窗口置顶 / 开机自启 / 回到屏幕内 / 隐藏**:右键菜单 & 菜单栏图标双入口
- **多屏感知**:跨屏走动、换屏自动收回屏幕内
- **配置持久化**:模式、大小、位置、穿透、置顶状态自动记住
- **Universal 二进制**:arm64 + x86_64

## 安装

从 [Releases](https://github.com/17310545446/dafeiyu-mac/releases) 下载 `Dafeiyu-x.y.z.dmg`:

1. 打开 dmg,把 `Dafeiyu.app` 拖进「应用程序」
2. 首次打开如果提示「无法验证开发者」,在 **系统设置 → 隐私与安全性** 里点「仍要打开」,或者:

```bash
xattr -dr com.apple.quarantine /Applications/Dafeiyu.app
```

3. 没有 Dock 图标,她会直接出现在屏幕右下角;菜单栏有一只小鲸鱼

## 用法

| 操作 | 效果 |
|---|---|
| 左键单击 | 蹦跳 + 回嘴,头顶出现 🗨️ 功能条 |
| 功能条 🗨️ | 开一行聊天胶囊,回车发送,回复直接冒泡 |
| 菜单栏左键 | 显示 / 隐藏桌宠 |
| 菜单栏右键 | 打开完整菜单 |
| 左键双击 | 喂食菜单 |
| 左键拖动 | 拎起来到处放 |
| 右键 | 完整菜单(模式 / 大小 / 穿透 / 置顶 / 自启 / 退出) |
| **⌃⌥K**(全局) | 随时呼出聊天面板 |
| 右键 / 菜单栏 → 聊天… | 同上,回车发送 |
| 右键 → 看天气 | 报当前气温 / 天气 / 湿度 / 风速 |
| 菜单栏 | 图标旁常显当前余额 |
| 右键 → DeepSeek 余额 | 气泡报余额(有赠金会单独标) |
| 右键 → 打开用量页… | 跳 platform.deepseek.com/usage |
| 右键 → 打开网关面板… | 跳 127.0.0.1:4000/ui |
| 右键 → API 设置… | 改 Base URL / 模型 / API Key / 城市 |
| 菜单栏图标 | 同一个菜单;隐藏后从这里叫回来 |

> **用量**:DeepSeek 官方只开放了"余额"接口,没有用量 API,所以用量只能从「打开用量页…」去控制台看。这是官方限制,不是没做。

配置写在 `~/Library/Application Support/Dafeiyu/config.json`,API Key 单独存 Keychain(service `io.github.dafeiyu.mac`)。

聊天默认配置:

| 项 | 默认值 |
|---|---|
| Base URL | `http://127.0.0.1:4000/v1`(本机 LiteLLM 网关) |
| 模型 | `deepseek-chat` |
| Key | 空(网关不鉴权时留空;走官方时填 `sk-...`) |

## 自己编译

需要 macOS 13+ 与 Xcode Command Line Tools(Swift 5.9+),不需要完整 Xcode。

```bash
swift build -c release          # 或 swift run 直接跑
./scripts/build-app.sh          # 产出 dist/Dafeiyu.app + zip + dmg
```

只想看看她长什么样、不开窗:

```bash
./dist/Dafeiyu.app/Contents/MacOS/Dafeiyu --shot            # 离屏渲染一张 PNG
./dist/Dafeiyu.app/Contents/MacOS/Dafeiyu --chat-test "你好"   # 命令行验证网关连通
./dist/Dafeiyu.app/Contents/MacOS/Dafeiyu --weather-test 汕头   # 命令行验证天气
./dist/Dafeiyu.app/Contents/MacOS/Dafeiyu --balance-test       # 命令行查 DeepSeek 余额
```

## 与 Windows 原版的差异

| 功能 | 状态 |
|---|---|
| 三视图走动 / 拖拽 / 喂食 / 台词 / 心声 | ✅ 已移植 |
| 鼠标穿透 / 置顶 / 自启 / 托盘菜单 | ✅ 已移植(系统实现换成 macOS 原生) |
| DeepSeek API 聊天 | ✅ v0.2(默认走本机 LiteLLM 网关,也可填 DeepSeek 官方) |
| CPU / 内存监控吐槽 | ✅ v0.2 |
| 天气查询 | ✅ v0.3(wttr.in,中文描述自建映射) |

## 一起把她养大 🐋

这个项目是我一时兴起搓出来的,台词和动作都还很单薄 —— **非常欢迎你来补充**。不用会 Swift 也能贡献:加几句台词就是 PR。

### 加台词(最容易上手)

文件:`Sources/Dafeiyu/Support.swift`,找到 `enum Lines`:

| 数组 | 用在哪 |
|---|---|
| `idle` | 待机闲聊 |
| `react` | 被戳时的回嘴 |
| `inner` | 思维链心声(自动加括号 + 灰色斜体) |
| `drag` | 被拎起来时 |
| `morning` / `noon` / `evening` / `night` / `lateNight` | 对应时段的语境台词 |
| `foodLines` | 每种食物的专属反应 |

几条小规矩:一句一行、别和已有的重复、别太长(气泡一行大约 20 字)、别有攻击性。

### 加动作

文件:`Sources/Dafeiyu/PetView.swift`

1. `enum Action` 里加一个 case
2. `performRandomAction` 里加分支 —— 注意那里用的是累计区间(`case ..<0.42`),调权重时后面的百分比要一起挪
3. `draw` 里给它加视觉(旋转 / 缩放 / 位移都行,现在只有 Core Graphics 变换,不需要新图)
4. `finishAction` 里收尾(比如把朝向转回正面)

### 加功能

- **菜单项**:`populate(_:)` 加 `NSMenuItem` + 对应的 `@objc` 方法
- **网络请求**:照着 `Weather.swift`(无 Key)或 `Balance.swift`(带 Key)写
- **配置项**:`Config` 加字段 → `init(from:)` 里 `decodeIfPresent` 兜底 → 设置面板加输入框
- **自检**:加一个 `--xxx-test` 命令行分支,方便无头验证(现有 `--shot` / `--chat-test` / `--weather-test` / `--balance-test`)

### 提 PR

Fork → 改 → `swift build -c release` 确认能编 → 发 PR。附一张截图或者一段说明更好。想法多但不会写代码,也可以直接开 issue 丢梗。

## 素材与致谢

- 精灵图(正面 / 侧面 / 背面)、图标、台词梗:来自 [1190fasheqi/dafeiyu-pet](https://github.com/1190fasheqi/dafeiyu-pet),MIT License
- 行为设计参考同仓库 `桌宠.py`
- 「鲸鱼娘 / 大肥鱼」形象是 DeepSeek 社区二创,**与 DeepSeek 官方无关**,本项目也非官方产品,仅限个人娱乐,不作商业用途

## License

代码 MIT。素材遵循上游 MIT,版权归原作者。

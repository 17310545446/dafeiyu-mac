# 大肥鱼 · macOS 桌宠 🐋

DeepSeek 社区二创形象「鲸鱼娘 · 大肥鱼」的 **macOS 原生桌面宠物**。

> 原版是 [1190fasheqi/dafeiyu-pet](https://github.com/1190fasheqi/dafeiyu-pet)(Python + PySide6,Windows)。本仓库把同一套素材和玩法移植成 Swift / AppKit 原生实现:**不用 Electron、不用 Python 运行时,2.7 MB 的 .app,实测常驻内存约 50 MB(AppKit 生效后的 RSS),Apple Silicon 与 Intel 通用**。

[![Release](https://img.shields.io/github/v/release/17310545446/dafeiyu-mac)](https://github.com/17310545446/dafeiyu-mac/releases)
[![Platform](https://img.shields.io/badge/macOS-13%2B-blue)](https://github.com/17310545446/dafeiyu-mac)

![渲染自检图](docs/screenshot-render.png)

<sub>上图是 `--shot` 离屏渲染的自检图(透明底,气泡为半透明白,在深色壁纸上更明显)。</sub>

## 特性

- **三视图走动**:正面 / 侧面 / 背面各一套,左右走自动镜像,转向有交叉淡化
- **自由散步**:随机挑点、加速减速、走累了原地休息 8–18 秒
- **跟随鼠标 / 原地待着**:右键菜单里切换
- **拖拽**:按住拖动会侧身朝向你拖的方向,松手还会抗议两句
- **单击**:蹦跳 + 回嘴; **双击**:喂食(🐟 🍰 🍭 🍡 💎,每种食物有专属台词)
- **思维链心声**:发呆时有小概率冒出灰色斜体气泡,内容取材 DS 社区梗
- **呼吸 / 摇摆 / 伸展 / 蹦跳**:纯 Core Graphics 变换,没有逐帧图
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
| 左键单击 | 蹦跳 + 回嘴一句 |
| 左键双击 | 喂食菜单 |
| 左键拖动 | 拎起来到处放 |
| 右键 | 完整菜单(模式 / 大小 / 穿透 / 置顶 / 自启 / 退出) |
| 菜单栏图标 | 同一个菜单;隐藏后从这里叫回来 |

配置写在 `~/Library/Application Support/Dafeiyu/config.json`。

## 自己编译

需要 macOS 13+ 与 Xcode Command Line Tools(Swift 5.9+),不需要完整 Xcode。

```bash
swift build -c release          # 或 swift run 直接跑
./scripts/build-app.sh          # 产出 dist/Dafeiyu.app + zip + dmg
```

只想看看她长什么样、不开窗:

```bash
./dist/Dafeiyu.app/Contents/MacOS/Dafeiyu --shot   # 输出 /tmp/pet-render.png
```

## 与 Windows 原版的差异

| 功能 | 状态 |
|---|---|
| 三视图走动 / 拖拽 / 喂食 / 台词 / 心声 | ✅ 已移植 |
| 鼠标穿透 / 置顶 / 自启 / 托盘菜单 | ✅ 已移植(系统实现换成 macOS 原生) |
| DeepSeek API 聊天 | ⏳ 路线图 |
| 天气查询 / CPU·内存监控 | ⏳ 路线图 |

## 素材与致谢

- 精灵图(正面 / 侧面 / 背面)、图标、台词梗:来自 [1190fasheqi/dafeiyu-pet](https://github.com/1190fasheqi/dafeiyu-pet),MIT License
- 行为设计参考同仓库 `桌宠.py`
- 「鲸鱼娘 / 大肥鱼」形象是 DeepSeek 社区二创,**与 DeepSeek 官方无关**,本项目也非官方产品,仅限个人娱乐,不作商业用途

## License

代码 MIT。素材遵循上游 MIT,版权归原作者。

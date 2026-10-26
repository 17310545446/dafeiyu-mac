# Changelog

## v0.2.0 — 2026-10-26

### 新增
- **聊天面板**(⌘K / 右键「聊天…」):接 OpenAI 兼容端点,默认指向本机 LiteLLM 网关 `http://127.0.0.1:4000/v1`,模型默认 `deepseek-chat`
- **API 设置面板**:Base URL / 模型 / Key 可视化修改
- **Keychain 存储**:API Key 走 Security.framework,不写进 config.json
- **系统监控**:每 10 秒采样 CPU / 内存,超阈值触发台词(CPU ≥90%、内存 ≥93%)
- 命令行自检:`--chat-test "文本"` 验证网关连通

### 修复
- 聊天时暂停走动,避免"边聊边跑"

## v0.1.0 — 2026-10-26

- 首个 macOS 原生版本:三视图走动、拖拽、单击回嘴、双击喂食、思维链心声
- 鼠标穿透 / 置顶 / 开机自启 / 菜单栏图标 / 多屏感知
- Universal 二进制(arm64 + x86_64)

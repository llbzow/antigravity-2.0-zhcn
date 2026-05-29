# Antigravity 汉化项目 (AGY-ZH)

![Antigravity](https://img.shields.io/badge/Antigravity-2.0.x-blue.svg)
![Status](https://img.shields.io/badge/Status-Stable-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

为强大的 Antigravity 编辑器提供深度、安全的中文本地化支持。本项目不仅汉化了核心的基础服务，还通过安全定向拦截技术成功汉化了 AI UI 面板（包括设置、导航、应用等页面）。

## 🌟 核心特性

- **稳定可靠的基础汉化**：完美覆盖核心扩展及基础提示，让你在熟悉的母语环境里流畅编码。
- **安全的 AI UI 面板注射**：独创 `agy-ui://` 协议拦截替换，仅对 `/main.js` 做定向处理，彻底告别旧版本中可能遭遇的“启动卡死”问题。
- **高覆盖率的静态文案映射**：内置近 300 条深度人工校验规则，覆盖系统设置、智能体设置、本地权限、账号选项、快捷键说明等。
- **不损原貌的动态拼接**：主动放弃直接替换不可靠的动态变量（如项目名、实时生成文本），最大程度避免因字符串越界带来的应用功能损坏。
- **向后兼容预警机制**：配置了版本指纹（Hash）检测机制。当宿主引擎发生大版本更新时，可降级回退或快速定位补丁点。

## 📦 小白使用方式

### Windows

1. 在 GitHub 项目页点击 `Code` → `Download ZIP`，解压到任意文件夹
2. 先彻底关闭 Antigravity
3. 双击对应 `.bat` 文件：
   - **完整中文界面**：`一键汉化-AI界面版.bat`
   - **基础稳定汉化**：`一键汉化-基础版.bat`
   - **恢复英文**：`一键恢复英文.bat`
4. 等脚本跑完，重新打开 Antigravity

### Linux (Arch/yay 等)

> **已测试**：Antigravity 2.0.6, Arch Linux, yay 安装（安装路径 `/opt/Antigravity/`）

**一键安装**：

```bash
git clone https://github.com/llbzow/antigravity-2.0-zhcn.git
cd antigravity-2.0-zhcn

# 1. 先打开 Antigravity（需要从运行实例抓取 UI 翻译包）
antigravity &

# 2. 等待启动完成（约 5 秒），然后运行汉化
sudo bash scripts/apply_linux.sh --ai-ui

# 3. 重新打开 Antigravity 即可看到中文界面
```

**手动步骤**（如果一键脚本失败）：

```bash
# 1. 从运行中的 Antigravity 抓取 UI bundle
PORT=$(grep -oP 'Local:\s+https://127\.0\.0\.1:\K\d+' ~/.config/Antigravity/logs/main.log | tail -1)
curl -sk "https://127.0.0.1:$PORT/main.js" -o /tmp/agy_ui_main.js

# 2. 生成中文翻译包
python3 scripts/translate_ui_linux.py --input /tmp/agy_ui_main.js --output ~/.config/Antigravity/zh_cn_ui_main.js

# 3. 关闭 Antigravity，用任务管理器或 kill -9 强制结束

# 4. 打补丁到 app.asar
sudo bash -c '
ASAR=/opt/Antigravity/resources/app.asar
E=/tmp/agy_patch
npx asar extract "$ASAR" "$E"
rm -rf "$E/node_modules/chrome-devtools-mcp"
cp patches/customScheme.ai-ui.v2.js "$E/dist/customScheme.js"
npx asar pack "$E" "$ASAR"
rm -rf "$E"
'

# 5. 重新打开 Antigravity
```

**注意事项**：

- `yay -Syu` 或 `pacman -Syu` 更新 Antigravity 后会覆盖补丁，需重新运行脚本
- 若汉化后界面空白/闪退，可恢复原始 `app.asar`：
  ```bash
  sudo cp ~/.cache/yay/antigravity/src/Antigravity-x64/resources/app.asar /opt/Antigravity/resources/app.asar
  rm ~/.config/Antigravity/zh_cn_ui_main.js
  ```
- 翻译覆盖率：**604 条**，覆盖设置、智能体、权限、快捷键、导航、对话等核心 UI
5. **注意**：`yay`/`pacman` 更新 Antigravity 后会覆盖补丁，需重新运行脚本

## 📦 命令行方式

### 默认安装 (Stable Core)
仅应用基础核心语言包，不尝试干涉 AI 界面渲染，提供最稳固的使用体验。
```powershell
.\scripts\apply.ps1
```

### AI 面板深度汉化模式 (Enable AI UI)
开启基于 `agy-ui://` 的定向重定向机制，享受设置中心与主交互界面的中文体验。
```powershell
.\scripts\apply.ps1 -EnableAiUi
```

> **注意**：
> 当前主版本已升级至 `2.0.6`。`2.0.6` 已不再沿用旧的 `resources/app/out` 结构，核心 VS Code 部分不再适合老式覆盖方式。当前脚本会优先解析真实运行中的 UI bundle，并在命中兼容哈希后启用 AI UI 汉化。详见 [implementation_plan.md](implementation_plan.md) 与 [开发交接文档](docs/HANDOFF.md)。

## 🛠️ 项目结构

- `scripts/`
  - `apply.ps1` - Windows 汉化应用入口与打包脚本。
  - `apply_linux.sh` - Linux 汉化应用入口（Arch/yay）。
  - `extract.ps1` - 提取工具，用于生成版本更新时的文本差异与哈希报告。
  - `translate_ui.py` - AI UI 面板核心词库与驱动引擎（Windows），通过字面量精确替换。
  - `translate_ui_linux.py` - AI UI 面板核心词库与驱动引擎（Linux），通过字面量精确替换。
  - `bg_install.py` / `run_bg_install.bat` - 异步静默安装触发器。
- `patches/`
  - `customScheme.ai-ui.js` / `customScheme.core.js` - `main.js` 定向重写与网络拦截的核心补丁模板（Windows）。
  - `customScheme.ai-ui.v2.js` - Linux 安全版 AI UI 补丁（同步 I/O + 错误处理，避免启动崩溃）。
  - `ai-ui-compat.json` - 版本兼容性指纹记录档案库。
- `docs/`
  - `INSTALL.md` - 详细安装指南。
  - `CHANGELOG.md` - 变更记录。
  - `HANDOFF.md` - 给开发者的接力及状态说明文档。

## 💡 开发与参与

本项目基于 Python 和 PowerShell 实现无损替换与应用。如果你有兴趣为项目添砖加瓦：

1. **增补词汇**：请直接编辑 `scripts/translate_ui.py` 下的词库字典。确保修改后能在本机通过 `node --check` 以及 `python -m py_compile` 的语法验证。
2. **适配新版**：我们在 `patches/ai-ui-compat.json` 中登记了已验证的文件指纹（Bundle Hash）。如果你在最新的 Antigravity 版本下提取了新的指纹，欢迎提交更新。
3. **翻译注意事项**：避免翻译单个通用英文单词（如 `Tab`、`App`、`Filter`、`Name` 等），它们可能与 JS 内部标识符冲突导致界面白屏。优先翻译完整短语和带上下文的标签。

## 📄 授权与许可

本项目采用 MIT 协议开源。
本项目仅作为本地化辅助工具，提供给爱好者研究使用。Antigravity 商标及软件相关权利归属其原属公司。

#!/usr/bin/env bash
# Antigravity 2.0 一键汉化 - Linux 版
# 自动检测环境、启停服务、抓取翻译、打补丁、重启

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
TRANS_JSON="$PROJECT_ROOT/translations/ui-translations.json"
CORE_PATCH="$PROJECT_ROOT/patches/customScheme.core.js"
AIUI_PATCH="$PROJECT_ROOT/patches/customScheme.ai-ui.v2.js"

AGY_INSTALL=""
AGY_ASAR=""
AGY_LOG=""
AGY_CONFIG_DIR="$HOME/.config/Antigravity"

MODE="${1:-ai-ui}"  # ai-ui | core | restore
FORCE=false
[[ "$MODE" == "--force" ]] && { FORCE=true; MODE="${2:-ai-ui}"; }

# ============================================
# 环境检测
# ============================================

detect_environment() {
    echo -e "${CYAN}>>> 环境检测${NC}"

    # 检测 Antigravity 安装
    if [[ -f /opt/Antigravity/antigravity ]]; then
        AGY_INSTALL="/opt/Antigravity"
        AGY_ASAR="/opt/Antigravity/resources/app.asar"
    elif command -v antigravity &>/dev/null; then
        AGY_INSTALL="$(dirname "$(dirname "$(readlink -f "$(which antigravity)")")")"
        AGY_ASAR="$AGY_INSTALL/resources/app.asar"
    else
        echo -e "${RED}错误: 未找到 Antigravity 安装。${NC}"
        echo "请先安装: yay -S antigravity"
        exit 1
    fi
    echo -e "  ${GREEN}Antigravity: $AGY_INSTALL${NC}"

    # 检测依赖
    for cmd in python3 node npx curl; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}错误: 缺少 $cmd，请先安装。${NC}"
            exit 1
        fi
    done
    echo -e "  ${GREEN}依赖完整${NC}"

    # 检测 sudo
    if [[ "$EUID" -ne 0 ]] && ! command -v sudo &>/dev/null; then
        echo -e "${RED}错误: 需要 sudo 权限修改 /opt/Antigravity。${NC}"
        exit 1
    fi
}

# ============================================
# 启动/停止 Antigravity
# ============================================

wait_for_port() {
    local max_wait=30 waited=0
    while [[ $waited -lt $max_wait ]]; do
        local port
        port=$(grep -oP 'Local:\s+https://127\.0\.0\.1:\K\d+' "$AGY_CONFIG_DIR/logs/main.log" 2>/dev/null | tail -1)
        if [[ -n "$port" ]]; then
            echo "$port"
            return 0
        fi
        sleep 1
        ((waited++))
    done
    return 1
}

start_antigravity() {
    if pgrep -f "[aA]ntigravity" &>/dev/null; then
        # 检查是否已有端口
        local port
        port=$(grep -oP 'Local:\s+https://127\.0\.0\.1:\K\d+' "$AGY_CONFIG_DIR/logs/main.log" 2>/dev/null | tail -1)
        if [[ -n "$port" ]]; then
            echo -e "  ${GREEN}Antigravity 已在运行 (端口 $port)${NC}"
            echo "$port"
            return
        fi
        echo -e "  ${YELLOW}Antigravity 进程存在但未就绪，等待...${NC}"
        port=$(wait_for_port)
        if [[ -n "$port" ]]; then
            echo "$port"
            return
        fi
    fi

    echo -e "  ${GREEN}启动 Antigravity...${NC}"
    nohup "$AGY_INSTALL/antigravity" &>/dev/null &
    local port
    port=$(wait_for_port)
    if [[ -z "$port" ]]; then
        echo -e "${RED}错误: 启动超时，请手动启动 Antigravity 后重试。${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}已启动 (端口 $port)${NC}"
    echo "$port"
}

stop_antigravity() {
    if pgrep -f "[aA]ntigravity" &>/dev/null; then
        echo -e "  ${YELLOW}停止 Antigravity...${NC}"
        kill -9 $(pgrep -f "[aA]ntigravity") 2>/dev/null || true
        sleep 1
        echo -e "  ${GREEN}已停止${NC}"
    fi
}

# ============================================
# 翻译
# ============================================

fetch_and_translate() {
    local port="$1"
    local bundle_file="/tmp/agy_ui_main_$$.js"
    local output_file="$AGY_CONFIG_DIR/zh_cn_ui_main.js"
    local translator="$PROJECT_ROOT/scripts/translate_ui_linux.py"

    echo -e "${CYAN}>>> 抓取 UI 翻译包${NC}"
    echo -e "  端口: $port"
    curl -sk "https://127.0.0.1:$port/main.js" -o "$bundle_file" 2>/dev/null
    if [[ ! -s "$bundle_file" ]]; then
        echo -e "${RED}错误: 无法抓取 UI bundle。${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}抓取成功 ($(wc -c < "$bundle_file") bytes)${NC}"

    # 检查版本兼容性
    local hash
    hash=$(sha256sum "$bundle_file" | awk '{print toupper($1)}')
    echo -e "  Hash: ${hash:0:16}..."
    local compat
    compat=$(python3 -c "
import json
m = json.load(open('$PROJECT_ROOT/patches/ai-ui-compat.json'))
for b in m.get('supportedBundles', []):
    if '$hash' in b.get('sourceSha256', '').upper():
        print(b.get('antigravityVersion', 'unknown'))
        break
" 2>/dev/null)
    if [[ -z "$compat" ]]; then
        echo -e "  ${YELLOW}警告: UI bundle hash 不在已知兼容列表中，可能为未知版本。${NC}"
        if ! $FORCE; then
            read -rp "  继续? (y/N) " answer
            [[ "$answer" != "y" && "$answer" != "Y" ]] && { rm -f "$bundle_file"; exit 0; }
        fi
    else
        echo -e "  ${GREEN}兼容版本: $compat${NC}"
    fi

    # 生成翻译
    echo -e "${CYAN}>>> 生成中文翻译${NC}"
    python3 "$translator" --input "$bundle_file" --output "$output_file"
    rm -f "$bundle_file"
    echo -e "  ${GREEN}翻译包已保存: $output_file${NC}"
}

# ============================================
# 打补丁
# ============================================

patch_asar() {
    local mode="$1"
    local patch_file
    case "$mode" in
        ai-ui) patch_file="$AIUI_PATCH" ;;
        core)  patch_file="$CORE_PATCH" ;;
        *) echo -e "${RED}未知模式: $mode${NC}"; exit 1 ;;
    esac

    echo -e "${CYAN}>>> 打补丁到 app.asar${NC}"

    local extracted="/tmp/agy_patch_$$"
    local backup="$AGY_ASAR.bak"

    # 备份（只做一次）
    if [[ ! -f "$backup" ]]; then
        sudo cp "$AGY_ASAR" "$backup"
        echo -e "  ${GREEN}备份: $backup${NC}"
    fi

    # 用 root 执行核心操作
    sudo bash -c "
set -e
npx asar extract '$AGY_ASAR' '$extracted'
rm -rf '$extracted/node_modules/chrome-devtools-mcp' 2>/dev/null || true
cp '$patch_file' '$extracted/dist/customScheme.js'
npx asar pack '$extracted' '$AGY_ASAR'
rm -rf '$extracted'
" 2>&1

    echo -e "  ${GREEN}补丁已应用 ($mode)${NC}"
}

# ============================================
# 恢复
# ============================================

do_restore() {
    echo -e "${CYAN}>>> 恢复原始英文${NC}"
    stop_antigravity

    if [[ -f "$AGY_ASAR.bak" ]]; then
        sudo cp "$AGY_ASAR.bak" "$AGY_ASAR"
        echo -e "  ${GREEN}已恢复原始 app.asar${NC}"
    else
        echo -e "${YELLOW}未找到备份，尝试从 AUR 缓存恢复...${NC}"
        local cached
        cached=$(find /var/cache/pacman/pkg ~/.cache/yay -name "*.tar.zst" -path "*antigravity*" 2>/dev/null | head -1)
        if [[ -n "$cached" ]]; then
            sudo bash -c "cd /tmp && tar xf '$cached' opt/Antigravity/resources/app.asar && cp opt/Antigravity/resources/app.asar '$AGY_ASAR' && rm -rf opt"
            echo -e "  ${GREEN}已从 AUR 缓存恢复${NC}"
        else
            echo -e "${YELLOW}未找到缓存，请用 yay -S antigravity 重新安装。${NC}"
        fi
    fi

    rm -f "$AGY_CONFIG_DIR/zh_cn_ui_main.js"
    echo -e "${GREEN}已清理翻译缓存${NC}"
    echo -e "\n${GREEN}恢复完成！重新打开 Antigravity 即可。${NC}"
}

# ============================================
# 主流程
# ============================================

echo -e "${CYAN}====================================${NC}"
echo -e "${CYAN} Antigravity 2.0 一键汉化 (Linux)${NC}"
echo -e "${CYAN}====================================${NC}"
echo ""

detect_environment

case "$MODE" in
    restore)
        do_restore
        exit 0
        ;;
    core)
        echo -e "${YELLOW}模式: 基础汉化 (不拦截 AI 面板)${NC}"
        ;;
    ai-ui)
        echo -e "${YELLOW}模式: 完整 AI 界面汉化${NC}"
        ;;
    *)
        echo -e "${RED}用法: $0 [ai-ui|core|restore]${NC}"
        exit 1
        ;;
esac

# 翻译步骤
if [[ "$MODE" == "ai-ui" ]]; then
    PORT=$(start_antigravity)
    fetch_and_translate "$PORT"
    stop_antigravity
else
    stop_antigravity
fi

# 打补丁
patch_asar "$MODE"

# 完成
echo ""
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN} 汉化完成！${NC}"
echo -e "${GREEN}====================================${NC}"
echo ""
echo -e "现在打开 Antigravity，AI 面板应显示中文。"
echo -e "yay 更新后会覆盖补丁，重新运行此脚本即可。"
echo -e "恢复英文: $0 restore"
echo ""
nohup "$AGY_INSTALL/antigravity" &>/dev/null &
echo -e "${GREEN}Antigravity 已自动启动。${NC}"

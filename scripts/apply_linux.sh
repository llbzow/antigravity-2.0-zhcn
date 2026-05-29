#!/usr/bin/env bash
set -euo pipefail

# Antigravity 2.0 Chinese Localization - Linux Edition
# Adapted from apply.ps1 by kakarotto-baroko

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGY_INSTALL="/opt/Antigravity"
AGY_ASAR="$AGY_INSTALL/resources/app.asar"
AGY_ASAR_BAK="$AGY_ASAR.bak"
AGY_EXTRACTED="$AGY_INSTALL/resources/extracted_asar"
AGY_CONFIG="$HOME/.config/Antigravity"
AGY_LOG="$AGY_CONFIG/logs/main.log"
AGY_BRAIN="$HOME/.gemini/antigravity/brain"

AI_UI_MODE=false
RESTORE_MODE=false

usage() {
    echo "Usage: $0 [--ai-ui] [--restore]"
    echo "  --ai-ui     Also enable AI panel UI Chinese translation"
    echo "  --restore   Restore original English files"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ai-ui) AI_UI_MODE=true; shift ;;
        --restore) RESTORE_MODE=true; shift ;;
        --help|-h) usage ;;
        *) usage ;;
    esac
done

require_root_or_sudo() {
    if [[ "$EUID" -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            exec sudo "$0" "$@"
        else
            echo -e "${RED}Error: This script requires root privileges.${NC}"
            exit 1
        fi
    fi
}

get_port_from_log() {
    grep -oP 'Local:\s+https://127\.0\.0\.1:\K\d+' "$AGY_LOG" 2>/dev/null | tail -1
}

must_stop_antigravity() {
    if pgrep -f Antigravity &>/dev/null; then
        echo -e "${YELLOW}Antigravity is running. Stopping...${NC}"
        pkill -f Antigravity || true
        sleep 2
        if pgrep -f Antigravity &>/dev/null; then
            echo -e "${RED}Failed to stop Antigravity. Please close it manually.${NC}"
            exit 1
        fi
        echo -e "${GREEN}Antigravity stopped.${NC}"
    fi
}

# ---- Restore ----
do_restore() {
    echo -e "${YELLOW}[Restore] Restoring original English files...${NC}"
    must_stop_antigravity

    if [[ -f "$AGY_ASAR_BAK" ]]; then
        cp "$AGY_ASAR_BAK" "$AGY_ASAR"
        echo -e "${GREEN}  Restored app.asar${NC}"
    fi
    if [[ -d "$AGY_EXTRACTED" ]]; then
        rm -rf "$AGY_EXTRACTED"
        echo -e "${GREEN}  Cleaned up extracted_asar${NC}"
    fi
    rm -f "$AGY_CONFIG/zh_cn_ui_main.js"
    echo -e "${GREEN}Restore complete. Restart Antigravity.${NC}"
    exit 0
}

# ---- Apply customScheme patch to app.asar ----
apply_scheme_patch() {
    local mode="$1"  # "core" or "ai-ui"
    local patch_file="$PROJECT_ROOT/patches/customScheme.$mode.js"
    local target="$AGY_EXTRACTED/dist/customScheme.js"

    if [[ ! -f "$patch_file" ]]; then
        echo -e "${RED}Missing patch: $patch_file${NC}"
        exit 1
    fi

    # Backup original asar
    if [[ ! -f "$AGY_ASAR_BAK" ]]; then
        cp "$AGY_ASAR" "$AGY_ASAR_BAK"
        echo -e "${GREEN}  Created backup: $AGY_ASAR_BAK${NC}"
    fi

    # Extract asar
    echo "  Extracting app.asar..."
    npx asar extract "$AGY_ASAR" "$AGY_EXTRACTED"

    # Apply patch
    cp "$patch_file" "$target"
    echo -e "${GREEN}  Applied $mode customScheme patch${NC}"

    # Repack
    echo "  Repacking app.asar..."
    npx asar pack "$AGY_EXTRACTED" "$AGY_ASAR"
    rm -rf "$AGY_EXTRACTED"
    echo -e "${GREEN}  app.asar repacked successfully${NC}"
}

# ---- Generate AI UI translation bundle ----
generate_ai_ui_bundle() {
    local port
    port=$(get_port_from_log)

    # If not running, try brain scratch dir
    local ui_source=""
    if [[ -n "$port" ]]; then
        # Fetch from running instance
        local bundle_file="/tmp/agy_ui_main_$$.js"
        echo "  Fetching UI bundle from port $port..."
        curl -sk "https://127.0.0.1:$port/main.js" -o "$bundle_file" 2>/dev/null
        if [[ -f "$bundle_file" && -s "$bundle_file" ]]; then
            ui_source="$bundle_file"
            echo -e "${GREEN}  Fetched $(wc -c < "$bundle_file") bytes${NC}"

            local hash
            hash=$(sha256sum "$bundle_file" | awk '{print $1}')
            local compat_hash
            compat_hash=$(python3 -c "
import json
m = json.load(open('$PROJECT_ROOT/patches/ai-ui-compat.json'))
for b in m['supportedBundles']:
    print(b['sourceSha256'].upper())
" 2>/dev/null)
            if ! echo "$compat_hash" | grep -qi "$hash"; then
                echo -e "${YELLOW}Warning: UI bundle hash mismatch. AI UI translation may not work correctly.${NC}"
            else
                echo -e "${GREEN}  Hash match confirmed!${NC}"
            fi
        fi
    fi

    # Fallback: find in brain dir
    if [[ -z "$ui_source" ]]; then
        ui_source=$(find "$AGY_BRAIN" -name "ui_main.js" -path "*/scratch/*" 2>/dev/null | head -1)
        if [[ -z "$ui_source" ]]; then
            echo -e "${RED}Cannot find UI bundle. Start Antigravity first to generate it.${NC}"
            return 1
        fi
        echo "  Using cached UI bundle: $ui_source"
    fi

    # Run translation
    echo "  Translating UI bundle..."
    python3 "$PROJECT_ROOT/scripts/translate_ui_linux.py" --input "$ui_source" --output "$AGY_CONFIG/zh_cn_ui_main.js"
    echo -e "${GREEN}  AI UI translation bundle generated${NC}"

    # Cleanup temp
    [[ "$ui_source" == /tmp/agy_ui_main_* ]] && rm -f "$ui_source"
}

# ---- Main ----
if $RESTORE_MODE; then
    do_restore
fi

echo -e "${CYAN}=== Antigravity 2.0 Chinese Localization (Linux) ===${NC}"

require_root_or_sudo "$@"

if $AI_UI_MODE; then
    echo -e "${YELLOW}[Install] Applying Chinese with AI UI translation...${NC}"

    # 1. Generate AI UI translation bundle (requires Antigravity to be running)
    echo "Step 1: Generating AI UI translation bundle..."
    generate_ai_ui_bundle

    # 2. Stop Antigravity to modify asar
    echo "Step 2: Stopping Antigravity to patch app.asar..."
    must_stop_antigravity

    # 3. Apply ai-ui customScheme patch
    echo "Step 3: Patching app.asar..."
    apply_scheme_patch "ai-ui"

    echo -e "${CYAN}=== Done! Restart Antigravity. AI panel should show Chinese. ===${NC}"
else
    echo -e "${YELLOW}[Install] Applying core Chinese localization...${NC}"
    must_stop_antigravity
    apply_scheme_patch "core"
    echo -e "${CYAN}=== Done! Restart Antigravity. ===${NC}"
fi

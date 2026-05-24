#!/bin/bash
# 浮光 Reminders Sync Helper - 一键安装脚本
# 用法: curl -fsSL https://dl.fl.vkr.me/install.sh | bash
#   或: bash install.sh

set -e

HELPER_NAME="me.vkr.fl.sync"
INSTALL_DIR="$HOME/.floatlight"
BINARY_NAME="floatlight-sync"
CHROME_NMH_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
VERSION="latest"

# Download URLs (R2 primary, GitHub fallback)
R2_BASE="https://dl.fl.vkr.me"
GITHUB_BASE="https://github.com/fliujun/floatlight-sync/releases/latest/download"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   浮光 · 提醒事项同步 Helper 安装程序   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}✗ 此功能仅支持 macOS${NC}"
    exit 1
fi

# Detect architecture
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
    ARCH_SUFFIX="arm64"
    echo -e "系统架构: ${CYAN}Apple Silicon (arm64)${NC}"
elif [[ "$ARCH" == "x86_64" ]]; then
    ARCH_SUFFIX="x86_64"
    echo -e "系统架构: ${CYAN}Intel (x86_64)${NC}"
else
    echo -e "${RED}✗ 不支持的架构: $ARCH${NC}"
    exit 1
fi

ARCHIVE_NAME="floatlight-sync-macos-${ARCH_SUFFIX}.tar.gz"

# Function to download with fallback
download_file() {
    local output="$1"
    local r2_url="${R2_BASE}/${ARCHIVE_NAME}"
    local github_url="${GITHUB_BASE}/${ARCHIVE_NAME}"

    echo -e "⏳ 正在下载 Helper..."

    # Try R2 first (faster for China)
    if curl -fsSL --connect-timeout 8 --max-time 60 -o "$output" "$r2_url" 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} 下载完成 (CDN)"
        return 0
    fi

    echo -e "   ${YELLOW}⚠ CDN 下载失败，尝试备用线路...${NC}"

    # Fallback to GitHub
    if curl -fsSL --connect-timeout 15 --max-time 120 -o "$output" "$github_url" 2>/dev/null; then
        echo -e "   ${GREEN}✓${NC} 下载完成 (GitHub)"
        return 0
    fi

    echo -e "${RED}✗ 下载失败，请检查网络连接${NC}"
    echo ""
    echo "你也可以手动下载:"
    echo "  ${CYAN}${github_url}${NC}"
    return 1
}

# Step 1: Download
TMPDIR_PATH="$(mktemp -d)"
trap "rm -rf '$TMPDIR_PATH'" EXIT

download_file "${TMPDIR_PATH}/${ARCHIVE_NAME}"

# Step 2: Extract
echo "⏳ 正在解压..."
tar -xzf "${TMPDIR_PATH}/${ARCHIVE_NAME}" -C "$TMPDIR_PATH"

EXTRACTED_BINARY="${TMPDIR_PATH}/${BINARY_NAME}"
if [ ! -f "$EXTRACTED_BINARY" ]; then
    echo -e "${RED}✗ 解压失败，安装包可能已损坏${NC}"
    exit 1
fi

# Step 3: Install binary
echo "⏳ 正在安装..."
mkdir -p "$INSTALL_DIR"
cp "$EXTRACTED_BINARY" "$INSTALL_DIR/$BINARY_NAME"
chmod +x "$INSTALL_DIR/$BINARY_NAME"
echo -e "${GREEN}✓ Helper 已安装到 $INSTALL_DIR/$BINARY_NAME${NC}"

# Step 4: Register Native Messaging Host
# Auto-detect extension ID from existing NMH config, or use wildcard
echo "⏳ 正在注册 Native Messaging Host..."
mkdir -p "$CHROME_NMH_DIR"

# Find extension ID if browser has the extension installed
EXTENSION_ID=""
EXISTING_CONFIG="$CHROME_NMH_DIR/$HELPER_NAME.json"
if [ -f "$EXISTING_CONFIG" ]; then
    EXTENSION_ID=$(grep -o 'chrome-extension://[^/]*' "$EXISTING_CONFIG" | head -1 | sed 's|chrome-extension://||')
fi

if [ -z "$EXTENSION_ID" ]; then
    # Try to find from Chrome extensions directory
    CHROME_EXT_DIR="$HOME/Library/Application Support/Google/Chrome/Default/Extensions"
    if [ -d "$CHROME_EXT_DIR" ]; then
        # Look for our extension by checking manifest.json for "浮光"
        for ext_dir in "$CHROME_EXT_DIR"/*/; do
            if [ -d "$ext_dir" ]; then
                latest_ver=$(ls -1 "$ext_dir" 2>/dev/null | sort -V | tail -1)
                if [ -n "$latest_ver" ] && grep -q "浮光" "$ext_dir$latest_ver/manifest.json" 2>/dev/null; then
                    EXTENSION_ID=$(basename "$ext_dir")
                    break
                fi
            fi
        done
    fi
fi

if [ -z "$EXTENSION_ID" ]; then
    echo -e "${YELLOW}未自动检测到浮光扩展 ID${NC}"
    echo -e "请输入扩展 ID（chrome://extensions 中查看）或按回车跳过:"
    read -r EXTENSION_ID
fi

if [ -z "$EXTENSION_ID" ]; then
    # Use a placeholder - user will need to update later
    echo -e "${YELLOW}⚠ 未设置扩展 ID，使用通配符模式（首次连接时可能需要重新安装）${NC}"
    ALLOWED_ORIGINS='"chrome-extension://*/"'
else
    echo -e "扩展 ID: ${CYAN}${EXTENSION_ID}${NC}"
    ALLOWED_ORIGINS="\"chrome-extension://$EXTENSION_ID/\""
fi

cat > "$CHROME_NMH_DIR/$HELPER_NAME.json" << EOF
{
  "name": "$HELPER_NAME",
  "description": "浮光提醒事项同步 Helper",
  "path": "$INSTALL_DIR/$BINARY_NAME",
  "type": "stdio",
  "allowed_origins": [
    $ALLOWED_ORIGINS
  ]
}
EOF

echo -e "${GREEN}✓ Native Messaging Host 已注册${NC}"

# Step 5: Verify installation
echo ""
if "$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null; then
    true
fi

echo ""
echo "════════════════════════════════════════════"
echo -e "${GREEN}✓ 安装完成！${NC}"
echo ""
echo "  Helper:  $INSTALL_DIR/$BINARY_NAME"
echo "  NMH配置: $CHROME_NMH_DIR/$HELPER_NAME.json"
echo ""
echo -e "${CYAN}下一步:${NC}"
echo "  1. 重启 Chrome 浏览器"
echo "  2. 打开浮光新标签页"
echo "  3. 在提醒事项面板底部打开同步开关"
echo ""
echo "首次运行时 macOS 会请求「提醒事项」访问权限，请点击允许。"
echo "════════════════════════════════════════════"
echo ""

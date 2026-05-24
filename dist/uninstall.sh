#!/bin/bash
# 浮光 Reminders Sync Helper - 卸载脚本
# 用法: curl -fsSL https://dl.fl.vkr.me/uninstall.sh | bash
#   或: bash uninstall.sh

HELPER_NAME="me.vkr.fl.sync"
INSTALL_DIR="$HOME/.floatlight"
BINARY_NAME="floatlight-sync"
CHROME_NMH_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "浮光 · 提醒事项同步 Helper 卸载"
echo "────────────────────────────────"
echo ""

removed=0

if [ -f "$INSTALL_DIR/$BINARY_NAME" ]; then
    rm -f "$INSTALL_DIR/$BINARY_NAME"
    echo -e "${GREEN}✓${NC} 已删除 Helper: $INSTALL_DIR/$BINARY_NAME"
    removed=1
fi

if [ -f "$CHROME_NMH_DIR/$HELPER_NAME.json" ]; then
    rm -f "$CHROME_NMH_DIR/$HELPER_NAME.json"
    echo -e "${GREEN}✓${NC} 已删除 NMH 配置"
    removed=1
fi

# Clean up install dir if empty
if [ -d "$INSTALL_DIR" ] && [ -z "$(ls -A "$INSTALL_DIR")" ]; then
    rmdir "$INSTALL_DIR"
fi

if [ $removed -eq 0 ]; then
    echo -e "${YELLOW}未找到已安装的 Helper${NC}"
else
    echo ""
    echo -e "${GREEN}✓ 卸载完成${NC}"
    echo "  重启 Chrome 后同步功能将停止。"
fi
echo ""

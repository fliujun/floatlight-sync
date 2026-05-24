#!/bin/bash
# 浮光同步助手 - 构建脚本
# 用法:
#   ./build.sh              # 编译当前架构
#   ./build.sh --universal  # 编译双架构（arm64 + x86_64）

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/FloatlightHelper"  # 目录名暂不改，仅内容更新
DIST_DIR="$SCRIPT_DIR/dist"
BINARY_NAME="floatlight-sync"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查 Swift 是否可用
command -v swift >/dev/null 2>&1 || error "Swift 未安装，请先安装 Xcode Command Line Tools"

# 清理并创建 dist 目录
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 编译单个架构
build_arch() {
    local arch="$1"
    info "正在编译 $arch 架构..."

    cd "$PROJECT_DIR"
    swift build -c release --arch "$arch" 2>&1 | while read -r line; do
        echo "  $line"
    done

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        error "编译 $arch 架构失败"
    fi

    # 找到编译产物
    local build_path=".build/release/FloatlightSync"
    if [ ! -f "$build_path" ]; then
        # 尝试在架构特定目录中查找
        build_path=".build/apple/Products/Release/FloatlightSync"
        if [ ! -f "$build_path" ]; then
            error "找不到编译产物，请检查 Package.swift 中的 target 名称"
        fi
    fi

    # 创建临时打包目录
    local tmp_dir=$(mktemp -d)
    cp "$build_path" "$tmp_dir/$BINARY_NAME"
    chmod +x "$tmp_dir/$BINARY_NAME"

    # 打包为 tar.gz
    local output_file="$DIST_DIR/${BINARY_NAME}-macos-${arch}.tar.gz"
    tar -czf "$output_file" -C "$tmp_dir" "$BINARY_NAME"
    rm -rf "$tmp_dir"

    # 显示产物信息
    local size=$(du -h "$output_file" | cut -f1)
    info "✓ $arch 编译完成: $(basename "$output_file") ($size)"

    cd "$SCRIPT_DIR"
}

# 复制安装/卸载脚本到 dist
copy_scripts() {
    if [ -f "$SCRIPT_DIR/install.sh" ]; then
        cp "$SCRIPT_DIR/install.sh" "$DIST_DIR/install.sh"
        info "已复制 install.sh 到 dist/"
    fi
    if [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
        cp "$SCRIPT_DIR/uninstall.sh" "$DIST_DIR/uninstall.sh"
        info "已复制 uninstall.sh 到 dist/"
    fi
}

# 主逻辑
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  浮光同步助手 构建脚本"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$1" = "--universal" ]; then
    info "模式: Universal（双架构）"
    echo ""
    build_arch "arm64"
    echo ""
    build_arch "x86_64"
else
    # 检测当前架构
    CURRENT_ARCH=$(uname -m)
    info "模式: 当前架构 ($CURRENT_ARCH)"
    echo ""
    build_arch "$CURRENT_ARCH"
fi

echo ""
copy_scripts

# 显示最终产物
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "构建完成！产物目录: $DIST_DIR"
echo ""
ls -lh "$DIST_DIR"
echo ""

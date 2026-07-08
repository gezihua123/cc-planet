#!/bin/bash
set -e

# --- 配置 ---
REPO="gezihua123/cc-planet"
BINARY="cc-planet"
DOWNLOAD_BASE="https://github.com/${REPO}/releases/download"
DEFAULT_VERSION="v0.0.6"              # 发布时自动更新，API 不可用时回退

# --- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 帮助 ---
usage() {
    echo "用法: curl -fsSL https://raw.githubusercontent.com/$REPO/main/install_pkg.sh | bash"
    echo "  或: ./install_pkg.sh [选项] [版本号]"
    echo ""
    echo "从 GitHub Releases 下载并安装 $BINARY"
    echo ""
    echo "选项:"
    echo "  --global    安装到 /usr/local/bin/（全局，使用 sudo）"
    echo "  -h, --help  显示帮助"
    echo ""
    echo "参数:"
    echo "  版本号    可选，指定版本（如 v0.0.4），默认最新版"
    echo ""
    echo "示例:"
    echo "  ./install_pkg.sh                # 安装到 ~/.local/bin/"
    echo "  ./install_pkg.sh --global       # 安装到 /usr/local/bin/"
    echo "  ./install_pkg.sh v0.0.3         # 安装指定版本到 ~/.local/bin/"
    echo "  ./install_pkg.sh --global v0.0.3"
    exit 0
}

# --- 解析参数 ---
GLOBAL=false
TAG=""

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage ;;
        --global) GLOBAL=true ;;
        v*) TAG="$arg" ;;
    esac
done

if [[ "$GLOBAL" == "true" ]]; then
    INSTALL_PATH="/usr/local/bin/$BINARY"
    SUDO="sudo"
else
    INSTALL_PATH="${HOME}/.local/bin/$BINARY"
    SUDO=""
fi

# --- 系统检查 ---
echo -e "${CYAN}🔍 检查系统...${NC}"
OS=$(uname -s)
if [[ "$OS" != "Darwin" ]]; then
    echo -e "${YELLOW}⚠️  当前系统: $OS，$BINARY 仅支持 macOS${NC}"
fi

# --- 确定版本 ---
if [[ -z "$TAG" ]]; then
    echo -e "   获取最新版本..."
    TAG=$(curl -fsSL --connect-timeout 5 "https://api.github.com/repos/$REPO/releases/latest" \
        | grep '"tag_name"' \
        | sed 's/.*"tag_name": "\(.*\)",/\1/')
    if [[ -z "$TAG" ]]; then
        TAG="$DEFAULT_VERSION"
        echo -e "${YELLOW}   ⚠️  API 不可用，使用默认版本 ${CYAN}$TAG${NC}"
    else
        echo -e "   最新版本: ${CYAN}$TAG${NC}"
    fi
else
    echo -e "   指定版本: ${CYAN}$TAG${NC}"
fi

# --- 下载 ---
TARBALL="cc-planet-${TAG}.tar.gz"
DOWNLOAD_URL="${DOWNLOAD_BASE}/${TAG}/${TARBALL}"
echo -e "${CYAN}📥 下载 ...${NC}"

TMP_DIR=$(mktemp -d)
trap "rm -rf '$TMP_DIR'" EXIT

HTTP_CODE=$(curl -fSL# -o "$TMP_DIR/$TARBALL" "$DOWNLOAD_URL" -w "%{http_code}" 2>&1 | tail -1)

if [[ "$HTTP_CODE" != "200" ]]; then
    # 降级：尝试裸二进制
    echo -e "${YELLOW}⚠️  未找到 tarball，尝试裸二进制...${NC}"
    BINARY_URL="${DOWNLOAD_BASE}/${TAG}/${BINARY}"
    HTTP_CODE=$(curl -fSL# -o "$TMP_DIR/$BINARY" "$BINARY_URL" -w "%{http_code}" 2>&1 | tail -1)
    if [[ "$HTTP_CODE" != "200" ]]; then
        echo -e "${RED}❌ 下载失败 (HTTP $HTTP_CODE)${NC}"
        exit 1
    fi
    chmod +x "$TMP_DIR/$BINARY"
    SRC="$TMP_DIR/$BINARY"
else
    echo -e "${CYAN}📦 解压 ...${NC}"
    tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"
    SRC="$TMP_DIR/cc-planet-${TAG}/$BINARY"
fi

# --- 安装 ---
echo -e "${CYAN}📦 安装到 $INSTALL_PATH ...${NC}"

INSTALL_DIR=$(dirname "$INSTALL_PATH")
if [[ ! -d "$INSTALL_DIR" ]]; then
    $SUDO mkdir -p "$INSTALL_DIR"
fi

$SUDO cp "$SRC" "$INSTALL_PATH"
$SUDO chmod +x "$INSTALL_PATH"
echo -e "${GREEN}   ✓${NC} 安装完成"

# --- 验证 ---
echo -e "${CYAN}✅ 验证...${NC}"
INSTALLED_PATH=$(command -v "$BINARY" || echo "")
if [[ "$INSTALLED_PATH" == "$INSTALL_PATH" ]]; then
    echo -e "${GREEN}   $BINARY 已就绪: $INSTALLED_PATH${NC}"
else
    echo -e "${GREEN}   $BINARY 已安装到 $INSTALL_PATH${NC}"
    echo -e "${YELLOW}   重启终端或执行: hash -r${NC}"
fi

echo ""
echo -e "${GREEN}✅ 安装完成!${NC}"
echo ""
echo -e "   运行:"
echo -e "     ${CYAN}$BINARY \"Hello World\"${NC}"
echo -e "     ${CYAN}$BINARY --success \"Build passed\"${NC}"
echo -e "     ${CYAN}$BINARY --failure \"Test failed\"${NC}"
echo -e "     ${CYAN}$BINARY --blocked \"Waiting review\"${NC}"

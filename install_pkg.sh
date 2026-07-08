#!/bin/bash
set -e

# --- 配置 ---
REPO="gezihua123/cc-planet"
BINARY="cc-planet"
INSTALL_BASE="${HOME}/bin/cc-plane"   # cc-notify.py 约定的路径
DOWNLOAD_BASE="https://github.com/${REPO}/releases/download"
DEFAULT_VERSION="v0.0.4"              # 发布时自动更新，API 不可用时回退

# --- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 帮助 ---
usage() {
    echo "用法: ./install_pkg.sh [版本号]"
    echo ""
    echo "从 GitHub Releases 下载并安装 cc-planet 及配套资源"
    echo ""
    echo "参数:"
    echo "  版本号    可选，默认安装最新版"
    echo ""
    echo "示例:"
    echo "  ./install_pkg.sh           # 安装最新版"
    echo "  ./install_pkg.sh v0.0.2    # 安装指定版本"
    exit 0
}

[[ "$1" == "-h" || "$1" == "--help" ]] && usage

# --- 系统检查 ---
echo -e "${CYAN}🔍 检查系统...${NC}"
OS=$(uname -s)
if [[ "$OS" != "Darwin" ]]; then
    echo -e "${YELLOW}⚠️  当前系统: $OS，$BINARY 仅支持 macOS${NC}"
fi

# --- 确定版本 ---
if [[ -n "$1" ]]; then
    TAG="$1"
    echo -e "   指定版本: ${CYAN}$TAG${NC}"
else
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
fi

# --- 下载 ---
TARBALL="cc-planet-${TAG}.tar.gz"
DOWNLOAD_URL="${DOWNLOAD_BASE}/${TAG}/${TARBALL}"
echo -e "${CYAN}📥 下载 ${TARBALL} ...${NC}"
echo -e "   地址: ${CYAN}$DOWNLOAD_URL${NC}"

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
    EXTRACTED="$TMP_DIR"
else
    echo -e "${CYAN}📦 解压 ${TARBALL} ...${NC}"
    tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"
    EXTRACTED="$TMP_DIR/cc-planet-${TAG}"
fi

# --- 安装 ---
echo -e "${CYAN}📦 安装到 $INSTALL_BASE ...${NC}"

# 备份旧目录
if [[ -d "$INSTALL_BASE" ]]; then
    BACKUP="${INSTALL_BASE}.bak.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}   ⚠️  备份旧版本: $BACKUP${NC}"
    mv "$INSTALL_BASE" "$BACKUP"
fi

mkdir -p "$INSTALL_BASE"

# 复制所有文件
cp -r "$EXTRACTED/"* "$INSTALL_BASE/"
chmod +x "$INSTALL_BASE/$BINARY" "$INSTALL_BASE/cc-notify.py" 2>/dev/null || true

echo -e "   ${GREEN}✓${NC} 安装完成:"
for f in "$INSTALL_BASE"/*; do
    echo -e "     $(basename "$f")"
done

# --- 可选：创建符号链接到 PATH ---
if command -v "$BINARY" &>/dev/null; then
    echo -e "${YELLOW}   ⚠️  检测到系统已有 $BINARY: $(command -v $BINARY)${NC}"
else
    echo -e "${CYAN}   🔗 创建符号链接 /usr/local/bin/${BINARY} ...${NC}"
    sudo ln -sf "$INSTALL_BASE/$BINARY" "/usr/local/bin/$BINARY"
    echo -e "   ${GREEN}✓${NC} $BINARY 已加入 PATH"
fi

# --- 验证 ---
echo -e "${CYAN}✅ 验证...${NC}"
INSTALLED_PATH=$(command -v "$BINARY" || echo "")
if [[ -n "$INSTALLED_PATH" ]]; then
    echo -e "${GREEN}   $BINARY 已就绪: $INSTALLED_PATH${NC}"
else
    echo -e "${YELLOW}   请将 $INSTALL_BASE 加入 PATH:${NC}"
    echo -e "   echo 'export PATH=\"\$PATH:$INSTALL_BASE\"' >> ~/.zshrc"
fi

echo ""
echo -e "${GREEN}✅ 安装完成!${NC}"
echo ""
echo -e "   运行:"
echo -e "     ${CYAN}$BINARY \"Hello World\"${NC}"
echo -e "     ${CYAN}$BINARY --success \"Build passed\"${NC}"
echo -e "     ${CYAN}$BINARY --failure \"Test failed\"${NC}"
echo ""
echo -e "   配置: ${CYAN}${INSTALL_BASE}/env.json${NC}"
echo -e "   文档: ${CYAN}${INSTALL_BASE}/README.md${NC}"
echo -e "   源码: ${CYAN}${INSTALL_BASE}/plane.png${NC}"
echo ""
echo -e "   CI/CD 集成 (cc-notify.py):"
echo -e "     ${CYAN}echo '\{\"stop_reason\":\"end_turn\"}' | ${INSTALL_BASE}/cc-notify.py${NC}"

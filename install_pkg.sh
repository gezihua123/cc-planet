#!/bin/bash
set -e

# --- 配置 ---
REPO="gezihua123/cc-planet"
BINARY="fly-airplane"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/usr/local/etc/fly-airplane"
DOWNLOAD_BASE="https://github.com/${REPO}/releases/download"

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
    echo "从 GitHub Releases 下载并安装 $BINARY 及配置文件"
    echo ""
    echo "参数:"
    echo "  版本号    可选，指定安装的版本（如 v0.0.1），默认为最新版"
    echo ""
    echo "示例:"
    echo "  ./install_pkg.sh           # 安装最新版"
    echo "  ./install_pkg.sh v0.0.1    # 安装指定版本"
    exit 0
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

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
    TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep '"tag_name"' \
        | sed 's/.*"tag_name": "\(.*\)",/\1/')
    if [[ -z "$TAG" ]]; then
        echo -e "${RED}❌ 无法获取最新版本，请检查网络或手动指定版本${NC}"
        exit 1
    fi
    echo -e "   最新版本: ${CYAN}$TAG${NC}"
fi

# --- 下载 tarball ---
TARBALL="fly-airplane-${TAG}.tar.gz"
DOWNLOAD_URL="${DOWNLOAD_BASE}/${TAG}/${TARBALL}"

echo -e "${CYAN}📥 下载 ${TARBALL} ...${NC}"
echo -e "   地址: ${CYAN}$DOWNLOAD_URL${NC}"

TMP_DIR=$(mktemp -d)
trap "rm -rf '$TMP_DIR'" EXIT

HTTP_CODE=$(curl -fSL# -o "$TMP_DIR/$TARBALL" "$DOWNLOAD_URL" -w "%{http_code}" 2>&1 | tail -1)

if [[ "$HTTP_CODE" != "200" ]]; then
    # 降级：尝试下载裸二进制（旧版 release 兼容）
    echo -e "${YELLOW}⚠️  未找到 tarball，尝试直接下载二进制...${NC}"
    BINARY_URL="${DOWNLOAD_BASE}/${TAG}/${BINARY}"
    HTTP_CODE=$(curl -fSL# -o "$TMP_DIR/$BINARY" "$BINARY_URL" -w "%{http_code}" 2>&1 | tail -1)
    if [[ "$HTTP_CODE" != "200" ]]; then
        echo -e "${RED}❌ 下载失败 (HTTP $HTTP_CODE)${NC}"
        echo -e "   请确认版本 $TAG 存在: https://github.com/$REPO/releases"
        exit 1
    fi
    chmod +x "$TMP_DIR/$BINARY"
    HAS_TARBALL=false
else
    HAS_TARBALL=true
fi

# --- 解压 ---
if [[ "$HAS_TARBALL" == "true" ]]; then
    echo -e "${CYAN}📦 解压 ${TARBALL} ...${NC}"
    tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"
    EXTRACTED="$TMP_DIR/fly-airplane-${TAG}"
else
    EXTRACTED="$TMP_DIR"
fi

# --- 校验 ---
echo -e "${CYAN}🔐 校验文件完整性...${NC}"
CHECKSUM_URL="${DOWNLOAD_BASE}/${TAG}/checksums.txt"
CHECKSUM=$(curl -fsSL "$CHECKSUM_URL" 2>/dev/null || true)
if [[ -n "$CHECKSUM" ]]; then
    EXPECTED=$(echo "$CHECKSUM" | grep "fly-airplane" | grep -v tar.gz | awk '{print $1}')
    if [[ -z "$EXPECTED" ]]; then
        EXPECTED=$(echo "$CHECKSUM" | grep "$TARBALL" | awk '{print $1}')
    fi
    if [[ -n "$EXPECTED" ]]; then
        ACTUAL=$(shasum -a 256 "$EXTRACTED/$BINARY" | awk '{print $1}')
        if [[ "$EXPECTED" != "$ACTUAL" ]]; then
            echo -e "${RED}❌ SHA256 校验失败${NC}"
            echo -e "   期望: $EXPECTED"
            echo -e "   实际: $ACTUAL"
            exit 1
        fi
        echo -e "${GREEN}   SHA256 校验通过${NC}"
    else
        echo -e "${YELLOW}   ⚠️  未找到校验和，跳过校验${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️  无 checksums.txt，跳过校验${NC}"
fi

# --- 检查旧版本 ---
if command -v "$BINARY" &>/dev/null; then
    OLD_PATH=$(command -v "$BINARY")
    echo -e "${YELLOW}   ⚠️  检测到旧版本: $OLD_PATH${NC}"
fi

# --- 安装二进制 ---
echo -e "${CYAN}📦 安装 $BINARY 到 $INSTALL_DIR ...${NC}"

if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}   目录 $INSTALL_DIR 不存在，正在创建...${NC}"
    sudo mkdir -p "$INSTALL_DIR"
fi

sudo cp "$EXTRACTED/$BINARY" "$INSTALL_DIR/$BINARY"
sudo chmod +x "$INSTALL_DIR/$BINARY"
echo -e "${GREEN}   ✓ $BINARY 已安装到 $INSTALL_DIR/$BINARY${NC}"

# --- 安装配置文件 ---
if [[ -f "$EXTRACTED/env.json" ]]; then
    echo -e "${CYAN}📦 安装配置文件到 $CONFIG_DIR ...${NC}"

    if [[ ! -d "$CONFIG_DIR" ]]; then
        sudo mkdir -p "$CONFIG_DIR"
    fi

    # 如果已存在，备份旧配置
    if [[ -f "$CONFIG_DIR/env.json" ]]; then
        BACKUP="${CONFIG_DIR}/env.json.bak.$(date +%Y%m%d%H%M%S)"
        echo -e "${YELLOW}   ⚠️  备份旧配置: $BACKUP${NC}"
        sudo cp "$CONFIG_DIR/env.json" "$BACKUP"
    fi

    sudo cp "$EXTRACTED/env.json" "$CONFIG_DIR/env.json"
    echo -e "${GREEN}   ✓ 配置文件已安装到 $CONFIG_DIR/env.json${NC}"
    echo -e "${YELLOW}   💡 按需编辑: sudo vim $CONFIG_DIR/env.json${NC}"
else
    echo -e "${YELLOW}   ⚠️  无配置文件，跳过${NC}"
fi

# --- 验证 ---
echo -e "${CYAN}✅ 验证安装...${NC}"

INSTALLED_PATH=$(command -v "$BINARY" || echo "")
if [[ -n "$INSTALLED_PATH" ]]; then
    echo -e "${GREEN}   $BINARY 已就绪: $INSTALLED_PATH${NC}"
else
    echo -e "${YELLOW}   $BINARY 已安装到 $INSTALL_DIR，但不在 PATH 中${NC}"
    echo -e "   请将 $INSTALL_DIR 添加到 PATH 或运行:"
    echo -e "   export PATH=\"\$PATH:$INSTALL_DIR\""
fi

# --- 完成 ---
echo ""
echo -e "${GREEN}✅ 安装完成!${NC}"
echo -e ""
echo -e "   运行: ${CYAN}$BINARY --help${NC}"
echo -e ""
echo -e "   示例:"
echo -e "     ${CYAN}$BINARY \"Hello World\"${NC}"
echo -e "     ${CYAN}$BINARY --success \"Build passed\"${NC}"
echo -e "     ${CYAN}$BINARY --failure \"Test failed\"${NC}"
echo -e "     ${CYAN}$BINARY --blocked \"Waiting review\"${NC}"
echo ""
echo -e "   配置编辑: ${CYAN}sudo vim ${CONFIG_DIR}/env.json${NC}"

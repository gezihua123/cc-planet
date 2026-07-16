#!/bin/bash
set -e

cd "$(dirname "$0")"

# --- 配置 ---
REMOTE="origin"
BRANCH="main"
DEFAULT_BUMP="patch"
REPO="gezihua123/cc-planet"
VERSION_FILE="version.properties"

# --- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 帮助 ---
usage() {
    echo "用法: ./release.sh [bump_type]"
    echo ""
    echo "发布新版本并推送到 GitHub"
    echo ""
    echo "参数:"
    echo "  bump_type    版本递增类型: major / minor / patch（默认: $DEFAULT_BUMP）"
    echo ""
    echo "示例:"
    echo "  ./release.sh            # patch 版本递增"
    echo "  ./release.sh minor      # minor 版本递增"
    echo "  ./release.sh major      # major 版本递增"
    exit 0
}

[[ "$1" == "-h" || "$1" == "--help" ]] && usage

BUMP="${1:-$DEFAULT_BUMP}"

# --- 前置检查 ---
echo -e "${CYAN}🔍 检查环境...${NC}"

if [[ -n "$(git status --porcelain)" ]]; then
    echo -e "${RED}❌ 工作区有未提交的更改，请先提交或暂存${NC}"
    git status --short
    exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
    echo -e "${RED}❌ 当前在 $CURRENT_BRANCH 分支，请切换到 $BRANCH 分支${NC}"
    exit 1
fi

if ! git remote get-url "$REMOTE" &>/dev/null; then
    echo -e "${RED}❌ Remote '$REMOTE' 不存在${NC}"
    exit 1
fi

# --- 从 version.properties 读取版本号 ---
if [[ ! -f "$VERSION_FILE" ]]; then
    echo -e "${RED}❌ $VERSION_FILE 不存在${NC}"
    exit 1
fi

source "$VERSION_FILE"
echo -e "   当前版本: ${CYAN}v$VERSION${NC}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
    *) echo -e "${RED}❌ 无效 bump_type: $BUMP（可选: major / minor / patch）${NC}"; exit 1 ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_TAG="v${NEW_VERSION}"

# --- 更新 version.properties ---
echo -e "${CYAN}📝 更新 $VERSION_FILE ...${NC}"
echo "VERSION=$NEW_VERSION" > "$VERSION_FILE"
echo -e "   ${GREEN}✓${NC} $VERSION_FILE: ${CYAN}$NEW_VERSION${NC}"

# --- 优先提交版本号并推送 ---
echo -e "${CYAN}🚀 提交版本号并推送...${NC}"
git add "$VERSION_FILE"
git commit -m "bump version to $NEW_TAG"
git push "$REMOTE" "$BRANCH"
echo -e "${GREEN}✅ 版本号已推送: ${CYAN}$NEW_TAG${NC}"

# --- 构建 ---
echo -e "${CYAN}🔨 构建项目...${NC}"
./build.sh
echo -e "${GREEN}✅ 构建成功${NC}"

# --- 打包所有资源 ---
echo -e "${CYAN}📦 打包资源...${NC}"

PKG_NAME="cc-planet-${NEW_TAG}"
PKG_DIR=$(mktemp -d)
PKG_DIR="${PKG_DIR}/${PKG_NAME}"
mkdir -p "$PKG_DIR"

FILES_TO_PACK=(
    "cc-planet"
    "env.json"
    "plane.png"
    "README.md"
    "README.en.md"
    "SKILL.md"
    "install_pkg.sh"
    "version.properties"
)

for file in "${FILES_TO_PACK[@]}"; do
    if [[ -f "$file" ]]; then
        cp "$file" "$PKG_DIR/"
        echo -e "   ${GREEN}✓${NC} $file"
    else
        echo -e "   ${YELLOW}⚠️  $file 不存在，跳过${NC}"
    fi
done

TARBALL="${PKG_NAME}.tar.gz"
tar -C "$(dirname "$PKG_DIR")" -czf "$TARBALL" "$PKG_NAME"

echo -e "   ${GREEN}✓${NC} 打包完成: ${CYAN}$TARBALL${NC}"
tar -tzf "$TARBALL" | sed 's/^/     /'

# --- 打 tag ---
echo -e "${CYAN}🏷️  打 tag $NEW_TAG ...${NC}"
git tag -a "$NEW_TAG" -m "release $NEW_TAG"

# --- 推送到 GitHub（tag + 构建产物记录） ---
echo -e "${CYAN}🚀 推送 tag 到 GitHub ...${NC}"
git push "$REMOTE" "$NEW_TAG"

# --- 创建 GitHub Release & 上传产物 ---
echo -e "${CYAN}📦 创建 GitHub Release 并上传产物...${NC}"

RELEASE_NOTES=$(mktemp)
cat > "$RELEASE_NOTES" <<-EOF
## $NEW_TAG

### 构建信息
- 平台: macOS 11+
- 架构: arm64 + x86_64 (Universal Binary)
- 版本文件: \`version.properties\`

### 包含文件
| 文件 | 说明 |
|------|------|
| \`cc-planet\` | 主程序（通用二进制） |
| \`env.json\` | 运行时配置模板 |
| \`plane.png\` | 飞机图片源文件 |
| \`README.md\` | 使用文档（中文） |
| \`README.en.md\` | 使用文档（英文） |
| \`SKILL.md\` | 技能文档 |
| \`install_pkg.sh\` | 安装脚本（自动创建 cc-notify 符号链接） |
| \`version.properties\` | 版本号配置 |

### 快速安装
\`\`\`bash
# 本地安装
curl -fsSL https://raw.githubusercontent.com/$REPO/main/install_pkg.sh | bash

# 全局安装
curl -fsSL https://raw.githubusercontent.com/$REPO/main/install_pkg.sh | bash -s -- --global
\`\`\`
EOF

if gh release create "$NEW_TAG" \
    --title "$NEW_TAG" \
    --notes-file "$RELEASE_NOTES" \
    "$TARBALL"; then
    rm -f "$RELEASE_NOTES"
    echo -e "${GREEN}✅ Release 已创建: https://github.com/$REPO/releases/tag/$NEW_TAG${NC}"

    # --- 更新 install_pkg.sh 默认版本号 ---
    echo -e "${CYAN}📝 更新 install_pkg.sh 默认版本号...${NC}"
    sed -i '' "s/^DEFAULT_VERSION=\".*\"/DEFAULT_VERSION=\"$NEW_TAG\"/" install_pkg.sh
    echo -e "   DEFAULT_VERSION -> ${CYAN}$NEW_TAG${NC}"

    git add install_pkg.sh
    git commit -m "bump install_pkg.sh default version to $NEW_TAG"
    git push "$REMOTE" "$BRANCH"
    echo -e "${GREEN}✅ install_pkg.sh 版本号已提交推送${NC}"
else
    rm -f "$RELEASE_NOTES"
    echo -e "${YELLOW}⚠️  gh release 创建失败，请手动创建${NC}"
    exit 1
fi

# --- 清理 ---
rm -rf "$(dirname "$PKG_DIR")" 2>/dev/null || true
rm -f "$TARBALL" 2>/dev/null || true

echo ""
echo -e "${GREEN}✅ 发布完成: ${NEW_TAG}${NC}"
echo -e "${GREEN}   代码已推送到 $REMOTE/$BRANCH${NC}"
echo -e "${GREEN}   产物已上传至 GitHub Release${NC}"
echo ""
echo -e "   安装命令:"
echo -e "   ${CYAN}curl -fsSL https://raw.githubusercontent.com/$REPO/main/install_pkg.sh | bash${NC}"

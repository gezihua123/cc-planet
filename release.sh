#!/bin/bash
set -e

cd "$(dirname "$0")"

# --- 配置 ---
REMOTE="origin"                    # git remote 名称
BRANCH="main"                      # 目标分支
DEFAULT_BUMP="patch"               # 默认版本递增: major / minor / patch

# --- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
fi

BUMP="${1:-$DEFAULT_BUMP}"

# --- 前置检查 ---
echo -e "${CYAN}🔍 检查环境...${NC}"

# 确保 git 工作区干净
if [[ -n "$(git status --porcelain)" ]]; then
    echo -e "${RED}❌ 工作区有未提交的更改，请先提交或暂存${NC}"
    git status --short
    exit 1
fi

# 确保在目标分支上
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
    echo -e "${RED}❌ 当前在 $CURRENT_BRANCH 分支，请切换到 $BRANCH 分支${NC}"
    exit 1
fi

# 确保有 remote
if ! git remote get-url "$REMOTE" &>/dev/null; then
    echo -e "${RED}❌ Remote '$REMOTE' 不存在${NC}"
    exit 1
fi

# --- 获取最新版本 tag ---
LATEST_TAG=$(git tag --sort=-v:refname | head -n 1)
if [[ -z "$LATEST_TAG" ]]; then
    echo -e "${YELLOW}⚠️  没有找到已有 tag，从 v0.0.0 开始${NC}"
    LATEST_TAG="v0.0.0"
fi
echo -e "   最新 tag: ${CYAN}$LATEST_TAG${NC}"

# --- 解析并递增版本号 ---
VERSION="${LATEST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

case "$BUMP" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        echo -e "${RED}❌ 无效的 bump_type: $BUMP（可选: major / minor / patch）${NC}"
        exit 1
        ;;
esac

NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"

# --- 构建 ---
echo -e "${CYAN}🔨 构建项目...${NC}"
./build.sh
echo -e "${GREEN}✅ 构建成功${NC}"

# --- 提交 & 打 tag ---
echo -e "${CYAN}🏷️  创建发布 $NEW_TAG ...${NC}"

git add -A
git commit --allow-empty -m "release $NEW_TAG"
git tag -a "$NEW_TAG" -m "release $NEW_TAG"

# --- 推送到 GitHub ---
echo -e "${CYAN}🚀 推送到 GitHub ($REMOTE/$BRANCH) ...${NC}"
git push "$REMOTE" "$BRANCH"
git push "$REMOTE" "$NEW_TAG"

# --- 创建 GitHub Release & 上传产物 ---
echo -e "${CYAN}📦 创建 GitHub Release 并上传产物...${NC}"

RELEASE_NOTES=$(mktemp)
cat > "$RELEASE_NOTES" <<-EOF
## $NEW_TAG

### 构建信息
- 平台: macOS 11+
- 架构: arm64 + x86_64 (Universal Binary)
- 文件: \`fly-airplane\`

### 使用
\`\`\`bash
./fly-airplane [--success | --failure | --blocked] [<消息文本>]
\`\`\`
EOF

if gh release create "$NEW_TAG" \
    --title "$NEW_TAG" \
    --notes-file "$RELEASE_NOTES" \
    "fly-airplane"; then
    rm -f "$RELEASE_NOTES"
    echo -e "${GREEN}✅ Release 已创建: https://github.com/gezihua123/cc-planet/releases/tag/$NEW_TAG${NC}"
else
    rm -f "$RELEASE_NOTES"
    echo -e "${YELLOW}⚠️  gh release 创建失败，请手动创建 Release${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ 发布完成: ${NEW_TAG}${NC}"
echo -e "${GREEN}   代码已推送到 $REMOTE/$BRANCH${NC}"
echo -e "${GREEN}   产物已上传至 GitHub Release${NC}"

#!/bin/zsh
# =====================================================================
# maycur_subsidy_drl 技能自动同步 GitHub 脚本 (专业增强版)
# =====================================================================

# 1. 颜色定义（美化终端输出）
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 2. 动态定位脚本所在目录（兼容任意执行路径）
SKILL_DIR="${0:A:h}"
if [[ ! -d "$SKILL_DIR/.git" ]]; then
    SKILL_DIR="/Users/snowlu16/Documents/每刻交付/补贴脚本开发/.agents/skills/maycur_subsidy_drl"
fi
cd "$SKILL_DIR" || { echo "${RED}❌ 目录不存在: $SKILL_DIR${NC}"; exit 1 }

# 3. 获取当前分支名称（默认 main）
BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
LOG_FILE="$SKILL_DIR/.sync.log"

echo "${CYAN}=====================================================================${NC}"
echo "${CYAN}🚀 开始同步技能目录: [ $BRANCH 分支 ] -> GitHub${NC}"
echo "${CYAN}📂 本地目录: $SKILL_DIR${NC}"
echo "${CYAN}=====================================================================${NC}"

# 4. 自动尝试拉取远程最新代码（避免多端修改冲突，以 rebase 方式合并）
echo "${YELLOW}🔄 正在检查远程仓库是否有更新...${NC}"
git pull --rebase origin "$BRANCH" 2>/dev/null
if [[ $? -ne 0 ]]; then
    echo "${YELLOW}⚠️ 注意: 拉取远程变更遇到提示或暂无关联更新，继续执行后续步骤...${NC}"
fi

# 5. 自动打包当前技能目录为 zip 文件（供上传 SkillHub 或分发）
ZIP_NAME="maycur_subsidy_drl.zip"
echo "${YELLOW}📦 正在自动打包生成最新的 $ZIP_NAME (排除 .git 及日志等)...${NC}"
PARENT_DIR="${SKILL_DIR:h}"
rm -f "$SKILL_DIR/$ZIP_NAME" "/Users/snowlu16/Documents/每刻交付/补贴脚本开发/$ZIP_NAME" 2>/dev/null
(
    cd "$PARENT_DIR" || exit 1
    # 安静且高压缩比打包 maycur_subsidy_drl 文件夹
    zip -q -r -9 "$SKILL_DIR/$ZIP_NAME" "maycur_subsidy_drl" -x "*/.git/*" "*/.DS_Store*" "*/.*.log" "*$ZIP_NAME*"
    # 同时复制一份到工作区根目录下方便随手获取
    cp -f "$SKILL_DIR/$ZIP_NAME" "/Users/snowlu16/Documents/每刻交付/补贴脚本开发/$ZIP_NAME" 2>/dev/null
)
if [[ -f "$SKILL_DIR/$ZIP_NAME" ]]; then
    ZIP_SIZE=$(du -h "$SKILL_DIR/$ZIP_NAME" | cut -f1 | tr -d ' ')
    echo "${GREEN}🎁 打包成功！ZIP 压缩包路径 (文件大小: $ZIP_SIZE)：${NC}"
    echo "${CYAN}   1️⃣  $SKILL_DIR/$ZIP_NAME${NC}"
    echo "${CYAN}   2️⃣  /Users/snowlu16/Documents/每刻交付/补贴脚本开发/$ZIP_NAME${NC}"
fi

# 6. 检查本地是否有新增、修改或未提交的文件
MODIFIED_FILES=$(git status --porcelain)
if [[ -n "$MODIFIED_FILES" ]]; then
    echo "${YELLOW}⚡ 检测到本地技能文件有修改或新增：${NC}"
    echo "$MODIFIED_FILES" | head -n 10
    [[ $(echo "$MODIFIED_FILES" | wc -l) -gt 10 ]] && echo "..."
    
    echo "${GREEN}📦 正在自动暂存并提交 (git commit)...${NC}"
    git add .
    COMMIT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    git commit -m "chore(skill): auto sync update $COMMIT_TIME"
fi

# 6. 检查本地分支是否领先于远程分支 (或是否有需要 push 的新 commit)
UNPUSHED_COUNT=$(git log "origin/$BRANCH..HEAD" --oneline 2>/dev/null | wc -l | tr -d ' ')
if [[ "$UNPUSHED_COUNT" -gt 0 || -n $(git status -sb | grep -E "ahead|No commits yet on remote") ]]; then
    echo "${GREEN}📤 正在推送到 GitHub (git push -u origin $BRANCH)...${NC}"
    git push -u origin "$BRANCH"
    PUSH_STATUS=$?
    
    if [[ $PUSH_STATUS -eq 0 ]]; then
        echo "${GREEN}✅ [$(date '+%Y-%m-%d %H:%M:%S')] 自动推送到 GitHub 成功！已同步最新修改。${NC}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Pushed to origin/$BRANCH" >> "$LOG_FILE"
    else
        echo "${RED}❌ [$(date '+%Y-%m-%d %H:%M:%S')] 推送失败，请检查网络连接或 SSH 密钥权限。${NC}"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Push failed" >> "$LOG_FILE"
        exit 1
    fi
else
    echo "${GREEN}✨ 当前本地仓库与 GitHub 远程完全一致，无需重复推送。${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Already up-to-date" >> "$LOG_FILE"
fi

echo "${CYAN}=====================================================================${NC}"

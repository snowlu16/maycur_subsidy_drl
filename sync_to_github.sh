#!/bin/zsh
# maycur_subsidy_drl 技能自动同步 GitHub 脚本

SKILL_DIR="/Users/snowlu16/Documents/每刻交付/补贴脚本开发/.agents/skills/maycur_subsidy_drl"
cd "$SKILL_DIR" || exit 1

# 检查当前 git 状态是否有变动或未提交的文件
if [[ -n $(git status --porcelain) ]]; then
    echo "⚡ 检测到本地技能文件有修改，正在自动提交..."
    git add .
    git commit -m "chore(skill): auto sync update $(date '+%Y-%m-%d %H:%M:%S')"
fi

# 检查是否有需要 push 的 commit
if [[ $(git log origin/main..HEAD 2>/dev/null | wc -l) -gt 0 || $(git status -sb | grep -E "ahead|No commits yet on remote") ]]; then
    echo "🚀 正在推送到 GitHub..."
    git push -u origin main
    if [[ $? -eq 0 ]]; then
        echo "✅ [$(date '+%Y-%m-%d %H:%M:%S')] 自动同步到 GitHub 成功！"
    else
        echo "❌ [$(date '+%Y-%m-%d %H:%M:%S')] 推送失败，请检查网络或 GitHub 授权（SSH Key / Token）。"
    fi
else
    echo "ℹ️ 当前没有新的修改需要同步。"
fi

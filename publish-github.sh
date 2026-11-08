#!/bin/bash
# 一键发布 stillwave 到 GitHub
# 前提：gh 已安装并已登录（gh auth login）
# 用法：bash publish-github.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v gh >/dev/null 2>&1; then
  echo "✗ 没找到 gh。先安装：brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "✗ gh 尚未登录。先运行：gh auth login" >&2
  echo "  选择 GitHub.com → HTTPS → Login with a web browser，浏览器里输入一次性验证码。" >&2
  exit 1
fi

if gh repo view stillwave >/dev/null 2>&1; then
  echo "⚠ 已存在同名仓库 stillwave，改用推送模式："
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/$(gh api user -q .login)/stillwave.git"
  fi
  git push -u origin main
else
  DESC="叩音 Stillwave — 单手叩出五音的水面解压 App · iOS + watchOS · MIT 开源"
  echo "→ 创建公开仓库 stillwave 并推送…"
  gh repo create stillwave --public --source=. --remote=origin --push --description "$DESC"
fi

echo "→ 配置话题标签…"
gh repo edit --add-topic ios --add-topic watchos --add-topic swiftui \
  --add-topic webgl --add-topic haptics --add-topic meditation \
  --add-topic stress-relief --add-topic generative-music --add-topic apple-watch >/dev/null

echo "✓ 完成：https://github.com/$(gh api user -q .login)/stillwave"

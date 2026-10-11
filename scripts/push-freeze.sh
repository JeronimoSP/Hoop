#!/usr/bin/env bash
# Run locally after `gh auth login` (api.github.com must be reachable).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="${PATH}:$(pwd)/.tools"
gh auth status
gh repo create circulo --private --source=. --remote=origin --push \
  || git push -u origin main
git push origin v0-freeze
echo "Freeze remote: https://github.com/$(gh api user --jq .login)/circulo"
echo "Tag: v0-freeze"

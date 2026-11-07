#!/usr/bin/env bash
# Installs the two design skills agents use in this repo into .claude/skills (git-ignored).
#
#   apple-hig        Apple HIG reference + /duo workflow, pinned to justinwetch/HIGAgentSkills@77f32a4
#                    (release 2026-09-27, the one FestivalNativeApps uses). Public, fetched from GitHub.
#   app-designer-pro Paid skill the owner bought. Never committed (this repo is public). Copied from
#                    $APP_DESIGNER_PRO_SRC, else the project's shared folder, else ~/.claude/skills.
#
# Usage: tools/install_design_skills.sh            # both
#        tools/install_design_skills.sh apple-hig  # one
# See .agents/design/README.md for when to use each.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="$ROOT/.claude/skills"
COMMANDS="$ROOT/.claude/commands"
HIG_REPO="https://github.com/justinwetch/HIGAgentSkills.git"
HIG_REV="77f32a4"
WANT="${1:-all}"

mkdir -p "$SKILLS" "$COMMANDS"

install_hig() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git clone -q "$HIG_REPO" "$tmp/hig"
  git -C "$tmp/hig" checkout -q "$HIG_REV"
  rm -rf "$SKILLS/apple-hig"
  mkdir -p "$SKILLS/apple-hig/scripts"
  # The runtime set from the release's shipping manifest; sources/, docs/ and tests/ stay out.
  (cd "$tmp/hig" && cp -R SKILL.md README.md routing-index.md references commands "$SKILLS/apple-hig/")
  cp "$tmp/hig/scripts/hig_route.py" "$tmp/hig/scripts/hig_enforce.py" "$SKILLS/apple-hig/scripts/"
  cp "$tmp/hig/commands/duo.md" "$COMMANDS/duo.md"
  echo "apple-hig $HIG_REV -> $SKILLS/apple-hig (/duo -> $COMMANDS/duo.md)"
}

install_designer() {
  local src=""
  for candidate in "${APP_DESIGNER_PRO_SRC:-}" /mnt/project-files/skills/app-designer-pro "$HOME/.claude/skills/app-designer-pro"; do
    if [ -n "$candidate" ] && [ -f "$candidate/SKILL.md" ]; then src="$candidate"; break; fi
  done
  if [ -z "$src" ]; then
    echo "app-designer-pro: no copy found. Set APP_DESIGNER_PRO_SRC to the unzipped app-designer-pro folder." >&2
    return 1
  fi
  rm -rf "$SKILLS/app-designer-pro"
  cp -R "$src" "$SKILLS/app-designer-pro"
  rm -rf "$SKILLS/app-designer-pro/node_modules"
  (cd "$SKILLS/app-designer-pro" && npm install --no-fund --no-audit --silent)
  echo "app-designer-pro <- $src -> $SKILLS/app-designer-pro"
  echo "  Renders use Google Chrome on a Mac (SF Pro). Elsewhere set APP_DESIGNER_CHROME to a Chromium binary;"
  echo "  SF Pro then falls back to a look-alike, so judge type on a Mac render."
}

case "$WANT" in
  all) install_hig; install_designer ;;
  apple-hig) install_hig ;;
  app-designer-pro) install_designer ;;
  *) echo "usage: $0 [all|apple-hig|app-designer-pro]" >&2; exit 2 ;;
esac

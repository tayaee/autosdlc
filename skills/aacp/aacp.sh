#!/usr/bin/env bash
# aacpd — Archive issue, git Add -u, Commit, Push, Deploy (dev only).
#
# Usage:
#   aacp.sh <issue-number> <commit-summary...>   # process one issue, no prompts
#   aacp.sh --pending                             # list issue numbers ready to deploy
#
# NOTE ON NAMING: this script is named after the four steps it actually
# implements — Archive, (git) Add, Commit, Push. The fifth step, Deploy, is
# deliberately NOT this skill's own logic: each target repo is expected to
# provide its own deploy entry point (see step 5 below). This file is
# `.claude/skills/aacpd/aacp.sh`; the deploy script it calls at the end is
# `<target-repo>/deploy-to-dev.sh` or `<target-repo>/deploy.sh` — a
# different file this skill never generates.
#
# Preconditions: run from inside the target repo (any subdirectory). Code
# changes for the issue must already be `git add`ed — that's the hand-off
# point from /tdd2.
#
# Never touches qa/prod. Only ever deploys --env dev.
set -euo pipefail

ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "$HOME/.local/bin/uv" ]; then
        export PATH="$HOME/.local/bin:$PATH"
        return 0
    fi
    if command -v mise >/dev/null 2>&1; then
        echo "uv를 찾을 수 없습니다. mise를 사용하여 uv를 설치합니다..." >&2
        mise use -g uv@latest >/dev/null 2>&1 || mise install uv >/dev/null 2>&1 || true
        if command -v mise >/dev/null 2>&1; then
            eval "$(mise env 2>/dev/null)" || true
        fi
        if command -v uv >/dev/null 2>&1; then
            uv python install >/dev/null 2>&1 || true
            return 0
        fi
    fi
    echo "[원인] uv 또는 mise를 찾을 수 없습니다." >&2
    echo "[조치] curl -LsSf https://astral.sh/uv/install.sh | sh 또는 mise install uv를 실행하세요." >&2
    exit 127
}
ensure_uv


if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  echo "aacp: 4단계 (deploy 없음); aacpd: 5단계 (deploy 포함)"
  exit 0
fi

# Check if 4-step mode (no deploy) is requested via flag or script directory 'aacp'
NO_DEPLOY=false
if [ "${1:-}" = "--no-deploy" ]; then
  NO_DEPLOY=true
  shift
fi
SCRIPT_DIR_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
if [ "$SCRIPT_DIR_NAME" = "aacp" ]; then
  NO_DEPLOY=true
fi

usage() {
  echo "Usage: aacp.sh <issue-number> <commit-summary...>" >&2
  echo "       aacp.sh --pending" >&2
  exit 1
}

[ $# -ge 1 ] || usage

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# --pending: an issue is "pending deploy" once tdd2 has filled in its
# `## 구현 결과` section (구현 완료 일시 is no longer the "(미정)" placeholder)
# but the issue file hasn't been archived yet. No separate state file —
# this reuses the issue template's own completion marker.
if [ "${1:-}" = "--pending" ]; then
  shopt -s nullglob
  for f in issues/issue-*.md issues/autofix-*.md; do
    # 산출물·파킹 마커가 붙은 파일 제외
    [[ "$f" == *__* ]] && continue
    if grep -q '\*\*구현 완료 일시\*\*:' "$f" \
       && ! grep -q '\*\*구현 완료 일시\*\*: *(미정)' "$f"; then
      # 슬러그를 제거하고 stream-N 형식으로만 출력
      fname=$(basename "$f" .md)      # e.g. issue-280-some-slug
      stream_part="${fname%%-*}"      # issue / autofix
      rest="${fname#*-}"              # 280-some-slug 또는 280
      n_part="${rest%%-*}"            # 280
      echo "${stream_part}-${n_part}"
    fi
  done
  exit 0
fi

[ $# -ge 2 ] || usage
ISSUE_NUM="$1"
shift
SUMMARY="$*"

# Stream detection: "issue-N" / "autofix-N" / bare "N" (defaults to issue).
case "$ISSUE_NUM" in
    issue-*|autofix-*) STREAM="${ISSUE_NUM%%-*}"; N="${ISSUE_NUM#*-}" ;;
    *)                 STREAM="issue";            N="$ISSUE_NUM" ;;
esac

# 슬러그 없는 경로 우선 시도; 없으면 슬러그 있는 후보 자동 탐색.
# 산출물·마커 파일(__가 포함된 파일)은 제외한다.
ISSUE_FILE="issues/${STREAM}-${N}.md"
if [ ! -f "$ISSUE_FILE" ]; then
  shopt -s nullglob
  SLUG_CANDIDATES=("issues/${STREAM}-${N}"-*.md)
  shopt -u nullglob
  # 마커 파일(__) 제외
  ISSUE_FILE=""
  for _c in "${SLUG_CANDIDATES[@]}"; do
    [[ "$_c" == *__* ]] && continue
    ISSUE_FILE="$_c"
    break
  done
  if [ -z "$ISSUE_FILE" ] || [ ! -f "$ISSUE_FILE" ]; then
    echo "ERROR: issues/${STREAM}-${N}.md (또는 슬러그 변형) not found" >&2
    exit 1
  fi
fi
# 아카이브 시 원본 파일명(슬러그 포함)을 그대로 보존한다.
ISSUE_BASENAME=$(basename "$ISSUE_FILE")

# 0. Python-project verification gate. Detected via pyproject.toml at the
# repo root. For each check, prefer the project's own ./run-<name>.sh if it
# exists (and is executable); otherwise fall back to this skill's bundled
# default in bin/ (never copied into the project — see SKILL.md).
# Runs before any git mutation, so a failure here leaves the repo untouched.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${AUTOSDLC_BIN_DIR:-}" ]; then
  if [ -d "$SKILL_DIR/../../bin" ]; then
    BIN_DIR="$(cd "$SKILL_DIR/../../bin" && pwd)"
  elif [ -d "$SKILL_DIR/../bin" ]; then
    BIN_DIR="$(cd "$SKILL_DIR/../bin" && pwd)"
  else
    BIN_DIR="$HOME/.claude/bin"
  fi
else
  BIN_DIR="$AUTOSDLC_BIN_DIR"
fi

run_check() {
  local name="$1"
  if [ -x "./${name}.sh" ]; then
    [ "${AACP_VERBOSE:-0}" = "1" ] && echo "--- ${name} (project script) ---"
    "./${name}.sh"
  else
    [ "${AACP_VERBOSE:-0}" = "1" ] && echo "--- ${name} (aacpd bin default) ---"
    bash "$BIN_DIR/${name}.sh"
  fi
}

if [ -f pyproject.toml ]; then
  echo "Python project detected (pyproject.toml) — running verification gate before merge..."
  for chk in run-ruff run-pyright run-unit-tests run-regression-tests run-pyright-full; do
    run_check "$chk"
  done
fi

# 1. Stage the issue file's own changes (e.g. the "구현 결과" section).
git add "$ISSUE_FILE"

# 2. Archive: move to issues/archive/YYYY/MM/DD/ (git mv auto-stages the rename).
ARCHIVE_DIR="issues/archive/$(date +%Y/%m/%d)"
mkdir -p "$ARCHIVE_DIR"
git mv "$ISSUE_FILE" "$ARCHIVE_DIR/${ISSUE_BASENAME}"

# 2.5. Archive this issue's output artifacts alongside it (code-review
# files, refix-plan, agent-stats.json).
shopt -s nullglob
TYPE_FILES=(
  issues/"${STREAM}-${N}"__code-review-by-*
  issues/"${STREAM}-${N}"__refix-plan.md
  issues/"${STREAM}-${N}"__agent-stats.json
)
shopt -u nullglob
for tf in "${TYPE_FILES[@]}"; do
  [ -e "$tf" ] || continue
  case "$tf" in
    *__agent-stats.json)
      if [ -f "$BIN_DIR/log-cost.sh" ]; then
        bash "$BIN_DIR/log-cost.sh" "$REPO_ROOT" "${STREAM}-${N}" "archive-start"
      fi
      if [ -f "$BIN_DIR/log-cost-summary.py" ]; then
        uv run "$BIN_DIR/log-cost-summary.py" "$REPO_ROOT" "${STREAM}-${N}"
      elif [ -f "$REPO_ROOT/bin/log-cost-summary.py" ]; then
        uv run "$REPO_ROOT/bin/log-cost-summary.py" "$REPO_ROOT" "${STREAM}-${N}"
      fi
      if [ -f "$BIN_DIR/agent-stats-archive.py" ]; then
        uv run "$BIN_DIR/agent-stats-archive.py" "$REPO_ROOT" "${STREAM}-${N}"
      fi
      ;;
  esac
  git mv "$tf" "$ARCHIVE_DIR/$(basename "$tf")"
done

# 3. Stage the rest of the already-tracked changes (never untracked files).
git add -u

# 4. Commit code + archiving as ONE commit.
COMMIT_MSG="${STREAM}-${N}: ${SUMMARY}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git commit -m "$COMMIT_MSG"

# 5. Push.
git push

# 6. Deploy — dev only, ever.
DEPLOY_STATUS="no deploy-to-dev.sh or deploy.sh found — deploy skipped"
if [ "$NO_DEPLOY" = "true" ]; then
  DEPLOY_STATUS="deploy skipped (aacp 4-step mode)"
  echo "NOTE: aacp 4-step mode — deploy skipped." >&2
elif [ -f deploy-to-dev.sh ]; then
  bash deploy-to-dev.sh
  DEPLOY_STATUS="deploy-to-dev.sh run"
elif [ -f deploy.sh ]; then
  bash deploy.sh --env dev
  DEPLOY_STATUS="deploy.sh --env dev run"
else
  echo "NOTE: this project has no deploy-to-dev.sh or deploy.sh — skipping deploy." >&2
  echo "Add one (deploy-to-dev.sh, or deploy.sh accepting --env <env>) to enable it." >&2
fi

echo "✓ aacpd complete: issue-${ISSUE_NUM} archived to ${ARCHIVE_DIR}/, committed, pushed, ${DEPLOY_STATUS}."

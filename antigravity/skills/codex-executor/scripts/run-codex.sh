#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-codex.sh [OPTIONS] <doc-or-task-file> [workdir]

Options:
  --review                 Read-only design review mode (forces `--sandbox read-only`)
  --resume <session-id>    Resume an existing Codex session for targeted rework
  --safe                   Use `--sandbox workspace-write` (exec) / omit full bypass (resume)
  --effort <level>         Override reasoning effort (low|medium|high|xhigh|max)
  --model <model>          Override Codex model for this run
  -h, --help               Show this help
EOF
}

TASK_FILE=""
WORKDIR="$(pwd)"
REVIEW_MODE=0
RESUME_ID=""
SAFE_MODE=0
EFFORT=""
MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --review)
      REVIEW_MODE=1
      shift
      ;;
    --resume)
      RESUME_ID="${2:?Missing value for --resume}"
      shift 2
      ;;
    --safe)
      SAFE_MODE=1
      shift
      ;;
    --effort)
      EFFORT="${2:?Missing value for --effort}"
      case "$EFFORT" in
        low|medium|high|xhigh|max) ;;
        *)
          echo "Error: invalid --effort value '$EFFORT' (expected: low|medium|high|xhigh|max)" >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    --model)
      MODEL="${2:?Missing value for --model}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -z "$TASK_FILE" ]]; then
        TASK_FILE="$1"
      else
        WORKDIR="$1"
      fi
      shift
      ;;
  esac
done

if [[ "$REVIEW_MODE" -eq 1 && -n "$RESUME_ID" ]]; then
  echo "Error: --review cannot be combined with --resume." >&2
  exit 2
fi

if [[ -z "$TASK_FILE" ]]; then
  echo "Error: <doc-or-task-file> is required." >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "Error: file not found: $TASK_FILE" >&2
  exit 2
fi

TASK_FILE="$(realpath "$TASK_FILE")"
WORKDIR="$(realpath "$WORKDIR")"

# Ensure common user binary paths (mise/nvm/local) are in PATH in non-login shells
if ! command -v codex >/dev/null 2>&1; then
  for p in \
    "$HOME/.local/share/mise/shims" \
    "$HOME/.local/bin" \
    "$HOME/.bun/bin"; do
    [[ -d "$p" ]] && export PATH="$p:$PATH"
  done
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: 'codex' command not found in PATH ($PATH)." >&2
  echo "Hint: verify codex is installed and Antigravity sandbox is disabled or bypassed." >&2
  exit 127
fi

REPORT_DIR="/tmp/codex-reports"
mkdir -p "$REPORT_DIR"
RAW_BASE="$(basename "$TASK_FILE" .md)"
TASK_SLUG="$(printf '%s' "$RAW_BASE" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')"
[[ -n "$TASK_SLUG" ]] || TASK_SLUG="task"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

IS_GIT_REPO=1
if ! git -C "$WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT_REPO=0
fi

if [[ -n "$RESUME_ID" ]]; then
  MODE="resume"
  REPORT_FILE="${REPORT_DIR}/resume-${TASK_SLUG}-${TIMESTAMP}.md"
  CMD=(codex exec resume --output-last-message "$REPORT_FILE")
  if [[ "$SAFE_MODE" -eq 0 ]]; then
    CMD+=(--dangerously-bypass-approvals-and-sandbox)
  fi
  if [[ "$IS_GIT_REPO" -eq 0 ]]; then
    CMD+=(--skip-git-repo-check)
  fi
  if [[ -n "$MODEL" ]]; then
    CMD+=(-m "$MODEL")
  fi
  if [[ -n "$EFFORT" ]]; then
    CMD+=(-c "model_reasoning_effort=\"$EFFORT\"")
  fi
  PROMPT="请阅读返工/补充说明 ${TASK_FILE}，在当前会话上下文基础上严格按范围与 Non-Goals 完成修复并重新运行验收命令。完成后汇报改动文件、验收结果及任何残余风险。"
  CMD+=("$RESUME_ID" "$PROMPT")
elif [[ "$REVIEW_MODE" -eq 1 ]]; then
  MODE="review"
  REPORT_FILE="${REPORT_DIR}/review-${TASK_SLUG}-${TIMESTAMP}.md"
  CMD=(codex exec -C "$WORKDIR" --color never --sandbox read-only --output-last-message "$REPORT_FILE")
  if [[ "$IS_GIT_REPO" -eq 0 ]]; then
    CMD+=(--skip-git-repo-check)
  fi
  if [[ -n "$MODEL" ]]; then
    CMD+=(-m "$MODEL")
  fi
  if [[ -n "$EFFORT" ]]; then
    CMD+=(-c "model_reasoning_effort=\"$EFFORT\"")
  fi
  PROMPT="这是一次**只读设计方案 Review**，请勿修改任何文件。请先阅读仓库中的 AGENTS.md（若存在）并结合真实代码库，仔细审查设计方案 ${TASK_FILE}。请重点核对：1) 方案中的文件路径、符号、调用链或行为假设是否与现有代码库不符；2) 是否遗漏了隐含依赖、受影响模块或破坏性变更；3) 核心逻辑、并发/数据一致性与边界风险。请按严重级别分组输出简洁的中文 Review 报告：[Blocker / 事实错误或主路径隐患]、[Important / 重要设计缺口]、[Edge-case / 极端临界条件]，并对每条建议标注**触发概率**与**修复引入的代码复杂度代价（低/中/高）**，便于架构师在严谨性与可维护性之间做权衡。"
  CMD+=("$PROMPT")
else
  MODE="exec"
  REPORT_FILE="${REPORT_DIR}/${TASK_SLUG}-${TIMESTAMP}.md"
  CMD=(codex exec -C "$WORKDIR" --color never --output-last-message "$REPORT_FILE")
  if [[ "$SAFE_MODE" -eq 1 ]]; then
    CMD+=(--sandbox workspace-write)
  else
    CMD+=(--dangerously-bypass-approvals-and-sandbox)
  fi
  if [[ "$IS_GIT_REPO" -eq 0 ]]; then
    CMD+=(--skip-git-repo-check)
  fi
  if [[ -n "$MODEL" ]]; then
    CMD+=(-m "$MODEL")
  fi
  if [[ -n "$EFFORT" ]]; then
    CMD+=(-c "model_reasoning_effort=\"$EFFORT\"")
  fi
  PROMPT="请先阅读仓库中的 AGENTS.md（若存在），然后完整阅读任务单 ${TASK_FILE}。严格按照任务单的目标、修改范围、约束与 Non-Goals（明确不做项，禁止对已排除的极端边界做过度防御式编程）完成代码落地，并亲自运行任务单中的全部验收命令。完成后输出简洁清晰的中文汇报，包含：1) 修改/新增的文件清单；2) 运行的验收命令及实际结果；3) 任何未解决的问题或风险。"
  CMD+=("$PROMPT")
fi

echo "MODE=$MODE"
echo "WORKDIR=$WORKDIR"
echo "TASK_FILE=$TASK_FILE"
echo "REPORT_FILE=$REPORT_FILE"
[[ -n "$EFFORT" ]] && echo "EFFORT=$EFFORT"
[[ -n "$RESUME_ID" ]] && echo "RESUME_ID=$RESUME_ID"

if [[ "$MODE" == "resume" ]]; then
  (cd "$WORKDIR" && "${CMD[@]}")
else
  "${CMD[@]}"
fi

echo "CODEX_DONE=1"
echo "REPORT_FILE=$REPORT_FILE"

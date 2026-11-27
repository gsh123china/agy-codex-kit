#!/usr/bin/env bash
{
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run-codex.sh [OPTIONS] <doc-or-task-file> [workdir]

Options:
  --review                 Pre-implementation read-only design review (`--sandbox read-only`)
  --code-review            Post-implementation independent read-only code review (`--sandbox read-only`)
  --resume <session-id>    Resume session for [BLOCKED] clarification or targeted rework (max 2 rework retries)
  --safe                   Use `--sandbox workspace-write` (exec & resume)
  --effort <level>         Override reasoning effort (low|medium|high|xhigh|max)
  --model <model>          Override Codex model for this run
  -h, --help               Show this help
EOF
}

TASK_FILE=""
WORKDIR="$(pwd)"
WORKDIR_SET=0
REVIEW_MODE=0
CODE_REVIEW_MODE=0
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
    --code-review)
      CODE_REVIEW_MODE=1
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
      elif [[ "$WORKDIR_SET" -eq 0 ]]; then
        WORKDIR="$1"
        WORKDIR_SET=1
      else
        echo "Error: unexpected extra argument: $1" >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
  esac
done

HAS_RESUME=0
if [[ -n "$RESUME_ID" ]]; then
  HAS_RESUME=1
fi

if (( REVIEW_MODE + CODE_REVIEW_MODE + HAS_RESUME > 1 )); then
  echo "Error: --review, --code-review, and --resume are mutually exclusive." >&2
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

if [[ ! -d "$WORKDIR" ]]; then
  echo "Error: workdir directory not found: $WORKDIR" >&2
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
    if [[ -d "$p" ]]; then
      export PATH="$p:$PATH"
    fi
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
TIMESTAMP="$(date +%Y%m%d-%H%M%S)-$$"

IS_GIT_REPO=1
if ! git -C "$WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT_REPO=0
fi

if [[ "$CODE_REVIEW_MODE" -eq 1 && "$IS_GIT_REPO" -eq 0 ]]; then
  echo "Error: --code-review requires workdir to be inside a Git repository: $WORKDIR" >&2
  exit 2
fi

if [[ -n "$RESUME_ID" ]]; then
  MODE="resume"
  REPORT_FILE="${REPORT_DIR}/resume-${TASK_SLUG}-${TIMESTAMP}.md"
  CMD=(codex exec resume --output-last-message "$REPORT_FILE")
  if [[ "$SAFE_MODE" -eq 1 ]]; then
    CMD+=(-c 'sandbox_mode="workspace-write"')
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
  PROMPT="请阅读澄清裁决或返工说明 ${TASK_FILE}，在当前会话上下文基础上严格按修改范围与 Non-Goals 完成代码落地或定向修复（若仍发现新的代码库事实硬冲突、禁改范围冲突或未授权高危破坏性分叉，同样禁止盲猜硬改，须保持无本轮残留污染改动并在汇报首行输出 [BLOCKED] 列出代码证据与待确认问题），并亲自运行全部验收命令（严禁为使测试通过而删改、放宽既有测试断言或验收标准，严禁执行 git add/commit/push）。正常完成后输出简洁中文汇报，包含：1) 本次修改/新增的文件清单；2) 运行的验收命令及实际结果；3) 任何未解决的问题或残余风险；4) 本次新增的自行假设与决定（Unstated Decisions，若无请写“无”）。"
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
  PROMPT="这是一次**只读设计方案 Review**，请勿修改任何文件。请先阅读仓库中的 AGENTS.md（若存在）并结合真实代码库，仔细审查设计方案 ${TASK_FILE}。请重点核对：1) 方案中的文件路径、符号、调用链或行为假设是否与现有代码库不符；2) 模块边界与数据归属是否清晰，带界面特性是否遵循“GUI 不复制算法、提供无头 CLI 导出 CSV/JSON 等结构化文本以支撑 AI 自动评估闭环”，是否遗漏了跨模块隐含依赖、删除/改动波及面（爆炸半径）或破坏性变更；3) 核心不变量、并发/数据一致性与故障边界风险。请按严重级别分组输出简洁的中文 Review 报告：[Blocker / 事实错误或主路径隐患]、[Important / 重要设计缺口或越界耦合]、[Edge-case / 极端临界条件]，并对每条建议标注**触发概率**与**修复引入的代码复杂度代价（低/中/高）**，便于架构师在严谨性与可维护性之间做权衡。"
  CMD+=("$PROMPT")
elif [[ "$CODE_REVIEW_MODE" -eq 1 ]]; then
  MODE="code-review"
  REPORT_FILE="${REPORT_DIR}/code-review-${TASK_SLUG}-${TIMESTAMP}.md"
  CMD=(codex exec -C "$WORKDIR" --color never --sandbox read-only --output-last-message "$REPORT_FILE")
  if [[ -n "$MODEL" ]]; then
    CMD+=(-m "$MODEL")
  fi
  if [[ -n "$EFFORT" ]]; then
    CMD+=(-c "model_reasoning_effort=\"$EFFORT\"")
  fi
  PROMPT="这是一次独立的**落地后只读代码审查（写审分离）**，请勿修改任何文件。你在未参与原编码推理过程的前提下担任严格审查者：请先阅读仓库中的 AGENTS.md（若存在）及任务/设计要求 ${TASK_FILE}，再依次核查 git status --short -uall（展开新增子目录内的全部未跟踪文件）、git diff HEAD（同时覆盖已暂存与未暂存改动；若仓库尚无首个提交无 HEAD，则直接审查全部暂存与未跟踪文件）以及状态为 ?? 的新增未跟踪文件内容（若工作区完全干净，仅在最近一次提交确系对应本任务时审查 git show，否则明确报告缺少可确认的改动基线）。请从严挑错并重点核查：1) 要求承诺的外部可观测行为、并发/异常边界是否真正兑现，测试是否为验证外部承诺的“行为评估”而非表面绿灯或绑死内部实现；2) 是否存在为通过测试而删改、放宽既有测试断言或验收标准的行为；3) 是否越出允许修改范围、破坏模块数据归属/跨边界契约（如在 GUI/表现层复制或混写核心算法逻辑），或混入超出 Non-Goals 的过度防御式冗余代码；4) 代码中是否藏有任务单未授权的高风险隐性假设（如来历不明的魔法数字、静默吞错、未评估影响面的删除）。请按 [Blocker / 必须返工]、[Important / 重要隐患或隐性 Gap]、[Minor / 可选优化] 分组输出简明中文审查报告，无问题项无需凑数。"
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
  PROMPT="请先阅读仓库中的 AGENTS.md（若存在），然后完整阅读任务单 ${TASK_FILE}。在动手修改代码前先核对代码库事实与边界契约，对未明说之处按两级处理：若仅为低回退代价的局部实现细节，请勿中断执行，自行采用简洁合理的默认方案并在最终汇报的 Unstated Decisions 中如实单列；若发现**阻塞级冲突或高危歧义**（任务单假设的文件/符号/调用链与真实代码库严重不符、兑现目标必须触碰禁改范围或违背 AGENTS.md 核心数据归属、或面临未授权的数据删除/公共契约破坏性分叉），**严禁盲猜硬改**——请保持工作区无本任务残留改动并立即停止实现，在最终汇报首行固定输出 [BLOCKED]，紧接着简明列出：1) 冲突或受阻的代码库事实证据（文件路径与行号）；2) 待拍板的具体问题与简要备选方案（不超过 2~3 项）。确认无阻塞后，严格按照任务单的目标、修改范围、约束与 Non-Goals（明确不做项，禁止对已排除的极端边界做过度防御式编程）完成代码落地，并亲自运行任务单中的全部验收命令（严禁为使测试通过而删改、放宽既有测试断言或验收标准；新增测试优先验证外部可观测行为；严禁执行 git add/commit/push）。正常完成后输出简洁清晰的中文汇报，必须包含：1) 修改/新增的文件清单；2) 运行的验收命令及实际结果；3) 任何未解决的问题或残余风险；4) 任务单未明确规定、你在实现中自行做出的假设与决定（Unstated Decisions，若无请写“无”）。"
  CMD+=("$PROMPT")
fi

echo "MODE=$MODE"
echo "WORKDIR=$WORKDIR"
echo "TASK_FILE=$TASK_FILE"
echo "REPORT_FILE=$REPORT_FILE"
if [[ -n "$EFFORT" ]]; then
  echo "EFFORT=$EFFORT"
fi
if [[ -n "$RESUME_ID" ]]; then
  echo "RESUME_ID=$RESUME_ID"
fi

STDERR_LOG="$(mktemp "${REPORT_DIR}/.stderr-${TIMESTAMP}.XXXXXX")"
cleanup() {
  rm -f "$STDERR_LOG"
}
trap cleanup EXIT

if [[ "$MODE" == "resume" ]]; then
  ((cd "$WORKDIR" && "${CMD[@]}") 3>&1 1>&2 2>&3 | tee "$STDERR_LOG") 3>&1 1>&2 2>&3
else
  ("${CMD[@]}" 3>&1 1>&2 2>&3 | tee "$STDERR_LOG") 3>&1 1>&2 2>&3
fi

SESSION_ID="$RESUME_ID"
if [[ -z "$SESSION_ID" && -f "$STDERR_LOG" ]]; then
  SESSION_ID="$(sed -n 's/^session id:[[:space:]]*\([0-9a-fA-F-]\+\).*$/\1/p' "$STDERR_LOG" | head -n 1)"
fi

CODEX_STATUS="OK"
if [[ ( "$MODE" == "exec" || "$MODE" == "resume" ) && -f "$REPORT_FILE" ]] && awk '
  /[^[:space:]]/ {
    seen = 1
    sub(/^[[:space:]]+/, "")
    blocked = ($0 ~ /^\[BLOCKED\]/ || $0 ~ /^\*\*\[BLOCKED\]\*\*/ || $0 ~ /^`\[BLOCKED\]`/)
    exit (blocked ? 0 : 1)
  }
  END { if (!seen) exit 1 }
' "$REPORT_FILE"; then
  CODEX_STATUS="BLOCKED"
fi

if [[ -n "$SESSION_ID" ]]; then
  echo "SESSION_ID=$SESSION_ID"
fi
echo "CODEX_STATUS=$CODEX_STATUS"
echo "CODEX_DONE=1"
echo "REPORT_FILE=$REPORT_FILE"
exit 0
}

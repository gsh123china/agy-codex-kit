#!/usr/bin/env bash
set -euo pipefail

# ─── ANSI Helpers (Standard 16-color palette, adapts to Tokyo Night & other themes) ─
R="\033[0m"
B="\033[1m"
D="\033[2m"

FG_RED="\033[31m"
FG_GREEN="\033[32m"
FG_YELLOW="\033[33m"
FG_BLUE="\033[34m"
FG_CYAN="\033[36m"
FG_WHITE="\033[37m"

FG_GRAY="\033[90m"
FG_BRIGHT_RED="\033[91m"
FG_BRIGHT_GREEN="\033[92m"
FG_BRIGHT_YELLOW="\033[93m"
FG_BRIGHT_BLUE="\033[94m"
FG_BRIGHT_MAGENTA="\033[95m"
FG_BRIGHT_CYAN="\033[96m"
FG_BRIGHT_WHITE="\033[97m"

# ─── Parse JSON from stdin in a single jq pass (handles empty/invalid stdin) ──
PARSED="$(
  jq -Rsr '
    ((fromjson? // {}) | if type == "object" then . else {} end) as $d |
    def cur_tokens:
      if ($d.context_window.current_usage | type) == "object" then
        (($d.context_window.current_usage.input_tokens // 0)
        + ($d.context_window.current_usage.output_tokens // 0)
        + ($d.context_window.current_usage.cache_creation_input_tokens // 0)
        + ($d.context_window.current_usage.cache_read_input_tokens // 0))
      else 0 end;
    def used_tokens:
      if (($d.context_window.context_window_size // 0) > 0) and (($d.context_window.used_percentage // 0) > 0) then
        ((($d.context_window.context_window_size * $d.context_window.used_percentage) / 100) | round)
      elif cur_tokens > 0 then
        cur_tokens
      else
        (($d.context_window.total_input_tokens // 0) + ($d.context_window.total_output_tokens // 0))
      end;
    [
      ($d.agent_state // "idle"),
      ($d.model.display_name // ""),
      ($d.context_window.used_percentage // 0),
      used_tokens,
      ($d.context_window.context_window_size // 0),
      ($d.vcs.branch // ""),
      ($d.vcs.dirty // false),
      ($d.sandbox.enabled // false),
      ($d.cycle_mode // ""),
      ($d.artifact_count // 0),
      (if ($d.subagents | type) == "array" then ([$d.subagents[] | select(.status == "running")] | length) else 0 end),
      ($d.task_count // 0),
      ($d.terminal_width // 100),
      (($d.workspace.current_dir // $d.cwd // "") | split("/") | last // ""),
      "END"
    ] | map(tostring | gsub("[\r\n\u001f]"; " ")) | join("\u001f")
  ' 2>/dev/null || printf 'idle\037\0370\0370\0370\037\037false\037false\037\0370\0370\0370\037100\037\037END'
)"

IFS=$'\x1f' read -r STATE MODEL USED_PCT USED_TOKENS WIN_SIZE VCS_BRANCH VCS_DIRTY SANDBOX CYCLE_MODE ARTIFACTS SUBAGENTS BG_TASKS COLS CWD_NAME _END <<< "$PARSED" || true

# ─── Format Helpers ──────────────────────────────────────────────────────────
fmt_tokens() {
  local n="${1:-0}"
  n="${n%.*}"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if (( n >= 1000000 )); then
    LC_NUMERIC=C awk -v v="$n" 'BEGIN { printf "%.2fM", v / 1000000 }' | sed 's/0M$/M/; s/\.0M$/M/'
  elif (( n >= 100000 )); then
    LC_NUMERIC=C awk -v v="$n" 'BEGIN { printf "%.0fk", v / 1000 }'
  elif (( n >= 1000 )); then
    LC_NUMERIC=C awk -v v="$n" 'BEGIN { printf "%.1fk", v / 1000 }' | sed 's/\.0k$/k/'
  else
    printf "%s" "$n"
  fi
}

PCT_FMT="$(LC_NUMERIC=C printf "%.1f" "$USED_PCT")"
PCT_INT="${USED_PCT%.*}"
PCT_INT="${PCT_INT:-0}"
[[ "$PCT_INT" =~ ^[0-9]+$ ]] || PCT_INT=0
(( PCT_INT > 100 )) && PCT_INT=100

USED_FMT="$(fmt_tokens "$USED_TOKENS")"
if [[ "$WIN_SIZE" =~ ^[0-9]+$ ]] && (( WIN_SIZE > 0 )); then
  WIN_FMT="$(fmt_tokens "$WIN_SIZE")"
  CTX_SIZE="${USED_FMT}/${WIN_FMT}"
else
  CTX_SIZE="${USED_FMT}"
fi

# ─── Context Usage (Numeric Only, Color-Coded by Threshold) ──────────────────
if (( PCT_INT >= 85 )); then
  CTX_NUM_COLOR="${FG_BRIGHT_RED}${B}"
elif (( PCT_INT >= 60 )); then
  CTX_NUM_COLOR="${FG_BRIGHT_YELLOW}${B}"
else
  CTX_NUM_COLOR="${FG_BRIGHT_WHITE}${B}"
fi

if [[ "$WIN_SIZE" =~ ^[0-9]+$ ]] && (( WIN_SIZE > 0 )); then
  CTX="${FG_GRAY}ctx ${CTX_NUM_COLOR}${CTX_SIZE}${R} ${FG_GRAY}(${PCT_FMT}%)${R}"
else
  CTX="${FG_GRAY}ctx ${CTX_NUM_COLOR}${CTX_SIZE}${R}"
fi

# ─── State Indicator ─────────────────────────────────────────────────────────
case "$STATE" in
  idle)          S="${FG_BRIGHT_GREEN}${B}● READY${R}" ;;
  working)       S="${FG_BRIGHT_CYAN}${B}⚙ WORK${R}" ;;
  tool_use)      S="${FG_BRIGHT_MAGENTA}${B}◆ TOOL${R}" ;;
  reviewing)     S="${FG_BRIGHT_YELLOW}${B}◈ REVIEW${R}" ;;
  error)         S="${FG_BRIGHT_RED}${B}✕ ERROR${R}" ;;
  *)             S="${FG_WHITE}${B}◌ ${STATE^^}${R}" ;;
esac

# ─── Metadata Segments ───────────────────────────────────────────────────────
SEP="${FG_GRAY} │ ${R}"
DOT="${FG_GRAY} · ${R}"

M=""
[[ -n "$MODEL" ]] && M="${FG_GRAY} ╱ ${FG_BRIGHT_MAGENTA}${MODEL}${R}"

LOC=""
if [[ -n "$VCS_BRANCH" ]]; then
  if [[ "$VCS_DIRTY" == "true" ]]; then
    LOC="${FG_GRAY} ╱ ${FG_BRIGHT_BLUE}${VCS_BRANCH}${FG_BRIGHT_YELLOW}*${R}"
  else
    LOC="${FG_GRAY} ╱ ${FG_BRIGHT_BLUE}${VCS_BRANCH}${R}"
  fi
elif [[ -n "$CWD_NAME" ]]; then
  LOC="${FG_GRAY} ╱ ${FG_BLUE}${CWD_NAME}${R}"
fi

EXTRAS=""
if [[ -n "$CYCLE_MODE" ]]; then
  EXTRAS+="${DOT}${FG_YELLOW}${CYCLE_MODE}${R}"
fi
if [[ "$SUBAGENTS" =~ ^[0-9]+$ ]] && (( SUBAGENTS > 0 )); then
  EXTRAS+="${DOT}${FG_GRAY}agents ${FG_BRIGHT_WHITE}${B}${SUBAGENTS}${R}"
fi
if [[ "$BG_TASKS" =~ ^[0-9]+$ ]] && (( BG_TASKS > 0 )); then
  EXTRAS+="${DOT}${FG_GRAY}tasks ${FG_BRIGHT_WHITE}${B}${BG_TASKS}${R}"
fi
if [[ "$ARTIFACTS" =~ ^[0-9]+$ ]] && (( ARTIFACTS > 0 )); then
  EXTRAS+="${DOT}${FG_GRAY}art ${FG_BRIGHT_WHITE}${ARTIFACTS}${R}"
fi
if [[ "$SANDBOX" == "true" ]]; then
  EXTRAS+="${DOT}${FG_GRAY}sbx ${FG_GREEN}on${R}"
else
  EXTRAS+="${DOT}${FG_GRAY}${D}sbx off${R}"
fi

# ─── Responsive Output ───────────────────────────────────────────────────────
[[ "$COLS" =~ ^[0-9]+$ ]] || COLS=100

if (( COLS >= 115 )); then
  printf "%b\n" "${S}${M}${LOC}${SEP}${CTX}${EXTRAS}"
elif (( COLS >= 75 )); then
  printf "%b\n" "${FG_GRAY}╭─${R} ${S}${M}${LOC}"
  printf "%b\n" "${FG_GRAY}╰─${R} ${CTX}${EXTRAS}"
else
  printf "%b\n" "${S}${M}"
  printf "%b\n" "${CTX}"
fi

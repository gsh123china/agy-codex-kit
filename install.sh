#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Deploy Antigravity + Codex global rules and skills via symlinks so this Git
repository stays the single source of truth.

Options:
  --uninstall   Remove symlinks that point into this repository
  -h, --help    Show this help

Environment:
  GEMINI_HOME   Override target Antigravity config root (default: ~/.gemini)
EOF
}

UNINSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GEMINI_HOME="${GEMINI_HOME:-$HOME/.gemini}"
SKILLS_TARGET_DIR="$GEMINI_HOME/config/skills"
CLI_HOME="$GEMINI_HOME/antigravity-cli"
BACKUP_ROOT="$GEMINI_HOME/backups/agy-codex-kit-$(date +%Y%m%d-%H%M%S)"
BACKUP_USED=0

backup_existing() {
  local target="$1"
  local rel_name="$2"
  local dest="$BACKUP_ROOT/$rel_name"
  mkdir -p "$(dirname "$dest")"
  mv "$target" "$dest"
  BACKUP_USED=1
  echo "[backup] $target -> $dest"
}

link_item() {
  local src="$1"
  local target="$2"
  local backup_rel="$3"

  mkdir -p "$(dirname "$target")"

  local src_real
  src_real="$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")"

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink -f "$target" 2>/dev/null || true)"
    if [[ -n "$current" && "$current" == "$src_real" ]]; then
      echo "[ok]     $target -> $src (already linked)"
      return 0
    fi
    backup_existing "$target" "$backup_rel"
  elif [[ -e "$target" ]]; then
    backup_existing "$target" "$backup_rel"
  fi

  ln -s "$src" "$target"
  echo "[link]   $target -> $src"
}

unlink_if_ours() {
  local src="$1"
  local target="$2"
  local src_real
  src_real="$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")"

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink -f "$target" 2>/dev/null || true)"
    if [[ -n "$current" && "$current" == "$src_real" ]]; then
      rm "$target"
      echo "[unlink] $target"
      return 0
    fi
    echo "[skip]   $target points elsewhere ($current)"
  elif [[ -e "$target" ]]; then
    echo "[skip]   $target is not a symlink"
  else
    echo "[skip]   $target does not exist"
  fi
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  echo "Uninstalling agy-codex-kit symlinks from $GEMINI_HOME ..."
  unlink_if_ours "$REPO_DIR/antigravity/GEMINI.md" "$GEMINI_HOME/GEMINI.md"
  unlink_if_ours "$REPO_DIR/antigravity/statusline.sh" "$CLI_HOME/statusline.sh"
  for skill_dir in "$REPO_DIR"/antigravity/skills/*; do
    [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]] || continue
    skill_name="$(basename "$skill_dir")"
    unlink_if_ours "$skill_dir" "$SKILLS_TARGET_DIR/$skill_name"
  done
  if [[ -d "$SKILLS_TARGET_DIR" ]]; then
    for link_path in "$SKILLS_TARGET_DIR"/*; do
      [[ -L "$link_path" ]] || continue
      raw_dest="$(readlink "$link_path" 2>/dev/null || true)"
      [[ -n "$raw_dest" ]] || continue
      if [[ "$raw_dest" != /* ]]; then
        raw_dest="$(dirname "$link_path")/$raw_dest"
      fi
      norm_dest="$(realpath -m "$raw_dest" 2>/dev/null || printf '%s' "$raw_dest")"
      if [[ "$norm_dest" == "$REPO_DIR/antigravity/skills/"* ]]; then
        rm "$link_path"
        echo "[unlink] $link_path (stale repo skill link)"
      fi
    done
  fi
  echo "Done."
  exit 0
fi

echo "Installing agy-codex-kit from $REPO_DIR -> $GEMINI_HOME ..."

# Ensure helper scripts are executable (only chmod when missing +x so read-only mounts work)
[[ -f "$REPO_DIR/antigravity/statusline.sh" && ! -x "$REPO_DIR/antigravity/statusline.sh" ]] && chmod +x "$REPO_DIR/antigravity/statusline.sh"
for script in "$REPO_DIR"/antigravity/skills/*/scripts/*.sh; do
  [[ -f "$script" && ! -x "$script" ]] && chmod +x "$script"
done

link_item "$REPO_DIR/antigravity/GEMINI.md" "$GEMINI_HOME/GEMINI.md" "GEMINI.md"
if [[ -f "$REPO_DIR/antigravity/statusline.sh" ]]; then
  link_item "$REPO_DIR/antigravity/statusline.sh" "$CLI_HOME/statusline.sh" "antigravity-cli/statusline.sh"
fi

for skill_dir in "$REPO_DIR"/antigravity/skills/*; do
  [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]] || continue
  skill_name="$(basename "$skill_dir")"
  link_item "$skill_dir" "$SKILLS_TARGET_DIR/$skill_name" "skills/$skill_name"
done

echo ""
echo "=== Environment Check ==="
FALLBACK_DIRS=("$HOME/.local/share/mise/shims" "$HOME/.local/bin" "$HOME/.bun/bin")
for bin in agy codex git jq; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "[ok]      $bin: $(command -v "$bin")"
  else
    found_alt=""
    for d in "${FALLBACK_DIRS[@]}"; do
      if [[ -x "$d/$bin" ]]; then
        found_alt="$d/$bin"
        break
      fi
    done
    if [[ -n "$found_alt" ]]; then
      echo "[ok]      $bin: $found_alt (found via user bin fallback)"
    else
      echo "[missing] $bin not found in PATH"
    fi
  fi
done

if [[ "$BACKUP_USED" -eq 1 ]]; then
  echo ""
  echo "Previous files were backed up outside scanned skill dirs to:"
  echo "  $BACKUP_ROOT"
fi

cat <<'EOF'

=== Next Steps (Machine-Local, Not Managed by Git) ===
1. Authenticate Codex CLI if not logged in:
     codex login
2. Configure Antigravity permission preset for this machine:
   - Isolated VM / unattended long tasks: run `/config` -> Turbo, or launch `agy --dangerously-skip-permissions`
   - Main workstation: keep Default/Auto and allow `run-codex.sh` / `codex exec` via `/permissions` (see examples/antigravity.settings.json.example)
3. Start a new `agy` session so the global GEMINI.md and skills take effect.
EOF

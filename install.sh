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

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMINI_HOME="${GEMINI_HOME:-$HOME/.gemini}"
SKILLS_TARGET_DIR="$GEMINI_HOME/config/skills"
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

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink -f "$target" 2>/dev/null || true)"
    if [[ "$current" == "$src" ]]; then
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

  if [[ -L "$target" ]]; then
    local current
    current="$(readlink -f "$target" 2>/dev/null || true)"
    if [[ "$current" == "$src" ]]; then
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
  for skill_dir in "$REPO_DIR"/antigravity/skills/*; do
    [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]] || continue
    skill_name="$(basename "$skill_dir")"
    unlink_if_ours "$skill_dir" "$SKILLS_TARGET_DIR/$skill_name"
  done
  echo "Done."
  exit 0
fi

echo "Installing agy-codex-kit from $REPO_DIR -> $GEMINI_HOME ..."

# Ensure helper scripts inside skills are executable
for script in "$REPO_DIR"/antigravity/skills/*/scripts/*.sh; do
  [[ -f "$script" ]] && chmod +x "$script"
done

link_item "$REPO_DIR/antigravity/GEMINI.md" "$GEMINI_HOME/GEMINI.md" "GEMINI.md"

for skill_dir in "$REPO_DIR"/antigravity/skills/*; do
  [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]] || continue
  skill_name="$(basename "$skill_dir")"
  link_item "$skill_dir" "$SKILLS_TARGET_DIR/$skill_name" "skills/$skill_name"
done

echo ""
echo "=== Environment Check ==="
for bin in agy codex git; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "[ok]      $bin: $(command -v "$bin")"
  else
    echo "[missing] $bin not found in PATH"
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
   - Main workstation: keep Default/Auto and allow `command(codex exec)` via `/permissions`
3. Start a new `agy` session so the global GEMINI.md and skills take effect.
EOF

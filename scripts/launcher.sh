#!/bin/bash

# --- Nexus-Shell Launcher ---
# A VSCode-style terminal IDE using TMUX
# https://github.com/samir-alsayad/nexus-shell

set -e

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Priority: Existing env > Home config > Shared repo
if [[ -z "$NEXUS_CONFIG" ]]; then
    if [[ -d "$HOME/.config/nexus-shell" ]]; then
        export NEXUS_CONFIG="$HOME/.config/nexus-shell"
    else
        export NEXUS_CONFIG="$(dirname "$SCRIPT_DIR")"
    fi
fi
export NEXUS_STATE="/tmp/nexus_$(whoami)"
export NEXUS_SCRIPTS="$SCRIPT_DIR"
export NEXUS_BIN="$HOME/.nexus-shell/bin"

# Load tools configuration
TOOLS_CONF="$HOME/.config/nexus-shell/tools.conf"
if [[ -f "$TOOLS_CONF" ]]; then
    source "$TOOLS_CONF"
fi

# Tool defaults (use system PATH if not configured)
NEXUS_EDITOR="${NEXUS_EDITOR:-nvim}"
NEXUS_FILES="${NEXUS_FILES:-yazi}"
NEXUS_CHAT="${NEXUS_CHAT:-}"
NEXUS_RENDER="${NEXUS_RENDER:-glow}"
NEXUS_PX_UI="${NEXUS_PX_UI:-tmux}"

# Check if using isolated/bundled tools (downloaded by installer)
# If so, use nexus-shell's own config directory for tool configs
NEXUS_ISOLATED="${NEXUS_ISOLATED:-false}"
if [[ "$NEXUS_ISOLATED" == "true" ]]; then
    export XDG_CONFIG_HOME="$HOME/.config/nexus-shell/tool-configs"
    export VIMINIT="source $XDG_CONFIG_HOME/nvim/init.lua"
    # Ensure nvim finds its isolated runtime
    export VIMRUNTIME="$HOME/.nexus-shell/share/nvim/runtime"
fi

# Verify required tools exist
check_tool() {
    local tool="$1"
    local name="$2"
    if [[ -n "$tool" ]] && ! command -v "$tool" &>/dev/null && [[ ! -x "$tool" ]]; then
        echo "[!] Warning: $name ($tool) not found"
        return 1
    fi
    return 0
}

check_tool "$NEXUS_EDITOR" "Editor" || { echo "    Install nvim or configure NEXUS_EDITOR"; exit 1; }
check_tool "$NEXUS_FILES" "File Navigator" || echo "    File navigator disabled"

# Project context
PROJECT_ROOT="${1:-$(pwd)}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_ROOT")"
export NEXUS_PROJECT="$PROJECT_NAME"

# Session and pipe names
SESSION_ID="nexus_$PROJECT_NAME"
NVIM_PIPE="$NEXUS_STATE/pipes/nvim_${PROJECT_NAME}.pipe"
export NEXUS_PIPE="$NVIM_PIPE"

# Ensure state directories exist
mkdir -p "$NEXUS_STATE/pipes"

# Wrapper script for indestructible panes
WRAPPER="$NEXUS_SCRIPTS/pane_wrapper.sh"

echo "[*] Nexus-Shell: Initializing..."
echo "    Project: $PROJECT_NAME"
echo "    Root:    $PROJECT_ROOT"

# Check if session exists
if tmux has-session -t "$SESSION_ID" 2>/dev/null; then
    echo "[*] Session '$SESSION_ID' already exists."
    read -p "    Kill and restart? (y/N): " confirm
    if [[ $confirm == [yY] ]]; then
        tmux kill-session -t "$SESSION_ID"
    else
        echo "[*] Attaching to existing session..."
        exec tmux attach-session -t "$SESSION_ID"
    fi
fi

echo "[*] Constructing layout..."

# Determine layout based on what's available
HAS_CHAT=false
[[ -n "$NEXUS_CHAT" ]] && command -v "$NEXUS_CHAT" &>/dev/null && HAS_CHAT=true

HAS_FILES=false
command -v "$NEXUS_FILES" &>/dev/null && HAS_FILES=true

# Calculate pane indices
if [[ "$HAS_FILES" == "true" ]]; then
    TREE_PANE_IDX=0
    PARALLAX_PANE_IDX=1
    EDITOR_PANE_IDX=2
    TERM_PANE_IDX=3
else
    TREE_PANE_IDX=-1
    PARALLAX_PANE_IDX=0
    EDITOR_PANE_IDX=1
    TERM_PANE_IDX=2
fi
CHAT_PANE_IDX=-1
[[ "$HAS_CHAT" == "true" ]] && CHAT_PANE_IDX=$((TERM_PANE_IDX + 1))

# Environment flags for all panes (passed directly to each pane)
PANE_ENV="-e NEXUS_CONFIG=$NEXUS_CONFIG -e NEXUS_PROJECT=$PROJECT_NAME -e NEXUS_PIPE=$NVIM_PIPE -e NEXUS_STATE=$NEXUS_STATE -e NEXUS_EDITOR=$NEXUS_EDITOR -e NEXUS_FILES=$NEXUS_FILES -e NEXUS_CHAT=$NEXUS_CHAT -e NEXUS_RENDER=$NEXUS_RENDER -e NEXUS_GIT=$NEXUS_GIT -e NEXUS_PX_UI=$NEXUS_PX_UI -e NEXUS_BIN=$NEXUS_BIN -e PX_NEXUS_MODE=1 -e PX_NEXUS_SESSION=$SESSION_ID -e PX_NEXUS_TREE_PANE=$TREE_PANE_IDX -e PX_NEXUS_PARALLAX_PANE=$PARALLAX_PANE_IDX -e PX_NEXUS_EDITOR_PANE=$EDITOR_PANE_IDX -e PX_NEXUS_TERMINAL_PANE=$TERM_PANE_IDX -e PX_NEXUS_CHAT_PANE=$CHAT_PANE_IDX -e VIMRUNTIME=$VIMRUNTIME -e XDG_CONFIG_HOME=$XDG_CONFIG_HOME -e YAZI_CONFIG_HOME=$HOME/.config/nexus-shell/tool-configs/yazi"

# TMUX config path

TMUX_CONF="$NEXUS_CONFIG/config/tmux/nexus.conf"
[[ ! -f "$TMUX_CONF" ]] && TMUX_CONF="$HOME/.config/nexus-shell/tmux/nexus.conf"

# Build editor command (only nvim/neovim supports --listen)
EDITOR_CMD="$NEXUS_EDITOR"
if [[ "$NEXUS_EDITOR" == *"nvim"* || "$NEXUS_EDITOR" == *"neovim"* ]]; then
    EDITOR_CMD="$NEXUS_EDITOR --listen $NVIM_PIPE"
fi

# Build Parallax Dashboard command
PARALLAX_BIN="$HOME/.parallax/bin/parallax"
PARALLAX_CMD="PX_NEXUS_MODE=1 PX_NEXUS_SESSION=$SESSION_ID PX_NEXUS_TERMINAL_PANE=$TERM_PANE_IDX $PARALLAX_BIN --nexus"

# 1. Start with the EDITOR pane (center)
tmux -f "$TMUX_CONF" new-session -d -s "$SESSION_ID" -c "$PROJECT_ROOT" \
    $PANE_ENV \
    "$WRAPPER $EDITOR_CMD"

# Export critical environment to the session (so sub-processes can find them)
tmux set-environment -t "$SESSION_ID" NEXUS_CONFIG "$NEXUS_CONFIG"
tmux set-environment -t "$SESSION_ID" NEXUS_PROJECT "$PROJECT_NAME"
tmux set-environment -t "$SESSION_ID" NEXUS_PIPE "$NVIM_PIPE"
tmux set-environment -t "$SESSION_ID" NEXUS_STATE "$NEXUS_STATE"
tmux set-environment -t "$SESSION_ID" NEXUS_EDITOR "$NEXUS_EDITOR"
tmux set-environment -t "$SESSION_ID" NEXUS_FILES "$NEXUS_FILES"
tmux set-environment -t "$SESSION_ID" PX_NEXUS_MODE 1
tmux set-environment -t "$SESSION_ID" PX_NEXUS_SESSION "$SESSION_ID"
tmux set-environment -t "$SESSION_ID" PX_NEXUS_TREE_PANE "$TREE_PANE_IDX"
tmux set-environment -t "$SESSION_ID" PX_NEXUS_PARALLAX_PANE "$PARALLAX_PANE_IDX"
tmux set-environment -t "$SESSION_ID" PX_NEXUS_EDITOR_PANE "$EDITOR_PANE_IDX"
tmux set-environment -t "$SESSION_ID" PX_NEXUS_TERMINAL_PANE "$TERM_PANE_IDX"
tmux set-environment -t "$SESSION_ID" PX_NEXUS_CHAT_PANE "$CHAT_PANE_IDX"
tmux set-environment -t "$SESSION_ID" XDG_CONFIG_HOME "$XDG_CONFIG_HOME"
tmux set-environment -t "$SESSION_ID" YAZI_CONFIG_HOME "$HOME/.config/nexus-shell/tool-configs/yazi"

tmux rename-window -t "$SESSION_ID:0" "workspace"

# 2. CHAT pane (far right, 25%) - only if configured
if [[ "$HAS_CHAT" == "true" ]]; then
    tmux split-window -h -l 25% -t "$SESSION_ID:0.0" -c "$PROJECT_ROOT" \
        $PANE_ENV \
        "$WRAPPER $NEXUS_CHAT"
fi

# 3. TREE pane (far left, 15%) - only if available
if [[ "$HAS_FILES" == "true" ]]; then
    tmux split-window -h -b -l 15% -t "$SESSION_ID:0.0" -c "$PROJECT_ROOT" \
        $PANE_ENV \
        "$WRAPPER $NEXUS_FILES '$PROJECT_ROOT'"
fi

# 4. PARALLAX pane (center top, 20%)
# Find the editor pane (it's always pane 0 or 1 depending on layout)
EDITOR_PANE="0"
[[ "$HAS_FILES" == "true" ]] && EDITOR_PANE="1"

tmux split-window -v -b -l 20% -t "$SESSION_ID:0.${EDITOR_PANE}" -c "$PROJECT_ROOT" \
    $PANE_ENV \
    "$WRAPPER $PARALLAX_CMD"

# 5. TERMINAL pane (center bottom, 30%)
# After split-v -b, the editor pane index increases by 1
EDITOR_PANE_NEW=$((EDITOR_PANE + 1))

tmux split-window -v -l 30% -t "$SESSION_ID:0.${EDITOR_PANE_NEW}" -c "$PROJECT_ROOT" \
    $PANE_ENV \
    "$WRAPPER /bin/zsh -i"

# Name panes for scripting
[[ "$HAS_FILES" == "true" ]] && tmux select-pane -t "$SESSION_ID:0.${TREE_PANE_IDX}" -T "tree"
tmux select-pane -t "$SESSION_ID:0.${PARALLAX_PANE_IDX}" -T "parallax"
tmux select-pane -t "$SESSION_ID:0.${EDITOR_PANE_IDX}" -T "editor"
tmux select-pane -t "$SESSION_ID:0.${TERM_PANE_IDX}" -T "terminal"
[[ "$HAS_CHAT" == "true" ]] && tmux select-pane -t "$SESSION_ID:0.${CHAT_PANE_IDX}" -T "chat"

# Focus terminal pane (for immediate shell use)
# Using index-based selection to avoid race condition with pane titles
tmux select-pane -t "$SESSION_ID:0.${PARALLAX_PANE_IDX}" -d 
tmux select-pane -t "$SESSION_ID:0.${TERM_PANE_IDX}"

echo "[*] Ready. Attaching..."

# Attach to session
exec tmux attach-session -t "$SESSION_ID"

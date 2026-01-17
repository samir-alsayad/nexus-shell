#!/bin/bash

# --- Nexus-Shell Launcher ---
# A VSCode-style terminal IDE using TMUX
# https://github.com/samir-alsayad/nexus-shell

set -e

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NEXUS_CONFIG="${NEXUS_CONFIG:-$(dirname "$SCRIPT_DIR")}"
export NEXUS_STATE="/tmp/nexus_$(whoami)"
export NEXUS_SCRIPTS="$SCRIPT_DIR"

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

# Check if using isolated/bundled tools (downloaded by installer)
# If so, use nexus-shell's own config directory for tool configs
NEXUS_ISOLATED="${NEXUS_ISOLATED:-false}"
if [[ "$NEXUS_ISOLATED" == "true" ]]; then
    export XDG_CONFIG_HOME="$HOME/.config/nexus-shell/tool-configs"
    export VIMINIT="source $XDG_CONFIG_HOME/nvim/init.lua"
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

# Environment flags for all panes (passed directly to each pane)
PANE_ENV="-e NEXUS_CONFIG=$NEXUS_CONFIG -e NEXUS_PROJECT=$PROJECT_NAME -e NEXUS_PIPE=$NVIM_PIPE -e NEXUS_STATE=$NEXUS_STATE -e NEXUS_EDITOR=$NEXUS_EDITOR -e NEXUS_FILES=$NEXUS_FILES -e NEXUS_CHAT=$NEXUS_CHAT -e NEXUS_RENDER=$NEXUS_RENDER"

# Determine layout based on what's available
HAS_CHAT=false
[[ -n "$NEXUS_CHAT" ]] && command -v "$NEXUS_CHAT" &>/dev/null && HAS_CHAT=true

HAS_FILES=false
command -v "$NEXUS_FILES" &>/dev/null && HAS_FILES=true

# TMUX config path
TMUX_CONF="$NEXUS_CONFIG/config/tmux/nexus.conf"
[[ ! -f "$TMUX_CONF" ]] && TMUX_CONF="$HOME/.config/nexus-shell/tmux/nexus.conf"

# Build editor command (only nvim/neovim supports --listen)
EDITOR_CMD="$NEXUS_EDITOR"
if [[ "$NEXUS_EDITOR" == *"nvim"* || "$NEXUS_EDITOR" == *"neovim"* ]]; then
    EDITOR_CMD="$NEXUS_EDITOR --listen $NVIM_PIPE"
fi

# 1. Start with the EDITOR pane (center)
tmux -f "$TMUX_CONF" new-session -d -s "$SESSION_ID" -c "$PROJECT_ROOT" \
    $PANE_ENV \
    "$WRAPPER $EDITOR_CMD"
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

# 4. TERMINAL pane (center bottom, 30%)
# Find the editor pane (it's always pane 0 or 1 depending on layout)
EDITOR_PANE="0"
[[ "$HAS_FILES" == "true" ]] && EDITOR_PANE="1"

tmux split-window -v -l 30% -t "$SESSION_ID:0.${EDITOR_PANE}" -c "$PROJECT_ROOT" \
    $PANE_ENV \
    "$WRAPPER /bin/zsh -i"

# Name panes for scripting (adjust based on layout)
PANE_IDX=0
if [[ "$HAS_FILES" == "true" ]]; then
    tmux select-pane -t "$SESSION_ID:0.${PANE_IDX}" -T "tree"
    ((PANE_IDX++))
fi
tmux select-pane -t "$SESSION_ID:0.${PANE_IDX}" -T "editor"
((PANE_IDX++))
tmux select-pane -t "$SESSION_ID:0.${PANE_IDX}" -T "terminal"
((PANE_IDX++))
if [[ "$HAS_CHAT" == "true" ]]; then
    tmux select-pane -t "$SESSION_ID:0.${PANE_IDX}" -T "chat"
fi

# Focus editor pane
[[ "$HAS_FILES" == "true" ]] && tmux select-pane -t "$SESSION_ID:0.1" || tmux select-pane -t "$SESSION_ID:0.0"

echo "[*] Ready. Attaching..."

# Attach to session
exec tmux attach-session -t "$SESSION_ID"

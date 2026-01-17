#!/bin/bash

# --- Nexus Yazi-to-Editor Bridge ---
# Opens selected file from Yazi directly in the editor pane (no prompts)

FILE="$1"
[[ -z "$FILE" ]] && exit 0

NEXUS_CONFIG="${NEXUS_CONFIG:-$HOME/.config/nexus-shell}"
NEXUS_STATE="${NEXUS_STATE:-/tmp/nexus_$(whoami)}"
NEXUS_SCRIPTS="$NEXUS_CONFIG/scripts"

# Load tools config
TOOLS_CONF="$NEXUS_CONFIG/tools.conf"
[[ -f "$TOOLS_CONF" ]] && source "$TOOLS_CONF"

NEXUS_EDITOR="${NEXUS_EDITOR:-nvim}"

# Resolve to absolute path
ABS_FILE=$(realpath "$FILE" 2>/dev/null || echo "$FILE")

SESSION_NAME=$(tmux display-message -p '#S')
PROJECT_NAME=${SESSION_NAME#nexus_}
NVIM_PIPE="${NEXUS_PIPE:-$NEXUS_STATE/pipes/nvim_${PROJECT_NAME}.pipe}"
LAST_FILE="$NEXUS_STATE/last_path"
MODE_FILE="$NEXUS_STATE/editor_mode"
WRAPPER="$NEXUS_SCRIPTS/pane_wrapper.sh"

# Update state
mkdir -p "$NEXUS_STATE/pipes"
echo "$ABS_FILE" > "$LAST_FILE"

# Find editor pane
EDITOR_PANE=$(tmux list-panes -F "#{pane_id} #{pane_title}" | grep -E "editor|render" | head -1 | awk '{print $1}')
[[ -z "$EDITOR_PANE" ]] && EDITOR_PANE="%1"

# Check current mode
CURRENT_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "editor")

if [[ "$CURRENT_MODE" == "render" ]]; then
    # In render mode - just update last_path, render daemon will pick it up
    # (file will be previewed automatically)
    :
else
    # In editor mode - open in nvim
    if [[ -S "$NVIM_PIPE" ]] && command -v nvim &>/dev/null; then
        # Nvim is running - send file via RPC
        nvim --server "$NVIM_PIPE" --remote-send "<Esc>:e $ABS_FILE<CR>"
    else
        # Start editor with the file
        if [[ "$NEXUS_EDITOR" == *"nvim"* ]]; then
            tmux respawn-pane -k -t "$EDITOR_PANE" "$WRAPPER $NEXUS_EDITOR --listen '$NVIM_PIPE' '$ABS_FILE'"
        else
            tmux respawn-pane -k -t "$EDITOR_PANE" "$WRAPPER $NEXUS_EDITOR '$ABS_FILE'"
        fi
        tmux select-pane -t "$EDITOR_PANE" -T "editor"
        echo "editor" > "$MODE_FILE"
    fi
    
    # Focus editor pane
    tmux select-pane -t "$EDITOR_PANE"
fi

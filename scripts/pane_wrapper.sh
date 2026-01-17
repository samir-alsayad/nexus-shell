#!/bin/bash

# --- Nexus Pane Wrapper ---
# Indestructible viewports with FZF tool switching
# When a tool exits, shows a menu to choose the next tool

COMMAND="$@"
NEXUS_CONFIG="${NEXUS_CONFIG:-$HOME/.config/nexus-shell}"
NEXUS_SCRIPTS="${NEXUS_SCRIPTS:-$NEXUS_CONFIG/scripts}"
NEXUS_STATE="${NEXUS_STATE:-/tmp/nexus_$(whoami)}"
PROJECT_NAME="${NEXUS_PROJECT:-$(basename $(pwd))}"
NVIM_PIPE="${NEXUS_PIPE:-$NEXUS_STATE/pipes/nvim_${PROJECT_NAME}.pipe}"

# Load tools config
[[ -f "$NEXUS_CONFIG/tools.conf" ]] && source "$NEXUS_CONFIG/tools.conf"
[[ -f "$HOME/.config/nexus-shell/tools.conf" ]] && source "$HOME/.config/nexus-shell/tools.conf"

# Tool defaults
NEXUS_EDITOR="${NEXUS_EDITOR:-nvim}"
NEXUS_FILES="${NEXUS_FILES:-yazi}"
NEXUS_CHAT="${NEXUS_CHAT:-}"
NEXUS_RENDER="${NEXUS_RENDER:-glow}"

# Trap Ctrl-C so it doesn't kill the wrapper
trap ":" SIGINT

run_tool() {
    if [[ -z "$COMMAND" ]]; then
        return 1
    fi
    # No clear here - let the tool handle its own display
    eval "$COMMAND"
    local exit_code=$?
    if [[ $exit_code -ne 0 && $exit_code -ne 130 ]]; then
        echo -e "\n\033[1;31m[!] Tool exited with code $exit_code\033[0m"
        echo "    Command: $COMMAND"
        echo "    Press Enter to return to Hub..."
        read
    fi
    return $exit_code
}

show_hub() {
    clear
    echo -e "\033[1;36m[ NEXUS PANE HUB ]\033[0m"
    echo "──────────────────────────────"
    echo "Project: $PROJECT_NAME"
    echo "Path:    $(pwd)"
    echo ""
    
    # Build menu dynamically based on available tools
    local menu_items=""
    menu_items+="editor|Editor ($NEXUS_EDITOR)\n"
    
    if command -v "$NEXUS_RENDER" &>/dev/null || [[ -x "$NEXUS_RENDER" ]]; then
        menu_items+="render|Render View ($NEXUS_RENDER)\n"
    fi
    
    menu_items+="shell|Terminal (Zsh)\n"
    
    if command -v "$NEXUS_FILES" &>/dev/null || [[ -x "$NEXUS_FILES" ]]; then
        menu_items+="files|File Navigator ($NEXUS_FILES)\n"
    fi
    
    if [[ -n "$NEXUS_CHAT" ]] && { command -v "$NEXUS_CHAT" &>/dev/null || [[ -x "$NEXUS_CHAT" ]]; }; then
        menu_items+="chat|AI Chat ($NEXUS_CHAT)\n"
    fi
    
    if command -v lazygit &>/dev/null; then
        menu_items+="git|Git Dashboard (Lazygit)\n"
    fi
    
    menu_items+="restart|RESTART STATION\n"
    menu_items+="exit|EXIT STATION"
    
    # FZF menu
    local selection
    selection=$(echo -e "$menu_items" \
        | fzf --delimiter='|' --with-nth=2 \
              --header="Choose Tool (Enter to select)" \
              --reverse --height=50% --border \
              --color="fg:cyan,bg:black,hl:magenta,fg+:white,bg+:#1a1a2e,hl+:magenta,info:yellow,prompt:cyan,pointer:magenta,marker:magenta,spinner:cyan,header:cyan,border:cyan")
    
    # Extract key (before the pipe)
    local key="${selection%%|*}"
    
    case "$key" in
        "editor")
            COMMAND="$NEXUS_EDITOR --listen $NVIM_PIPE"
            tmux select-pane -T "editor"
            ;;
        "render")
            COMMAND="$NEXUS_SCRIPTS/render_daemon.sh"
            tmux select-pane -T "render"
            ;;
        "shell")
            COMMAND="/bin/zsh -i"
            tmux select-pane -T "terminal"
            ;;
        "files")
            COMMAND="$NEXUS_FILES"
            tmux select-pane -T "tree"
            ;;
        "chat")
            COMMAND="$NEXUS_CHAT"
            tmux select-pane -T "chat"
            ;;
        "git")
            COMMAND="lazygit"
            tmux select-pane -T "git"
            ;;
        "restart")
            local session=$(tmux display-message -p '#S')
            tmux kill-session -t "$session"
            exec "$NEXUS_SCRIPTS/launcher.sh"
            ;;
        "exit")
            local session=$(tmux display-message -p '#S')
            tmux kill-session -t "$session"
            exit 0
            ;;
        *)
            # Empty selection or Escape - default to shell
            COMMAND="/bin/zsh -i"
            ;;
    esac
}

# Main execution
if [[ -n "$COMMAND" ]]; then
    run_tool
fi

# Tool exited - show hub in a loop
while true; do
    show_hub
    if [[ -n "$COMMAND" ]]; then
        run_tool
    fi
done

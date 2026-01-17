#!/bin/bash

# --- Nexus Global Command Dispatcher ---
# Handles commands from the ':' prompt in TMUX
# UI command dispatcher (TMUX)

CMD="$1"
NEXUS_HOME="${NEXUS_HOME:-$HOME/.config/nexus-shell}"
NEXUS_BIN="$NEXUS_HOME/bin"
NEXUS_SCRIPTS="$NEXUS_HOME/scripts"
NEXUS_STATE="${NEXUS_STATE:-/tmp/nexus_$(whoami)}"

# Determine project from session name
SESSION_NAME=$(tmux display-message -p '#S')
PROJECT_NAME=${SESSION_NAME#nexus_}
NVIM_PIPE="${NEXUS_PIPE:-$NEXUS_STATE/pipes/nvim_${PROJECT_NAME}.pipe}"

case "$CMD" in
    # === Exit Commands ===
    "q"|":q")
        # Safe quit - check for unsaved changes
        if [[ -S "$NVIM_PIPE" ]]; then
            DIRTY=$("$NEXUS_BIN/nvim" --server "$NVIM_PIPE" --remote-expr "v:lua.is_dirty()" 2>/dev/null)
            if [[ "$DIRTY" == "true" ]]; then
                tmux display-message "Unsaved changes! Use :wq to save or :q! to force quit"
                exit 1
            fi
        fi
        "$NEXUS_SCRIPTS/guard.sh" exit
        ;;
        
    "wq"|":wq")
        # Save and quit
        if [[ -S "$NVIM_PIPE" ]]; then
            tmux display-message "Saving buffers..."
            "$NEXUS_BIN/nvim" --server "$NVIM_PIPE" --remote-send ":wa<CR>"
            sleep 0.5
        fi
        "$NEXUS_SCRIPTS/guard.sh" exit
        ;;
        
    "q!"|":q!")
        # Force quit
        "$NEXUS_SCRIPTS/guard.sh" force
        ;;

    # === View Commands ===
    "v"|":v")
        # Toggle Vision/Render mode
        "$NEXUS_SCRIPTS/swap.sh"
        ;;

    # === Pane Navigation ===
    "n"|":n")
        tmux select-pane -t tree 2>/dev/null || tmux select-pane -t 0
        ;;
    "e"|":e")
        tmux select-pane -t editor 2>/dev/null || tmux select-pane -t 1
        ;;
    "t"|":t")
        tmux select-pane -t terminal 2>/dev/null || tmux select-pane -t 2
        ;;
    "c"|":c")
        tmux select-pane -t chat 2>/dev/null || tmux select-pane -t 3
        ;;

    # === Theme ===
    "theme"|":theme")
        "$NEXUS_SCRIPTS/theme.sh" menu
        ;;

    # === Help ===
    "help"|":help"|"?"|":?")
        tmux display-popup -E -w 60% -h 70% "cat << 'EOF'
╔══════════════════════════════════════════════════════════╗
║                  NEXUS-SHELL COMMANDS                    ║
╠══════════════════════════════════════════════════════════╣
║  EXIT                                                    ║
║    :q      - Quit (checks for unsaved changes)           ║
║    :wq     - Save all and quit                           ║
║    :q!     - Force quit                                  ║
║                                                          ║
║  NAVIGATION                                              ║
║    :n      - Focus Navigator (Tree)                      ║
║    :e      - Focus Editor                                ║
║    :t      - Focus Terminal                              ║
║    :c      - Focus Chat                                  ║
║                                                          ║
║  VIEW                                                    ║
║    :v      - Toggle Editor/Render mode                   ║
║    :theme  - Change color theme                          ║
║                                                          ║
║  RESIZE (After Alt-Esc)                                  ║
║    Shift+H/J/K/L - Resize panes                          ║
║                                                          ║
║  Press Enter to close                                    ║
╚══════════════════════════════════════════════════════════╝
EOF
read"
        ;;

    # === Fallback ===
    *)
        # Try as tmux command
        if [[ -n "$CMD" ]]; then
            tmux $CMD 2>/dev/null || tmux display-message "Unknown command: $CMD (try :help)"
        fi
        ;;
esac

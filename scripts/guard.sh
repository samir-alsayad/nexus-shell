#!/bin/bash

# --- Nexus Guard: Session Cleanup ---
# Handles graceful and forced session termination

ACTION="${1:-exit}"
SESSION_NAME=$(tmux display-message -p '#S')

case "$ACTION" in
    "exit")
        echo "[*] Nexus: Shutting down station..."
        tmux kill-session -t "$SESSION_NAME"
        ;;
        
    "force")
        echo "[!] Nexus: Force shutdown..."
        # Kill any lingering nexus processes
        pkill -f "nexus_" 2>/dev/null
        tmux kill-session -t "$SESSION_NAME"
        ;;
        
    *)
        echo "Usage: guard.sh [exit|force]"
        exit 1
        ;;
esac

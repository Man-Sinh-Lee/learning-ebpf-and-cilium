SESSION_NAME="Battle"

tmux new-session -d -s "$SESSION_NAME"

# Split the first window into two panes vertically
tmux split-window -h

# Split both the left and right panes horizontally to create four panes
tmux select-pane -t 0
tmux split-window -v
tmux select-pane -t 2
tmux split-window -v

# Your commands go below. Replace 'command1', 'command2', etc., with your commands.
# Pane 0 - Top Left
tmux send-keys -t "$SESSION_NAME":0.0 'echo -e "\033[1m🟥 red-leader\033[0m\n\n"; kubectl exec -ti red-leader -- socat UDP4-RECVFROM:8888,reuseaddr,ip-add-membership=225.0.0.21:0.0.0.0,fork -' C-m

# Pane 1 - Bottom Left
tmux send-keys -t "$SESSION_NAME":0.1 'echo -e "\033[1m🦅 millenium-falcon\033[0m\n\n"; kubectl exec -ti millenium-falcon -- socat UDP4-RECVFROM:8888,reuseaddr,ip-add-membership=225.0.0.21:0.0.0.0,fork -' C-m

# Pane 2 - Top Right
tmux send-keys -t "$SESSION_NAME":0.2 'echo -e "\033[1m🧑 luke\033[0m\n\n"; kubectl exec -ti luke -- sh -c "socat UDP4-RECVFROM:8888,reuseaddr,ip-add-membership=225.0.0.21:0.0.0.0,fork - & socat UDP4-RECVFROM:7777,reuseaddr,ip-add-membership=225.0.0.42:0.0.0.0,fork -"' C-m

# Pane 3 - Bottom Right
tmux send-keys -t "$SESSION_NAME":0.3 'echo -e "\033[1m⬛ darth-vader\033[0m\n\n"; kubectl exec -ti darth-vader -- socat UDP4-RECVFROM:6666,reuseaddr,ip-add-membership=225.0.0.11:0.0.0.0,fork -' C-m

# Optionally, you might want to select the first pane to start with.
tmux select-pane -t 0

# Attach to the session
tmux attach-session -t "$SESSION_NAME"

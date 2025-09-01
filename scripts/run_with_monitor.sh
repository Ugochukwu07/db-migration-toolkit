#!/bin/bash

# === RUN SYNC WITH MONITORING ===
# This script starts the sync process and opens monitoring in a new terminal

LOG_FILE="sync_progress.log"
PID_FILE="./sync_pids.tmp"

echo "🚀 Starting database synchronization with monitoring..."

# Clean up old log and PID files
rm -f "$LOG_FILE"
rm -f "$PID_FILE"

# Create process group for easy termination
set -m  # Enable job control

# Start the sync process in background with logging
echo "📝 Starting sync process (logging to $LOG_FILE)..."
./multi_thread_sync.sh > "$LOG_FILE" 2>&1 &
SYNC_PID=$!

# Store the main PID and process group
echo "$SYNC_PID" > "$PID_FILE"
PGID=$(ps -o pgid= -p $SYNC_PID | tr -d ' ')
echo "PGID:$PGID" >> "$PID_FILE"

echo "🔍 Sync started with PID: $SYNC_PID (Process Group: $PGID)"
echo "📊 Starting monitor in 3 seconds..."
sleep 3

# Try to open monitoring in a new terminal window
if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal -- bash -c "./monitor_sync.sh; read -p 'Press Enter to close...'"
elif command -v xterm >/dev/null 2>&1; then
    xterm -e "bash -c './monitor_sync.sh; read -p \"Press Enter to close...\"'" &
elif command -v konsole >/dev/null 2>&1; then
    konsole -e bash -c "./monitor_sync.sh; read -p 'Press Enter to close...'" &
else
    echo "⚠️  Could not open new terminal window."
    echo "🔍 You can manually run: ./monitor_sync.sh"
    echo "📄 Or monitor logs with: tail -f $LOG_FILE"
fi

echo ""
echo "📋 MONITORING OPTIONS:"
echo "1. Watch the monitoring window that just opened"
echo "2. In another terminal, run: ./monitor_sync.sh"
echo "3. Monitor logs: tail -f $LOG_FILE"
echo "4. Check processes: ps aux | grep multi_thread_sync"
echo ""
echo "⏹️  STOP ALL SYNC PROCESSES:"
echo "   Quick stop: ./stop_sync.sh"
echo "   Manual:     kill -TERM -$PGID"
echo "   Force kill: kill -KILL -$PGID"
echo "   Main PID:   $SYNC_PID"
echo ""

# Wait for sync to complete
wait $SYNC_PID
SYNC_EXIT_CODE=$?

echo ""
if [ $SYNC_EXIT_CODE -eq 0 ]; then
    echo "✅ Sync completed successfully!"
else
    echo "❌ Sync completed with errors (exit code: $SYNC_EXIT_CODE)"
fi

echo "📄 Full log available in: $LOG_FILE"

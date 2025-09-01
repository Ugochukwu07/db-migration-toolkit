#!/bin/bash

# === STOP DATABASE SYNC PROCESSES ===
# This script stops all processes related to database synchronization

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PID_FILE="./sync_pids.tmp"

echo -e "${CYAN}🛑 DATABASE SYNC STOP UTILITY${NC}"
echo "==============================="

# Function to find sync processes
find_sync_processes() {
    ps aux | grep -E "(multi_thread_sync|mysqldump.*errandaar_db|mysqldump.*messaging_db|mysqldump.*notification_db|mysqldump.*payment_db|mysqldump.*post_db|mysqldump.*pref_db)" | grep -v grep | grep -v stop_sync
}

# Function to stop processes by pattern
stop_by_pattern() {
    local pattern="$1"
    local description="$2"
    
    local pids=$(pgrep -f "$pattern" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo -e "${YELLOW}🔍 Found $description processes: $pids${NC}"
        echo "$pids" | xargs kill -TERM 2>/dev/null
        sleep 2
        
        # Check if any are still running and force kill
        local remaining=$(pgrep -f "$pattern" 2>/dev/null)
        if [ -n "$remaining" ]; then
            echo -e "${RED}💀 Force killing stubborn processes: $remaining${NC}"
            echo "$remaining" | xargs kill -KILL 2>/dev/null
        fi
        
        return 0
    else
        return 1
    fi
}

# Check current sync processes
current_processes=$(find_sync_processes)
if [ -z "$current_processes" ]; then
    echo -e "${GREEN}✅ No sync processes currently running${NC}"
    
    # Clean up PID file if it exists
    if [ -f "$PID_FILE" ]; then
        rm -f "$PID_FILE"
        echo -e "${GREEN}🧹 Cleaned up PID file${NC}"
    fi
    
    exit 0
fi

echo -e "${YELLOW}📊 Current sync processes:${NC}"
echo "$current_processes"
echo ""

# Method 1: Try using stored PID file (most reliable)
if [ -f "$PID_FILE" ]; then
    echo -e "${BLUE}🎯 Method 1: Using stored PID file${NC}"
    
    # Get main PID and process group
    MAIN_PID=$(head -n 1 "$PID_FILE")
    PGID_LINE=$(grep "^PGID:" "$PID_FILE" 2>/dev/null)
    PGID=$(echo "$PGID_LINE" | cut -d':' -f2)
    
    if [ -n "$MAIN_PID" ] && kill -0 "$MAIN_PID" 2>/dev/null; then
        echo -e "${YELLOW}🔫 Stopping process group (PGID: $PGID)...${NC}"
        
        if [ -n "$PGID" ]; then
            # Kill entire process group
            kill -TERM -"$PGID" 2>/dev/null
            sleep 3
            
            # Force kill if still running
            if kill -0 -"$PGID" 2>/dev/null; then
                echo -e "${RED}💀 Force killing process group...${NC}"
                kill -KILL -"$PGID" 2>/dev/null
            fi
        else
            # Fallback to main PID only
            echo -e "${YELLOW}⚠️  No PGID found, killing main PID: $MAIN_PID${NC}"
            kill -TERM "$MAIN_PID" 2>/dev/null
            sleep 2
            if kill -0 "$MAIN_PID" 2>/dev/null; then
                kill -KILL "$MAIN_PID" 2>/dev/null
            fi
        fi
        
        rm -f "$PID_FILE"
        echo -e "${GREEN}✅ Process group terminated${NC}"
    else
        echo -e "${YELLOW}⚠️  Main PID $MAIN_PID not running, trying pattern matching...${NC}"
        rm -f "$PID_FILE"
    fi
fi

# Method 2: Pattern-based killing (fallback)
echo -e "${BLUE}🎯 Method 2: Pattern-based process termination${NC}"

# Stop multi_thread_sync processes
stop_by_pattern "multi_thread_sync.sh" "multi-thread sync"

# Stop mysqldump processes for our specific databases
stop_by_pattern "mysqldump.*errandaar_db" "errandaar_db mysqldump"
stop_by_pattern "mysqldump.*messaging_db" "messaging_db mysqldump"
stop_by_pattern "mysqldump.*messaging_v2_db" "messaging_v2_db mysqldump"
stop_by_pattern "mysqldump.*notification_db" "notification_db mysqldump"
stop_by_pattern "mysqldump.*payment_db" "payment_db mysqldump"
stop_by_pattern "mysqldump.*post_bot_db" "post_bot_db mysqldump"
stop_by_pattern "mysqldump.*post_db" "post_db mysqldump"
stop_by_pattern "mysqldump.*pref_db" "pref_db mysqldump"

# Method 3: Nuclear option - kill all mysqldump processes
echo -e "${BLUE}🎯 Method 3: Checking for remaining mysqldump processes${NC}"
remaining_dumps=$(pgrep mysqldump 2>/dev/null)
if [ -n "$remaining_dumps" ]; then
    echo -e "${YELLOW}⚠️  Found remaining mysqldump processes: $remaining_dumps${NC}"
    read -p "Kill ALL mysqldump processes? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$remaining_dumps" | xargs kill -TERM 2>/dev/null
        sleep 2
        remaining_dumps=$(pgrep mysqldump 2>/dev/null)
        if [ -n "$remaining_dumps" ]; then
            echo "$remaining_dumps" | xargs kill -KILL 2>/dev/null
        fi
        echo -e "${GREEN}✅ All mysqldump processes terminated${NC}"
    fi
fi

# Final verification
echo ""
echo -e "${CYAN}🔍 Final verification:${NC}"
final_processes=$(find_sync_processes)
if [ -z "$final_processes" ]; then
    echo -e "${GREEN}✅ All sync processes successfully stopped!${NC}"
    
    # Clean up any remaining files
    rm -f "$PID_FILE"
    
    # Show summary
    echo -e "${GREEN}🧹 Cleanup completed:${NC}"
    echo -e "  - All sync processes terminated"
    echo -e "  - PID files cleaned up"
    echo -e "  - Ready for new sync operations"
else
    echo -e "${RED}⚠️  Some processes may still be running:${NC}"
    echo "$final_processes"
    echo ""
    echo -e "${YELLOW}Manual cleanup commands:${NC}"
    echo "  pkill -f multi_thread_sync"
    echo "  pkill mysqldump"
    echo "  ps aux | grep -E '(multi_thread_sync|mysqldump)' | grep -v grep"
fi

echo ""
echo -e "${CYAN}Database sync stop utility completed!${NC}"

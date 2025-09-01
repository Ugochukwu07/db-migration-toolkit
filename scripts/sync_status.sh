#!/bin/bash

# === QUICK SYNC STATUS CHECKER ===
# Quick overview of sync processes and progress

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}📊 QUICK SYNC STATUS${NC}"
echo "===================="

# Check for running processes
sync_processes=$(ps aux | grep -E "(multi_thread_sync|mysqldump.*errandaar_db|mysqldump.*messaging_db|mysqldump.*notification_db|mysqldump.*payment_db|mysqldump.*post_db|mysqldump.*pref_db)" | grep -v grep | grep -v sync_status)

if [ -n "$sync_processes" ]; then
    echo -e "${GREEN}🔄 SYNC ACTIVE${NC}"
    
    # Count processes
    total_procs=$(echo "$sync_processes" | wc -l)
    mysqldump_procs=$(echo "$sync_processes" | grep -c mysqldump)
    
    echo -e "${BLUE}📈 Active processes: $total_procs (${mysqldump_procs} mysqldump)${NC}"
    
    # Show backup file status
    echo -e "${YELLOW}📁 Current backup files:${NC}"
    if ls ./backups/*.sql >/dev/null 2>&1; then
        ls -lah ./backups/*.sql | grep -v test_ | while read -r line; do
            size=$(echo "$line" | awk '{print $5}')
            name=$(echo "$line" | awk '{print $9}' | xargs basename)
            time=$(echo "$line" | awk '{print $6 " " $7 " " $8}')
            echo "  📄 $name ($size) - $time"
        done
    else
        echo "  ❌ No backup files found"
    fi
    
    # Quick status from status file
    if [ -f "./backups/sync_status.tmp" ]; then
        success_count=$(grep -c "^SUCCESS:" "./backups/sync_status.tmp" 2>/dev/null || echo "0")
        failed_count=$(grep -c "^FAILED:" "./backups/sync_status.tmp" 2>/dev/null || echo "0")
        echo -e "${GREEN}✅ Completed: $success_count${NC}"
        echo -e "${RED}❌ Failed: $failed_count${NC}"
    fi
    
else
    echo -e "${YELLOW}💤 NO SYNC RUNNING${NC}"
    
    # Check if there are recent backup files
    recent_backups=$(find ./backups -name "*.sql" -not -name "test_*" -mmin -30 2>/dev/null)
    if [ -n "$recent_backups" ]; then
        echo -e "${BLUE}📁 Recent backups (last 30 mins):${NC}"
        echo "$recent_backups" | while read -r file; do
            if [ -f "$file" ]; then
                size=$(du -h "$file" | cut -f1)
                name=$(basename "$file")
                echo "  📄 $name ($size)"
            fi
        done
    else
        echo -e "${YELLOW}📁 No recent backup activity${NC}"
    fi
fi

# Show quick actions
echo ""
echo -e "${CYAN}🎮 QUICK ACTIONS:${NC}"
echo "  🚀 Start sync:    ./run_with_monitor.sh"
echo "  📊 Monitor:       ./monitor_sync.sh"
echo "  🛑 Stop sync:     ./stop_sync.sh"
echo "  🚨 View errors:   ./view_errors.sh"
echo "  📄 View logs:     tail -f sync_progress.log"

#!/bin/bash

# === SYNC MONITORING SCRIPT ===
# Monitor the multi-threaded database synchronization process

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the configuration loader
source "$SCRIPT_DIR/config_loader.sh"

# Load configuration
if ! load_config "$PROJECT_ROOT/config/config.env" 2>/dev/null; then
    echo "Warning: Could not load configuration, using defaults"
fi

# Configuration with fallbacks
DATA_DIR="${PROJECT_ROOT}/${BACKUP_DIR:-data}"
BACKUP_DIR="$DATA_DIR/backups/multi_thread_sync"
TMP_DIR="$DATA_DIR/tmp/multi_thread_sync"
REFRESH_INTERVAL=${MONITOR_REFRESH_INTERVAL:-2}
LOG_FILE="sync_progress.log"

# Auto-detect latest session if no specific one provided
if [ -z "$SESSION_TIMESTAMP" ]; then
    # Find the most recent status file
    LATEST_STATUS=$(ls -t "$TMP_DIR"/sync_status-*.tmp 2>/dev/null | head -n 1)
    if [ -n "$LATEST_STATUS" ]; then
        SESSION_TIMESTAMP=$(basename "$LATEST_STATUS" | sed 's/sync_status-\(.*\)\.tmp/\1/')
    fi
fi

# Function to display header
show_header() {
    clear
    echo -e "${CYAN}=================================="
    echo -e "🚀 DATABASE SYNC MONITOR"
    echo -e "==================================${NC}"
    echo -e "Refresh Rate: ${REFRESH_INTERVAL}s | Press Ctrl+C to exit"
    if [ -n "$SESSION_TIMESTAMP" ]; then
        echo -e "Session: ${YELLOW}$SESSION_TIMESTAMP${NC}"
    else
        echo -e "Session: ${RED}No active session found${NC}"
    fi
    echo ""
}

# Function to show process status
show_processes() {
    echo -e "${YELLOW}📊 ACTIVE PROCESSES:${NC}"
    local processes=$(ps aux | grep -E "(multi_thread_sync|mysqldump|mysql)" | grep -v grep | grep -v monitor_sync)
    if [ -n "$processes" ]; then
        echo "$processes" | while read -r line; do
            if echo "$line" | grep -q "multi_thread_sync"; then
                echo -e "${GREEN}🖥️  $line${NC}"
            elif echo "$line" | grep -q "mysqldump"; then
                echo -e "${BLUE}📤 $line${NC}"
            elif echo "$line" | grep -q "mysql"; then
                echo -e "${PURPLE}📥 $line${NC}"
            fi
        done
    else
        echo -e "${RED}❌ No sync processes running${NC}"
    fi
    echo ""
}

# Function to show backup files status
show_backup_status() {
    echo -e "${YELLOW}📁 BACKUP FILES STATUS:${NC}"
    if [ -d "$BACKUP_DIR" ]; then
        # Show files for current session if available
        if [ -n "$SESSION_TIMESTAMP" ]; then
            local session_files=$(find "$BACKUP_DIR" -name "*-${SESSION_TIMESTAMP}.sql" 2>/dev/null)
            if [ -n "$session_files" ]; then
                echo -e "${CYAN}Current session files:${NC}"
                echo "$session_files" | while read -r file; do
                    if [ -f "$file" ]; then
                        local size=$(du -h "$file" 2>/dev/null | cut -f1)
                        local mtime=$(stat -c %Y "$file" 2>/dev/null)
                        local current_time=$(date +%s)
                        local age=$((current_time - mtime))
                        
                        local filename=$(basename "$file")
                        if [ $age -lt 60 ]; then
                            echo -e "  ${GREEN}🟢 $filename (${size}) - Recently updated${NC}"
                        elif [ $age -lt 300 ]; then
                            echo -e "  ${YELLOW}🟡 $filename (${size}) - ${age}s ago${NC}"
                        else
                            echo -e "  ${RED}🔴 $filename (${size}) - ${age}s ago${NC}"
                        fi
                    fi
                done
            else
                echo -e "${YELLOW}⏳ No backup files for current session yet${NC}"
            fi
        else
            # Show recent files if no specific session
            local recent_files=$(find "$BACKUP_DIR" -name "*.sql" -mmin -60 2>/dev/null | head -10)
            if [ -n "$recent_files" ]; then
                echo -e "${CYAN}Recent backup files (last hour):${NC}"
                echo "$recent_files" | while read -r file; do
                    if [ -f "$file" ]; then
                        local size=$(du -h "$file" 2>/dev/null | cut -f1)
                        local filename=$(basename "$file")
                        echo -e "  ${GREEN}📄${NC} $filename (${size})"
                    fi
                done
            else
                echo -e "${RED}❌ No recent backup files found${NC}"
            fi
        fi
        
        # Show total backup directory size
        local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        echo -e "${CYAN}📦 Total backup size: $total_size${NC}"
    else
        echo -e "${RED}❌ Backup directory not found${NC}"
    fi
    echo ""
}

# Function to show recent logs
show_recent_logs() {
    echo -e "${YELLOW}📄 RECENT LOG ENTRIES:${NC}"
    if [ -f "$LOG_FILE" ]; then
        tail -n 10 "$LOG_FILE" | while read -r line; do
            if echo "$line" | grep -q "ERROR"; then
                echo -e "${RED}$line${NC}"
            elif echo "$line" | grep -q "SUCCESS"; then
                echo -e "${GREEN}$line${NC}"
            elif echo "$line" | grep -q "WARN"; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo -e "${NC}$line${NC}"
            fi
        done
    else
        echo -e "${RED}❌ No log file found${NC}"
    fi
    echo ""
}

# Function to show sync status from status file
show_sync_status() {
    echo -e "${YELLOW}🎯 SYNC STATUS:${NC}"
    local status_file=""
    
    if [ -n "$SESSION_TIMESTAMP" ]; then
        status_file="$TMP_DIR/sync_status-$SESSION_TIMESTAMP.tmp"
    fi
    
    if [ -n "$status_file" ] && [ -f "$status_file" ]; then
        local success_count=$(grep -c "^SUCCESS:" "$status_file" 2>/dev/null)
        local failed_count=$(grep -c "^FAILED:" "$status_file" 2>/dev/null)
        success_count=${success_count:-0}
        failed_count=${failed_count:-0}
        local total_count=$((success_count + failed_count))
        
        echo -e "${GREEN}✅ Completed: $success_count${NC}"
        echo -e "${RED}❌ Failed: $failed_count${NC}"
        echo -e "${CYAN}📊 Total: $total_count${NC}"
        
        if [ $success_count -gt 0 ]; then
            echo -e "${GREEN}Successful databases:${NC}"
            grep "^SUCCESS:" "$status_file" | while IFS=':' read -r status db duration attempt timestamp; do
                if [ -n "$attempt" ]; then
                    echo -e "  ${GREEN}✓${NC} $db ($duration, attempt $attempt) -> ${db}-${timestamp}.sql"
                else
                    echo -e "  ${GREEN}✓${NC} $db ($duration) -> ${db}-${timestamp}.sql"
                fi
            done
        fi
        
        if [ $failed_count -gt 0 ]; then
            echo -e "${RED}Failed databases:${NC}"
            grep "^FAILED:" "$status_file" | while IFS=':' read -r status db attempts timestamp; do
                echo -e "  ${RED}✗${NC} $db (failed after $attempts attempts)"
            done
        fi
    else
        echo -e "${YELLOW}⏳ No status file found - sync may not have started or completed${NC}"
        if [ -z "$SESSION_TIMESTAMP" ]; then
            echo -e "${BLUE}💡 No active session detected${NC}"
        fi
    fi
    echo ""
}

# Function to show error details
show_error_details() {
    echo -e "${YELLOW}🚨 ERROR DETAILS:${NC}"
    local error_file=""
    
    if [ -n "$SESSION_TIMESTAMP" ]; then
        error_file="$TMP_DIR/error_log-$SESSION_TIMESTAMP.tmp"
    fi
    
    if [ -n "$error_file" ] && [ -f "$error_file" ]; then
        local dump_errors=$(grep -c "^DUMP_ERROR:" "$error_file" 2>/dev/null)
        local prep_errors=$(grep -c "^PREP_ERROR:" "$error_file" 2>/dev/null)
        local import_errors=$(grep -c "^IMPORT_ERROR:" "$error_file" 2>/dev/null)
        
        dump_errors=${dump_errors:-0}
        prep_errors=${prep_errors:-0}
        import_errors=${import_errors:-0}
        
        if [ $((dump_errors + prep_errors + import_errors)) -gt 0 ]; then
            echo -e "${RED}📤 Dump errors: $dump_errors${NC}"
            echo -e "${RED}🔧 Preparation errors: $prep_errors${NC}"
            echo -e "${RED}📥 Import errors: $import_errors${NC}"
            
            # Show recent errors (last 3)
            echo -e "${YELLOW}Recent errors:${NC}"
            tail -n 3 "$error_file" 2>/dev/null | while IFS=':' read -r error_type db attempt error_msg timestamp; do
                case "$error_type" in
                    "DUMP_ERROR")
                        echo -e "  ${RED}📤${NC} $db ($attempt): $error_msg"
                        ;;
                    "PREP_ERROR")
                        echo -e "  ${RED}🔧${NC} $db ($attempt): $error_msg"
                        ;;
                    "IMPORT_ERROR")
                        echo -e "  ${RED}📥${NC} $db ($attempt): $error_msg"
                        ;;
                esac
            done
        else
            echo -e "${GREEN}✅ No errors logged${NC}"
        fi
    else
        echo -e "${GREEN}✅ No error log found for current session${NC}"
    fi
    echo ""
}

# Function to show retry activity
show_retry_activity() {
    echo -e "${YELLOW}🔄 RETRY ACTIVITY:${NC}"
    local error_file=""
    
    if [ -n "$SESSION_TIMESTAMP" ]; then
        error_file="$TMP_DIR/error_log-$SESSION_TIMESTAMP.tmp"
    fi
    
    if [ -n "$error_file" ] && [ -f "$error_file" ]; then
        # Count retries by database
        local retry_databases=$(grep "_attempt_[2-9]" "$error_file" 2>/dev/null | cut -d':' -f2 | sort | uniq)
        if [ -n "$retry_databases" ]; then
            echo "$retry_databases" | while read -r db; do
                if [ -n "$db" ]; then
                    local retry_count=$(grep ":$db:attempt_" "$error_file" | wc -l)
                    echo -e "  ${YELLOW}🔄${NC} $db: $retry_count retry attempts"
                fi
            done
        else
            echo -e "${GREEN}✅ No retries needed${NC}"
        fi
    else
        echo -e "${GREEN}✅ No retry activity for current session${NC}"
    fi
    echo ""
}

# Function to show system resources
show_system_resources() {
    echo -e "${YELLOW}💻 SYSTEM RESOURCES:${NC}"
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    local mem_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    local disk_usage=$(df . | tail -1 | awk '{print $5}' | sed 's/%//')
    
    echo -e "${CYAN}🖥️  CPU Usage: ${cpu_usage}%${NC}"
    echo -e "${CYAN}🧠 Memory Usage: ${mem_usage}%${NC}"
    echo -e "${CYAN}💾 Disk Usage: ${disk_usage}%${NC}"
    echo ""
}

# Main monitoring loop
main() {
    echo "Starting sync monitor..."
    echo "Data directory: $DATA_DIR"
    echo "Backup directory: $BACKUP_DIR"
    echo "Temporary directory: $TMP_DIR"
    echo "Log file: $LOG_FILE"
    if [ -n "$SESSION_TIMESTAMP" ]; then
        echo "Monitoring session: $SESSION_TIMESTAMP"
    else
        echo "Monitoring: Latest session (auto-detect)"
    fi
    echo ""
    
    while true; do
        show_header
        show_processes
        show_sync_status
        show_retry_activity
        show_error_details
        show_backup_status
        show_recent_logs
        show_system_resources
        
        echo -e "${CYAN}Last updated: $(date)${NC}"
        sleep $REFRESH_INTERVAL
    done
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${GREEN}Monitor stopped by user${NC}"; exit 0' INT

# Check if script arguments are provided
case "$1" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --interval N   Set refresh interval in seconds (default: 2)"
        echo "  --log FILE     Specify log file to monitor (default: sync_progress.log)"
        echo "  --session TS   Monitor specific session timestamp"
        exit 0
        ;;
    --interval)
        if [ -n "$2" ] && [ "$2" -gt 0 ] 2>/dev/null; then
            REFRESH_INTERVAL="$2"
        else
            echo "Error: Invalid interval value"
            exit 1
        fi
        ;;
    --log)
        if [ -n "$2" ]; then
            LOG_FILE="$2"
        else
            echo "Error: Log file not specified"
            exit 1
        fi
        ;;
    --session)
        if [ -n "$2" ]; then
            SESSION_TIMESTAMP="$2"
        else
            echo "Error: Session timestamp not specified"
            exit 1
        fi
        ;;
esac

# Start monitoring
main

#!/bin/bash

# === ERROR LOG VIEWER ===
# Script to view detailed error logs from database synchronization

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Use configured directories or fallbacks
DATA_DIR="${PROJECT_ROOT}/${BACKUP_DIR:-data}"
BACKUP_DIR="$DATA_DIR/backups"
TMP_DIR="$DATA_DIR/tmp"

# Look for error logs in various locations
ERROR_LOGS=(
    "$BACKUP_DIR/error_log.tmp"
    "$TMP_DIR/multi_thread_sync/error_log-"*.tmp
    "$TMP_DIR/multi_thread_table_sync/error_log-"*.tmp
)

echo -e "${CYAN}=================================="
echo -e "🚨 DATABASE SYNC ERROR VIEWER"
echo -e "==================================${NC}"
echo ""

# Find the most recent error log
LATEST_ERROR_LOG=""
for pattern in "${ERROR_LOGS[@]}"; do
    if ls $pattern 1> /dev/null 2>&1; then
        LATEST_ERROR_LOG=$(ls -t $pattern 2>/dev/null | head -n 1)
        break
    fi
done

if [ -z "$LATEST_ERROR_LOG" ] || [ ! -f "$LATEST_ERROR_LOG" ]; then
    echo -e "${GREEN}✅ No error log found - no errors occurred!${NC}"
    echo -e "${CYAN}Searched in:${NC}"
    for pattern in "${ERROR_LOGS[@]}"; do
        echo -e "  - $pattern"
    done
    exit 0
fi

echo -e "${CYAN}Using error log: $LATEST_ERROR_LOG${NC}"
echo ""

# Count different types of errors
dump_errors=$(grep -c "^DUMP_ERROR:" "$LATEST_ERROR_LOG" 2>/dev/null || echo "0")
prep_errors=$(grep -c "^PREP_ERROR:" "$LATEST_ERROR_LOG" 2>/dev/null || echo "0")
import_errors=$(grep -c "^IMPORT_ERROR:" "$LATEST_ERROR_LOG" 2>/dev/null || echo "0")
total_errors=$((dump_errors + prep_errors + import_errors))

echo -e "${YELLOW}📊 ERROR SUMMARY:${NC}"
echo -e "  ${RED}📤 Dump errors: $dump_errors${NC}"
echo -e "  ${RED}🔧 Preparation errors: $prep_errors${NC}"
echo -e "  ${RED}📥 Import errors: $import_errors${NC}"
echo -e "  ${RED}📊 Total errors: $total_errors${NC}"
echo ""

# Show errors by database
echo -e "${YELLOW}🗂️  ERRORS BY DATABASE:${NC}"
databases=$(cut -d':' -f2 "$LATEST_ERROR_LOG" | sort | uniq)
for db in $databases; do
    if [ -n "$db" ]; then
        local db_errors=$(grep ":$db:" "$LATEST_ERROR_LOG" | wc -l)
        echo -e "  ${CYAN}$db${NC}: $db_errors errors"
        
        # Show error details for this database
        grep ":$db:" "$LATEST_ERROR_LOG" | while IFS=':' read -r error_type database attempt error_msg; do
            case "$error_type" in
                "DUMP_ERROR")
                    echo -e "    ${RED}📤${NC} $attempt: $error_msg"
                    ;;
                "PREP_ERROR")
                    echo -e "    ${RED}🔧${NC} $attempt: $error_msg"
                    ;;
                "IMPORT_ERROR")
                    echo -e "    ${RED}📥${NC} $attempt: $error_msg"
                    ;;
            esac
        done
        echo ""
    fi
done

echo -e "${YELLOW}📄 RAW ERROR LOG:${NC}"
echo -e "${BLUE}(File: $LATEST_ERROR_LOG)${NC}"
echo "----------------------------------------"
cat "$LATEST_ERROR_LOG"
echo "----------------------------------------"
echo ""

# Show individual error files if they exist
echo -e "${YELLOW}📁 INDIVIDUAL ERROR FILES:${NC}"
error_files=$(find "$BACKUP_DIR" "$TMP_DIR" -name "*_error*.log" 2>/dev/null | head -10)
if [ -n "$error_files" ]; then
    echo "$error_files" | while read -r file; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            echo -e "${CYAN}$filename:${NC}"
            echo "  $(head -n 3 "$file" | tr '\n' ' ')"
            echo ""
        fi
    done
else
    echo -e "${GREEN}✅ No individual error files found${NC}"
fi

echo -e "${CYAN}Error log viewing completed!${NC}"

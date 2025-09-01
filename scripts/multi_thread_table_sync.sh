#!/bin/bash

# === MULTI-THREADED TABLE SYNCHRONIZATION SCRIPT ===
# This script processes multiple database tables in parallel for faster synchronization
# Moves table dumps from remote database and imports them to local databases
# Now uses externalized configuration from config.env

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the configuration loader
source "$SCRIPT_DIR/config_loader.sh"

# === LOGGING FUNCTION ===
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local pid=$$
    local thread_id=$(echo $BASHPID | tail -c 5)  # Last 4 digits of process ID
    echo "[$timestamp] [$level] [Thread-$thread_id] $message"
}

# === THREAD-SAFE LOGGING ===
thread_log() {
    local level="$1"
    local db="$2"
    local table="$3"
    shift 3
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local thread_id=$(echo $BASHPID | tail -c 5)
    echo "[$timestamp] [$level] [DB:$db] [Table:$table] [Thread-$thread_id] $message"
}

# === TABLE SYNC FUNCTION WITH RETRY (runs in background) ===
sync_table() {
    local SOURCE_DB="$1"
    local TARGET_DB="$2"
    local TABLE="$3"
    local BACKUP_DIR="$4"
    local TMP_DIR="$5"
    local TIMESTAMP="$6"
    local start_time=$(date +%s)
    local attempt=1
    local max_attempts=${MAX_RETRY_ATTEMPTS:-3}
    
    thread_log "INFO" "$SOURCE_DB" "$TABLE" "Starting table synchronization (max attempts: $max_attempts)..."
    
    while [ $attempt -le $max_attempts ]; do
        thread_log "INFO" "$SOURCE_DB" "$TABLE" "Attempt $attempt/$max_attempts: Starting sync process..."
        
        # Step 1: Dump table from remote database
        if sync_dump_table "$SOURCE_DB" "$TABLE" "$BACKUP_DIR" "$TMP_DIR" "$TIMESTAMP" $attempt; then
            # Step 2: Import table to local database
            if sync_import_table "$SOURCE_DB" "$TARGET_DB" "$TABLE" "$BACKUP_DIR" "$TMP_DIR" "$TIMESTAMP" $attempt; then
                local end_time=$(date +%s)
                local duration=$((end_time - start_time))
                thread_log "SUCCESS" "$SOURCE_DB" "$TABLE" "Table synchronization completed successfully in ${duration}s (attempt $attempt/$max_attempts)"
                echo "SUCCESS:$SOURCE_DB:$TARGET_DB:$TABLE:${duration}s:$attempt:$TIMESTAMP" >> "$TMP_DIR/sync_status-$TIMESTAMP.tmp"
                return 0
            fi
        fi
        
        # If we reach here, something failed
        if [ $attempt -lt $max_attempts ]; then
            local retry_delay=${RETRY_DELAY:-10}
            thread_log "WARN" "$SOURCE_DB" "$TABLE" "Attempt $attempt failed. Retrying in ${retry_delay}s..."
            sleep $retry_delay
        else
            thread_log "ERROR" "$SOURCE_DB" "$TABLE" "All $max_attempts attempts failed. Giving up."
            echo "FAILED:$SOURCE_DB:$TARGET_DB:$TABLE:$attempt:$TIMESTAMP" >> "$TMP_DIR/sync_status-$TIMESTAMP.tmp"
            return 1
        fi
        
        ((attempt++))
    done
}

# === DUMP TABLE FUNCTION FROM REMOTE DATABASE ===
sync_dump_table() {
    local DB="$1"
    local TABLE="$2"
    local BACKUP_DIR="$3"
    local TMP_DIR="$4"
    local TIMESTAMP="$5"
    local attempt="$6"
    local error_file="$TMP_DIR/${DB}_${TABLE}_dump_error-$TIMESTAMP.log"
    local backup_file="$BACKUP_DIR/${DB}_${TABLE}-${TIMESTAMP}.sql"
    
    thread_log "INFO" "$DB" "$TABLE" "Step 1/2: Dumping table $TABLE from $DB on remote database (attempt $attempt)..."
    thread_log "INFO" "$DB" "$TABLE" "Backup file: $backup_file"
    
    # Clear previous error log
    > "$error_file"
    
    # Get mysqldump options for table sync from configuration
    local dump_options=$(get_mysqldump_table_options)
    
    # Build mysqldump command for specific table
    local dump_cmd="mysqldump -h\"$REMOTE_HOST\" -P\"${REMOTE_PORT:-3306}\" -u\"$REMOTE_USER\" -p\"$REMOTE_PASS\""
    dump_cmd="$dump_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\" --single-transaction"
    dump_cmd="$dump_cmd $dump_options \"$DB\" \"$TABLE\""
    
    if is_debug_mode; then
        thread_log "DEBUG" "$DB" "$TABLE" "Dump command: $dump_cmd"
    fi
    
    # Execute dump command
    eval "$dump_cmd" > "$backup_file" 2>"$error_file"

    if [ $? -ne 0 ]; then
        local error_msg=$(cat "$error_file" 2>/dev/null | head -n 3 | tr '\n' ' ')
        # Filter out password warnings (they're not real errors)
        if echo "$error_msg" | grep -q "Using a password on the command line interface can be insecure" && [ -s "$backup_file" ]; then
            thread_log "WARN" "$DB" "$TABLE" "Dump completed with password warning (attempt $attempt)"
        else
            thread_log "ERROR" "$DB" "$TABLE" "Dump failed (attempt $attempt): ${error_msg}"
            echo "DUMP_ERROR:$DB:$TABLE:attempt_$attempt:${error_msg}:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
            return 1
        fi
    fi

    # Verify dump file was created and has content
    if [ ! -f "$backup_file" ] || [ ! -s "$backup_file" ]; then
        thread_log "ERROR" "$DB" "$TABLE" "Dump file is empty or missing (attempt $attempt)"
        echo "DUMP_ERROR:$DB:$TABLE:attempt_$attempt:Empty or missing dump file:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi

    # Verify the dump contains the table structure
    if ! grep -q "CREATE TABLE" "$backup_file"; then
        thread_log "ERROR" "$DB" "$TABLE" "Dump file doesn't contain table structure (attempt $attempt)"
        echo "DUMP_ERROR:$DB:$TABLE:attempt_$attempt:No table structure found:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi

    local dump_size=$(du -h "$backup_file" | cut -f1)
    local row_count=$(grep -c "INSERT INTO" "$backup_file" 2>/dev/null || echo "0")
    thread_log "SUCCESS" "$DB" "$TABLE" "Table dump completed successfully (Size: $dump_size, Inserts: $row_count, attempt $attempt)"
    rm -f "$error_file"  # Clean up error file on success
    return 0
}

# === IMPORT TABLE FUNCTION TO LOCAL DATABASE ===
sync_import_table() {
    local SOURCE_DB="$1"
    local TARGET_DB="$2"
    local TABLE="$3"
    local BACKUP_DIR="$4"
    local TMP_DIR="$5"
    local TIMESTAMP="$6"
    local attempt="$7"
    local error_file="$TMP_DIR/${SOURCE_DB}_${TABLE}_import_error-$TIMESTAMP.log"
    local backup_file="$BACKUP_DIR/${SOURCE_DB}_${TABLE}-${TIMESTAMP}.sql"
    local local_db_name="$TARGET_DB"
    
    thread_log "INFO" "$SOURCE_DB" "$TABLE" "Step 2/2: Importing table into local database $local_db_name (attempt $attempt)..."
    thread_log "INFO" "$SOURCE_DB" "$TABLE" "Importing from: $backup_file"
    
    # Clear previous error log
    > "$error_file"
    
    # Ensure local database exists
    local create_db_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    create_db_cmd="$create_db_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    
    # Build database creation command
    local db_create_sql="CREATE DATABASE IF NOT EXISTS \`$local_db_name\`"
    if [ -n "${CHARSET:-}" ]; then
        db_create_sql="$db_create_sql CHARACTER SET ${CHARSET}"
    fi
    if [ -n "${COLLATION:-}" ]; then
        db_create_sql="$db_create_sql COLLATE ${COLLATION}"
    fi
    
    create_db_cmd="$create_db_cmd -e '$db_create_sql'"
    
    eval "$create_db_cmd" 2>"$error_file"
    if [ $? -ne 0 ]; then
        local error_msg=$(cat "$error_file" 2>/dev/null | head -n 2 | tr '\n' ' ')
        thread_log "ERROR" "$SOURCE_DB" "$TABLE" "Failed to create/access local database (attempt $attempt): ${error_msg}"
        echo "IMPORT_ERROR:$SOURCE_DB:$TABLE:attempt_$attempt:Database creation failed - ${error_msg}:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi
    
    # Drop existing table if configured to do so
    if should_drop_existing_tables; then
        thread_log "INFO" "$SOURCE_DB" "$TABLE" "Dropping existing table $TABLE (if exists)..."
        local drop_table_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
        drop_table_cmd="$drop_table_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
        drop_table_cmd="$drop_table_cmd \"$local_db_name\" -e 'DROP TABLE IF EXISTS \`$TABLE\`'"
        
        eval "$drop_table_cmd" 2>"$error_file"
        if [ $? -ne 0 ]; then
            local error_msg=$(cat "$error_file" 2>/dev/null | head -n 2 | tr '\n' ' ')
            thread_log "WARN" "$SOURCE_DB" "$TABLE" "Failed to drop existing table (attempt $attempt): ${error_msg}"
            # Continue anyway, as the table might not exist
        fi
    fi
    
    # Import table dump into local DB
    local import_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    import_cmd="$import_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    
    # Set SQL mode if configured
    if [ -n "${SQL_MODE:-}" ]; then
        import_cmd="$import_cmd --init-command=\"SET SESSION sql_mode='${SQL_MODE}'\""
    fi
    
    import_cmd="$import_cmd \"$local_db_name\""
    
    eval "$import_cmd" < "$backup_file" 2>"$error_file"
    if [ $? -ne 0 ]; then
        local error_msg=$(cat "$error_file" 2>/dev/null | head -n 3 | tr '\n' ' ')
        thread_log "ERROR" "$SOURCE_DB" "$TABLE" "Import failed (attempt $attempt): ${error_msg}"
        echo "IMPORT_ERROR:$SOURCE_DB:$TABLE:attempt_$attempt:${error_msg}:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi
    
    # Verify import by checking if table exists and has expected structure
    local table_check_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    table_check_cmd="$table_check_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    table_check_cmd="$table_check_cmd \"$local_db_name\" -e \"SHOW TABLES LIKE '$TABLE';\" 2>/dev/null | wc -l"
    
    local table_exists=$(eval "$table_check_cmd")
    if [ "${table_exists:-0}" -le 1 ]; then
        thread_log "ERROR" "$SOURCE_DB" "$TABLE" "Import verification failed - table not found after import (attempt $attempt)"
        echo "IMPORT_ERROR:$SOURCE_DB:$TABLE:attempt_$attempt:Table not found after import:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi
    
    # Get row count for verification
    local row_count_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    row_count_cmd="$row_count_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    row_count_cmd="$row_count_cmd \"$local_db_name\" -e \"SELECT COUNT(*) FROM \\\`$TABLE\\\`;\" 2>/dev/null | tail -n 1"
    
    local row_count=$(eval "$row_count_cmd")
    thread_log "SUCCESS" "$SOURCE_DB" "$TABLE" "Table import completed successfully (${row_count:-unknown} rows, attempt $attempt)"
    rm -f "$error_file"  # Clean up error file on success
    return 0
}

# === PROGRESS MONITOR FUNCTION ===
monitor_progress() {
    local total_tables=$1
    local tmp_dir="$2"
    local timestamp="$3"
    local start_time=$(date +%s)
    
    while true; do
        if [ -f "$tmp_dir/sync_status-$timestamp.tmp" ]; then
            local completed=$(wc -l < "$tmp_dir/sync_status-$timestamp.tmp" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            
            if [ "$completed" -ge "$total_tables" ]; then
                break
            fi
            
            log "INFO" "Progress: $completed/$total_tables tables completed (${elapsed}s elapsed)"
        fi
        sleep ${PROGRESS_REPORT_INTERVAL:-5}
    done
}

# === TABLE DISCOVERY FUNCTION ===
discover_tables() {
    local DB="$1"
    local tables_file="$2"
    
    log "INFO" "Discovering tables in database: $DB"
    
    # Get list of tables from remote database
    local discover_cmd="mysql -h\"$REMOTE_HOST\" -P\"${REMOTE_PORT:-3306}\" -u\"$REMOTE_USER\" -p\"$REMOTE_PASS\""
    discover_cmd="$discover_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    discover_cmd="$discover_cmd -e \"USE $DB; SHOW TABLES;\" 2>/dev/null | tail -n +2"
    
    eval "$discover_cmd" > "$tables_file"
    
    if [ $? -ne 0 ] || [ ! -s "$tables_file" ]; then
        log "ERROR" "Failed to discover tables in database: $DB"
        return 1
    fi
    
    local table_count=$(wc -l < "$tables_file")
    log "INFO" "Discovered $table_count tables in database: $DB"
    return 0
}

# === MAIN SCRIPT ===

# Initialize configuration
log "INFO" "Initializing Database Migration Toolkit - Multi-threaded Table Sync"
if ! init_config "$PROJECT_ROOT/config/config.env"; then
    log "ERROR" "Failed to initialize configuration"
    exit 1
fi

# Parse table sync configuration
declare -a SYNC_CONFIG=()
if ! parse_table_sync_config SYNC_CONFIG; then
    log "ERROR" "No table sync configuration found"
    log "ERROR" "Please set TABLE_SYNC_CONFIG or TABLE_SYNC_CONFIG_MULTILINE in your config/config.env file"
    log "ERROR" "Example: TABLE_SYNC_CONFIG=\"source_db:target_db:table1,table2|another_db:local_another:*\""
    exit 1
fi

# Create timestamp for this run
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SCRIPT_NAME="multi_thread_table_sync"

# Directory structure from configuration
DATA_DIR="${PROJECT_ROOT}/${BACKUP_DIR:-data}"
BACKUP_DIR="$DATA_DIR/backups/$SCRIPT_NAME"
TMP_DIR="$DATA_DIR/tmp/$SCRIPT_NAME"
LOG_DIR="$DATA_DIR/logs"

# Create directory structure
mkdir -p "$BACKUP_DIR" "$TMP_DIR" "$LOG_DIR"

# Ensure proper permissions for directories
for dir in "$BACKUP_DIR" "$TMP_DIR" "$LOG_DIR"; do
    if [ ! -w "$dir" ]; then
        log "ERROR" "Directory $dir is not writable. Attempting to fix permissions..."
        chmod 755 "$dir" 2>/dev/null || {
            log "ERROR" "Cannot fix permissions for $dir. Please run: sudo chown -R \$USER:\$USER $DATA_DIR"
            exit 1
        }
    fi
done

# Clean up old temporary files (older than 7 days)
find "$TMP_DIR" -name "*.tmp" -mtime +7 -delete 2>/dev/null || true
find "$TMP_DIR" -name "*_error-*.log" -mtime +7 -delete 2>/dev/null || true

# Validation
if [ ${#SYNC_CONFIG[@]} -eq 0 ]; then
    log "ERROR" "No databases/tables specified for synchronization"
    exit 1
fi

log "INFO" "Starting MULTI-THREADED table synchronization process..."
log "INFO" "Session timestamp: $TIMESTAMP"
log "INFO" "Remote host: ${REMOTE_HOST}:${REMOTE_PORT:-3306}"
log "INFO" "Sync configuration entries: ${#SYNC_CONFIG[@]}"
log "INFO" "Local DB prefix: ${LOCAL_DB_PREFIX:-none}"
log "INFO" "Drop existing tables: $(should_drop_existing_tables && echo "true" || echo "false")"
log "INFO" "Backup directory: $BACKUP_DIR"
log "INFO" "Temporary directory: $TMP_DIR"
log "INFO" "Maximum concurrent threads: ${MAX_THREADS:-4}"
log "INFO" "Retry attempts per table: ${MAX_RETRY_ATTEMPTS:-3}"
log "INFO" "Retry delay: ${RETRY_DELAY:-10}s"

# Parse configuration and build table list
declare -a TABLE_LIST=()
for config in "${SYNC_CONFIG[@]}"; do
    # Count colons to determine format
    colon_count=$(echo "$config" | tr -cd ':' | wc -c)
    
    if [ "$colon_count" -eq 2 ]; then
        # New format: source_db:target_db:tables
        IFS=':' read -r source_db target_db table_spec <<< "$config"
    elif [ "$colon_count" -eq 1 ]; then
        # Legacy format: source_db:tables (auto-generate target_db)
        IFS=':' read -r source_db table_spec <<< "$config"
        target_db=$(get_local_database_name "$source_db")
    else
        log "ERROR" "Invalid config format: $config. Expected 'source_db:target_db:tables' or 'source_db:tables'"
        continue
    fi
    
    if [ "$table_spec" = "*" ]; then
        # Auto-discover tables
        tables_file="$TMP_DIR/${source_db}_tables-$TIMESTAMP.tmp"
        if discover_tables "$source_db" "$tables_file"; then
            while IFS= read -r table; do
                # Skip empty lines
                if [ -n "$table" ]; then
                    TABLE_LIST+=("$source_db:$target_db:$table")
                fi
            done < "$tables_file"
            rm -f "$tables_file"
        else
            log "WARN" "Skipping database $source_db due to table discovery failure"
        fi
    else
        # Use specified tables
        IFS=',' read -ra tables <<< "$table_spec"
        for table in "${tables[@]}"; do
            # Trim whitespace
            table=$(echo "$table" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$table" ]; then
                TABLE_LIST+=("$source_db:$target_db:$table")
            fi
        done
    fi
done

total_tables=${#TABLE_LIST[@]}
log "INFO" "Total tables to sync: $total_tables"

if [ $total_tables -eq 0 ]; then
    log "ERROR" "No tables found to synchronize"
    exit 1
fi

# Show table list in debug mode
if is_debug_mode; then
    log "DEBUG" "Table sync list:"
    for table_config in "${TABLE_LIST[@]}"; do
        IFS=':' read -r source_db target_db table_name <<< "$table_config"
        log "DEBUG" "  - $source_db.$table_name -> $target_db"
    done
fi

# Record start time
SYNC_START_TIME=$(date +%s)

# Start progress monitor in background
monitor_progress $total_tables "$TMP_DIR" "$TIMESTAMP" &
MONITOR_PID=$!

# Array to store background process IDs
declare -a PIDS=()
active_threads=0

# Process tables with thread limiting
for table_config in "${TABLE_LIST[@]}"; do
    IFS=':' read -r source_db target_db table_name <<< "$table_config"
    
    # Wait if we've reached the maximum number of threads
    while [ $active_threads -ge ${MAX_THREADS:-4} ]; do
        # Check if any background jobs have finished
        for i in "${!PIDS[@]}"; do
            if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
                # Process has finished, remove from array
                unset PIDS[$i]
                ((active_threads--))
            fi
        done
        
        # Rebuild array to remove empty slots
        PIDS=("${PIDS[@]}")
        
        # Small delay to prevent busy waiting
        sleep 0.5
    done
    
    # Start table sync in background
    log "INFO" "Starting sync for table: $source_db.$table_name -> $target_db (Thread $((active_threads + 1))/${MAX_THREADS:-4})"
    sync_table "$source_db" "$target_db" "$table_name" "$BACKUP_DIR" "$TMP_DIR" "$TIMESTAMP" &
    PIDS+=($!)
    ((active_threads++))
done

# Wait for all background processes to complete
log "INFO" "All tables queued. Waiting for completion..."
for pid in "${PIDS[@]}"; do
    wait "$pid"
done

# Stop progress monitor
kill $MONITOR_PID 2>/dev/null
wait $MONITOR_PID 2>/dev/null

# Calculate total execution time
SYNC_END_TIME=$(date +%s)
TOTAL_DURATION=$((SYNC_END_TIME - SYNC_START_TIME))

# === FINAL REPORT ===
log "INFO" "All table synchronization processes completed"
log "INFO" "Total execution time: ${TOTAL_DURATION}s"

if [ -f "$TMP_DIR/sync_status-$TIMESTAMP.tmp" ]; then
    successful=$(grep -c "^SUCCESS:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
    failed=$(grep -c "^FAILED:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
    
    log "INFO" "FINAL SUMMARY:"
    log "INFO" "  ✓ Successful: $successful tables"
    log "INFO" "  ✗ Failed: $failed tables"
    
    if [ "$successful" -gt 0 ]; then
        log "INFO" "Successfully synchronized tables:"
        grep "^SUCCESS:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp" | while IFS=':' read -r status source_db target_db table duration attempt timestamp; do
            if [ -n "$attempt" ]; then
                log "INFO" "  - $source_db.$table -> $target_db (completed in $duration, attempt $attempt) -> ${source_db}_${table}-${timestamp}.sql"
            else
                log "INFO" "  - $source_db.$table -> $target_db (completed in $duration) -> ${source_db}_${table}-${timestamp}.sql"
            fi
        done
    fi
    
    if [ "$failed" -gt 0 ]; then
        log "WARN" "Failed tables:"
        grep "^FAILED:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp" | while IFS=':' read -r status source_db target_db table attempts timestamp; do
            log "WARN" "  - $source_db.$table -> $target_db (failed after $attempts attempts)"
        done
    fi
    
    # Show error summary if errors occurred
    if [ -f "$TMP_DIR/error_log-$TIMESTAMP.tmp" ]; then
        log "INFO" "Error Summary:"
        dump_errors=$(grep -c "^DUMP_ERROR:" "$TMP_DIR/error_log-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
        import_errors=$(grep -c "^IMPORT_ERROR:" "$TMP_DIR/error_log-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
        
        log "INFO" "  - Dump errors: $dump_errors"
        log "INFO" "  - Import errors: $import_errors"
        log "INFO" "  - Detailed errors logged to: $TMP_DIR/error_log-$TIMESTAMP.tmp"
    fi
    
    # Show file locations
    log "INFO" "Generated Files:"
    log "INFO" "  - Table dump files: $BACKUP_DIR/*_*-$TIMESTAMP.sql"
    log "INFO" "  - Status file: $TMP_DIR/sync_status-$TIMESTAMP.tmp"
    log "INFO" "  - Error log: $TMP_DIR/error_log-$TIMESTAMP.tmp"
else
    log "WARN" "No status file found - unable to generate detailed report"
fi

# Clean up old backups if retention policy is set
if [ -n "${BACKUP_RETENTION_DAYS:-}" ] && [ "${BACKUP_RETENTION_DAYS}" -gt 0 ]; then
    log "INFO" "Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days"
    find "$BACKUP_DIR" -name "*.sql" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
    log "INFO" "Backup cleanup completed"
fi

# Send notifications if configured
if [ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" = "true" ] && command -v mail >/dev/null 2>&1; then
    local status_msg="Multi-threaded table synchronization completed"
    if [ "$failed" -gt 0 ]; then
        status_msg="$status_msg with $failed failures"
    fi
    echo "$status_msg at $(date)" | \
    mail -s "Multi-threaded Table Sync Complete" "${EMAIL_TO:-admin@localhost}"
fi

if [ "${ENABLE_WEBHOOK_NOTIFICATIONS:-false}" = "true" ] && [ -n "${WEBHOOK_URL:-}" ] && command -v curl >/dev/null 2>&1; then
    local webhook_data="{\"text\":\"Multi-threaded table synchronization completed. Success: $successful, Failed: $failed\"}"
    curl -X POST -H "Content-Type: application/json" \
         -d "$webhook_data" \
         "${WEBHOOK_URL}" >/dev/null 2>&1 || true
fi

log "INFO" "Multi-threaded table synchronization completed!"
log "INFO" "Check the logs above for any errors or warnings"

# Exit with error code if any tables failed
if [ -f "$TMP_DIR/sync_status-$TIMESTAMP.tmp" ] && grep -q "^FAILED:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp"; then
    exit 1
fi
#!/bin/bash

# === MULTI-THREADED DATABASE SYNCHRONIZATION SCRIPT ===
# This script processes multiple databases in parallel for faster synchronization
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
    shift 2
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local thread_id=$(echo $BASHPID | tail -c 5)
    echo "[$timestamp] [$level] [DB:$db] [Thread-$thread_id] $message"
}

# === DATABASE SYNC FUNCTION WITH RETRY (runs in background) ===
sync_database() {
    local DB="$1"
    local BACKUP_DIR="$2"
    local TMP_DIR="$3"
    local TIMESTAMP="$4"
    local start_time=$(date +%s)
    local attempt=1
    local max_attempts=${MAX_RETRY_ATTEMPTS:-3}
    
    thread_log "INFO" "$DB" "Starting database synchronization (max attempts: $max_attempts)..."
    
    while [ $attempt -le $max_attempts ]; do
        thread_log "INFO" "$DB" "Attempt $attempt/$max_attempts: Starting sync process..."
        
        # Step 1: Dump database
        if sync_dump_database "$DB" "$BACKUP_DIR" "$TMP_DIR" "$TIMESTAMP" $attempt; then
            # Step 2: Prepare local database
            if sync_prepare_local_db "$DB" "$TMP_DIR" "$TIMESTAMP" $attempt; then
                # Step 3: Import database
                if sync_import_database "$DB" "$BACKUP_DIR" "$TMP_DIR" "$TIMESTAMP" $attempt; then
                    local end_time=$(date +%s)
                    local duration=$((end_time - start_time))
                    thread_log "SUCCESS" "$DB" "Database synchronization completed successfully in ${duration}s (attempt $attempt/$max_attempts)"
                    echo "SUCCESS:$DB:${duration}s:$attempt:$TIMESTAMP" >> "$TMP_DIR/sync_status-$TIMESTAMP.tmp"
                    return 0
                fi
            fi
        fi
        
        # If we reach here, something failed
        if [ $attempt -lt $max_attempts ]; then
            local retry_delay=${RETRY_DELAY:-10}
            thread_log "WARN" "$DB" "Attempt $attempt failed. Retrying in ${retry_delay}s..."
            sleep $retry_delay
        else
            thread_log "ERROR" "$DB" "All $max_attempts attempts failed. Giving up."
            echo "FAILED:$DB:$attempt:$TIMESTAMP" >> "$TMP_DIR/sync_status-$TIMESTAMP.tmp"
            return 1
        fi
        
        ((attempt++))
    done
}

# === DUMP DATABASE FUNCTION ===
sync_dump_database() {
    local DB="$1"
    local BACKUP_DIR="$2"
    local TMP_DIR="$3"
    local TIMESTAMP="$4"
    local attempt="$5"
    local error_file="$TMP_DIR/${DB}_dump_error-$TIMESTAMP.log"
    local backup_file="$BACKUP_DIR/${DB}-${TIMESTAMP}.sql"
    
    thread_log "INFO" "$DB" "Step 1/3: Dumping $DB from remote server (attempt $attempt)..."
    thread_log "INFO" "$DB" "Backup file: $backup_file"
    
    # Clear previous error log
    > "$error_file"
    
    # Get mysqldump options from configuration
    local dump_options=$(get_mysqldump_options)
    
    # Build mysqldump command
    local dump_cmd="mysqldump -h\"$REMOTE_HOST\" -P\"${REMOTE_PORT:-3306}\" -u\"$REMOTE_USER\" -p\"$REMOTE_PASS\""
    dump_cmd="$dump_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\" --single-transaction"
    dump_cmd="$dump_cmd $dump_options \"$DB\""
    
    if is_debug_mode; then
        thread_log "DEBUG" "$DB" "Dump command: $dump_cmd"
    fi
    
    # Execute dump command
    eval "$dump_cmd" > "$backup_file" 2>"$error_file"

    if [ $? -ne 0 ]; then
        local error_msg=$(cat "$error_file" 2>/dev/null | head -n 3 | tr '\n' ' ')
        # Filter out password warnings (they're not real errors)
        if echo "$error_msg" | grep -q "Using a password on the command line interface can be insecure" && [ -s "$backup_file" ]; then
            thread_log "WARN" "$DB" "Dump completed with password warning (attempt $attempt)"
        else
            thread_log "ERROR" "$DB" "Dump failed (attempt $attempt): ${error_msg}"
            echo "DUMP_ERROR:$DB:attempt_$attempt:${error_msg}:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
            return 1
        fi
    fi

    # Verify dump file was created and has content
    if [ ! -f "$backup_file" ] || [ ! -s "$backup_file" ]; then
        thread_log "ERROR" "$DB" "Dump file is empty or missing (attempt $attempt)"
        echo "DUMP_ERROR:$DB:attempt_$attempt:Empty or missing dump file:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi

    local dump_size=$(du -h "$backup_file" | cut -f1)
    thread_log "SUCCESS" "$DB" "Database dump completed successfully (Size: $dump_size, attempt $attempt)"
    rm -f "$error_file"  # Clean up error file on success
    return 0
}

# === PREPARE LOCAL DATABASE FUNCTION ===
sync_prepare_local_db() {
    local DB="$1"
    local TMP_DIR="$2"
    local TIMESTAMP="$3"
    local attempt="$4"
    local error_file="$TMP_DIR/${DB}_prep_error-$TIMESTAMP.log"
    
    # Generate local database name using configuration
    local LOCAL_DB_NAME=$(get_local_database_name "$DB")
    
    thread_log "INFO" "$DB" "Step 2/3: Preparing local database $LOCAL_DB_NAME (attempt $attempt)..."
    
    # Clear previous error log
    > "$error_file"
    
    # Drop existing database
    thread_log "INFO" "$DB" "Dropping existing local database $LOCAL_DB_NAME (if exists)..."
    local drop_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    drop_cmd="$drop_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    drop_cmd="$drop_cmd -e 'DROP DATABASE IF EXISTS \`$LOCAL_DB_NAME\`'"
    
    eval "$drop_cmd" 2>"$error_file"
    if [ $? -ne 0 ]; then
        local error_msg=$(cat "$error_file" 2>/dev/null | head -n 2 | tr '\n' ' ')
        thread_log "ERROR" "$DB" "Failed to drop database (attempt $attempt): ${error_msg}"
        echo "PREP_ERROR:$DB:attempt_$attempt:Drop failed - ${error_msg}:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi
    
    # Create fresh database
    thread_log "INFO" "$DB" "Creating fresh local database $LOCAL_DB_NAME..."
    local create_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    create_cmd="$create_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    create_cmd="$create_cmd -e 'CREATE DATABASE \`$LOCAL_DB_NAME\`"
    
    # Add character set and collation if configured
    if [ -n "${CHARSET:-}" ]; then
        create_cmd="$create_cmd CHARACTER SET ${CHARSET}"
    fi
    if [ -n "${COLLATION:-}" ]; then
        create_cmd="$create_cmd COLLATE ${COLLATION}"
    fi
    create_cmd="$create_cmd'"
    
    eval "$create_cmd" 2>"$error_file"
    if [ $? -ne 0 ]; then
        local error_msg=$(cat "$error_file" 2>/dev/null | head -n 2 | tr '\n' ' ')
        thread_log "ERROR" "$DB" "Failed to create database (attempt $attempt): ${error_msg}"
        echo "PREP_ERROR:$DB:attempt_$attempt:Create failed - ${error_msg}:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi
    
    rm -f "$error_file"  # Clean up error file on success
    return 0
}

# === IMPORT DATABASE FUNCTION ===
sync_import_database() {
    local DB="$1"
    local BACKUP_DIR="$2"
    local TMP_DIR="$3"
    local TIMESTAMP="$4"
    local attempt="$5"
    local error_file="$TMP_DIR/${DB}_import_error-$TIMESTAMP.log"
    local backup_file="$BACKUP_DIR/${DB}-${TIMESTAMP}.sql"
    
    # Generate local database name using configuration
    local LOCAL_DB_NAME=$(get_local_database_name "$DB")
    
    thread_log "INFO" "$DB" "Step 3/3: Importing dump into local database $LOCAL_DB_NAME (attempt $attempt)..."
    thread_log "INFO" "$DB" "Importing from: $backup_file"
    
    # Clear previous error log
    > "$error_file"
    
    # Import dump into local DB
    local import_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    import_cmd="$import_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    
    # Set SQL mode if configured
    if [ -n "${SQL_MODE:-}" ]; then
        import_cmd="$import_cmd --init-command=\"SET SESSION sql_mode='${SQL_MODE}'\""
    fi
    
    import_cmd="$import_cmd \"$LOCAL_DB_NAME\""
    
    eval "$import_cmd" < "$backup_file" 2>"$error_file"
    if [ $? -ne 0 ]; then
        local error_msg=$(cat "$error_file" 2>/dev/null | head -n 3 | tr '\n' ' ')
        thread_log "ERROR" "$DB" "Import failed (attempt $attempt): ${error_msg}"
        echo "IMPORT_ERROR:$DB:attempt_$attempt:${error_msg}:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi
    
    # Verify import by checking if tables exist
    local table_count_cmd="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    table_count_cmd="$table_count_cmd --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    table_count_cmd="$table_count_cmd \"$LOCAL_DB_NAME\" -e 'SHOW TABLES;' 2>/dev/null | wc -l"
    
    local table_count=$(eval "$table_count_cmd")
    if [ "${table_count:-0}" -le 1 ]; then
        thread_log "ERROR" "$DB" "Import verification failed - no tables found (attempt $attempt)"
        echo "IMPORT_ERROR:$DB:attempt_$attempt:No tables found after import:$TIMESTAMP" >> "$TMP_DIR/error_log-$TIMESTAMP.tmp"
        return 1
    fi
    
    thread_log "SUCCESS" "$DB" "Database import completed successfully ($((table_count - 1)) tables, attempt $attempt)"
    rm -f "$error_file"  # Clean up error file on success
    return 0
}

# === PROGRESS MONITOR FUNCTION ===
monitor_progress() {
    local total_dbs=$1
    local tmp_dir="$2"
    local timestamp="$3"
    local start_time=$(date +%s)
    
    while true; do
        if [ -f "$tmp_dir/sync_status-$timestamp.tmp" ]; then
            local completed=$(wc -l < "$tmp_dir/sync_status-$timestamp.tmp" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            
            if [ "$completed" -ge "$total_dbs" ]; then
                break
            fi
            
            log "INFO" "Progress: $completed/$total_dbs databases completed (${elapsed}s elapsed)"
        fi
        sleep ${PROGRESS_REPORT_INTERVAL:-5}
    done
}

# === MAIN SCRIPT ===

# Initialize configuration
log "INFO" "Initializing Database Migration Toolkit - Multi-threaded Sync"
if ! init_config "$PROJECT_ROOT/config/config.env"; then
    log "ERROR" "Failed to initialize configuration"
    exit 1
fi

# Parse database list from configuration
declare -a DATABASES=()
if ! parse_database_list DATABASES; then
    log "ERROR" "No databases configured for synchronization"
    log "ERROR" "Please set SYNC_DATABASES in your config/config.env file"
    log "ERROR" "Example: SYNC_DATABASES=\"database1,database2,database3\""
    exit 1
fi

# Create timestamp for this run
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
SCRIPT_NAME="multi_thread_sync"

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
if [ ${#DATABASES[@]} -eq 0 ]; then
    log "ERROR" "No databases specified for synchronization"
    exit 1
fi

log "INFO" "Starting MULTI-THREADED database synchronization process..."
log "INFO" "Session timestamp: $TIMESTAMP"
log "INFO" "Remote host: ${REMOTE_HOST}:${REMOTE_PORT:-3306}"
log "INFO" "Databases to sync: ${DATABASES[*]}"
log "INFO" "Backup directory: $BACKUP_DIR"
log "INFO" "Temporary directory: $TMP_DIR"
log "INFO" "Maximum concurrent threads: ${MAX_THREADS:-4}"
log "INFO" "Retry attempts per database: ${MAX_RETRY_ATTEMPTS:-3}"
log "INFO" "Retry delay: ${RETRY_DELAY:-10}s"
log "INFO" "Total databases: ${#DATABASES[@]}"

# Record start time
SYNC_START_TIME=$(date +%s)

# Start progress monitor in background
monitor_progress ${#DATABASES[@]} "$TMP_DIR" "$TIMESTAMP" &
MONITOR_PID=$!

# Array to store background process IDs
declare -a PIDS=()
active_threads=0

# Process databases with thread limiting
for DB in "${DATABASES[@]}"; do
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
    
    # Start database sync in background
    log "INFO" "Starting sync for database: $DB (Thread $((active_threads + 1))/${MAX_THREADS:-4})"
    sync_database "$DB" "$BACKUP_DIR" "$TMP_DIR" "$TIMESTAMP" &
    PIDS+=($!)
    ((active_threads++))
done

# Wait for all background processes to complete
log "INFO" "All databases queued. Waiting for completion..."
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
log "INFO" "All database synchronization processes completed"
log "INFO" "Total execution time: ${TOTAL_DURATION}s"

if [ -f "$TMP_DIR/sync_status-$TIMESTAMP.tmp" ]; then
    local successful=$(grep -c "^SUCCESS:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
    local failed=$(grep -c "^FAILED:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
    
    log "INFO" "FINAL SUMMARY:"
    log "INFO" "  ✓ Successful: $successful databases"
    log "INFO" "  ✗ Failed: $failed databases"
    
    if [ "$successful" -gt 0 ]; then
        log "INFO" "Successfully synchronized databases:"
        grep "^SUCCESS:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp" | while IFS=':' read -r status db duration attempt timestamp; do
            local local_db_name=$(get_local_database_name "$db")
            if [ -n "$attempt" ]; then
                log "INFO" "  - $db -> $local_db_name (completed in $duration, attempt $attempt) -> ${db}-${timestamp}.sql"
            else
                log "INFO" "  - $db -> $local_db_name (completed in $duration) -> ${db}-${timestamp}.sql"
            fi
        done
    fi
    
    if [ "$failed" -gt 0 ]; then
        log "WARN" "Failed databases:"
        grep "^FAILED:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp" | while IFS=':' read -r status db attempts timestamp; do
            log "WARN" "  - $db (failed after $attempts attempts)"
        done
    fi
    
    # Show error summary if errors occurred
    if [ -f "$TMP_DIR/error_log-$TIMESTAMP.tmp" ]; then
        log "INFO" "Error Summary:"
        local dump_errors=$(grep -c "^DUMP_ERROR:" "$TMP_DIR/error_log-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
        local prep_errors=$(grep -c "^PREP_ERROR:" "$TMP_DIR/error_log-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
        local import_errors=$(grep -c "^IMPORT_ERROR:" "$TMP_DIR/error_log-$TIMESTAMP.tmp" 2>/dev/null || echo "0")
        
        log "INFO" "  - Dump errors: $dump_errors"
        log "INFO" "  - Preparation errors: $prep_errors"
        log "INFO" "  - Import errors: $import_errors"
        log "INFO" "  - Detailed errors logged to: $TMP_DIR/error_log-$TIMESTAMP.tmp"
    fi
    
    # Show file locations
    log "INFO" "Generated Files:"
    log "INFO" "  - Backup files: $BACKUP_DIR/*-$TIMESTAMP.sql"
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
    local status_msg="Multi-threaded database synchronization completed"
    if [ "$failed" -gt 0 ]; then
        status_msg="$status_msg with $failed failures"
    fi
    echo "$status_msg at $(date)" | \
    mail -s "Multi-threaded DB Sync Complete" "${EMAIL_TO:-admin@localhost}"
fi

if [ "${ENABLE_WEBHOOK_NOTIFICATIONS:-false}" = "true" ] && [ -n "${WEBHOOK_URL:-}" ] && command -v curl >/dev/null 2>&1; then
    local webhook_data="{\"text\":\"Multi-threaded database synchronization completed. Success: $successful, Failed: $failed\"}"
    curl -X POST -H "Content-Type: application/json" \
         -d "$webhook_data" \
         "${WEBHOOK_URL}" >/dev/null 2>&1 || true
fi

log "INFO" "Multi-threaded database synchronization completed!"
log "INFO" "Check the logs above for any errors or warnings"

# Exit with error code if any databases failed
if [ -f "$TMP_DIR/sync_status-$TIMESTAMP.tmp" ] && grep -q "^FAILED:" "$TMP_DIR/sync_status-$TIMESTAMP.tmp"; then
    exit 1
fi
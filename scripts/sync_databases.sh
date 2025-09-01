#!/bin/bash

# ==============================================
# Simple Database Synchronization Script
# ==============================================
# This script synchronizes databases from a remote source to local MySQL
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
    echo "[$timestamp] [$level] $message"
}

# === MAIN SCRIPT ===

# Initialize configuration
log "INFO" "Initializing Database Migration Toolkit - Simple Sync"
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

# Create backup directory from configuration
BACKUP_DIR="${PROJECT_ROOT}/${BACKUP_DIR:-data/backups}"
mkdir -p "$BACKUP_DIR"

log "INFO" "Starting database synchronization process..."
log "INFO" "Remote host: ${REMOTE_HOST}:${REMOTE_PORT:-3306}"
log "INFO" "Databases to sync: ${DATABASES[*]}"
log "INFO" "Backup directory: $BACKUP_DIR"
log "INFO" "Local database prefix: ${LOCAL_DB_PREFIX:-none}"

# Get mysqldump options from configuration
DUMP_OPTIONS=$(get_mysqldump_options)
log "INFO" "Using mysqldump options: $DUMP_OPTIONS"

for DB in "${DATABASES[@]}"; do
    log "INFO" "Processing database: $DB"
    log "INFO" "Step 1/3: Dumping $DB from remote server..."

    # Generate local database name
    LOCAL_DB_NAME=$(get_local_database_name "$DB")
    
    # Dump from remote DB with configured options
    DUMP_CMD="mysqldump -h\"$REMOTE_HOST\" -P\"${REMOTE_PORT:-3306}\" -u\"$REMOTE_USER\" -p\"$REMOTE_PASS\""
    DUMP_CMD="$DUMP_CMD --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\" --single-transaction"
    DUMP_CMD="$DUMP_CMD $DUMP_OPTIONS \"$DB\""
    
    if is_debug_mode; then
        log "DEBUG" "Dump command: $DUMP_CMD > \"$BACKUP_DIR/$DB.sql\""
    fi
    
    eval "$DUMP_CMD" > "$BACKUP_DIR/$DB.sql" 2>"$BACKUP_DIR/${DB}_dump_error.log"

    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to dump database $DB from remote server"
        if [ -f "$BACKUP_DIR/${DB}_dump_error.log" ]; then
            log "ERROR" "Error details: $(head -n 3 "$BACKUP_DIR/${DB}_dump_error.log" | tr '\n' ' ')"
        fi
        log "WARN" "Skipping $DB and continuing with next database"
        continue
    fi

    dump_size=$(du -h "$BACKUP_DIR/$DB.sql" | cut -f1)
    log "SUCCESS" "Database dump completed successfully (Size: $dump_size)"
    
    # Clean up successful dump error log
    rm -f "$BACKUP_DIR/${DB}_dump_error.log"
    
    log "INFO" "Step 2/3: Preparing local database $LOCAL_DB_NAME..."

    # Drop and create database
    log "INFO" "Dropping existing local database $LOCAL_DB_NAME (if exists)..."
    DROP_CMD="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    DROP_CMD="$DROP_CMD --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    DROP_CMD="$DROP_CMD -e 'DROP DATABASE IF EXISTS \`$LOCAL_DB_NAME\`'"
    
    if is_debug_mode; then
        log "DEBUG" "Drop command: $DROP_CMD"
    fi
    
    eval "$DROP_CMD" 2>"$BACKUP_DIR/${DB}_drop_error.log"
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to drop existing database $LOCAL_DB_NAME"
        if [ -f "$BACKUP_DIR/${DB}_drop_error.log" ]; then
            log "ERROR" "Error details: $(head -n 2 "$BACKUP_DIR/${DB}_drop_error.log" | tr '\n' ' ')"
        fi
        continue
    fi
    rm -f "$BACKUP_DIR/${DB}_drop_error.log"
    
    log "INFO" "Creating fresh local database $LOCAL_DB_NAME..."
    CREATE_CMD="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    CREATE_CMD="$CREATE_CMD --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    CREATE_CMD="$CREATE_CMD -e 'CREATE DATABASE \`$LOCAL_DB_NAME\`"
    
    # Add character set and collation if configured
    if [ -n "${CHARSET:-}" ]; then
        CREATE_CMD="$CREATE_CMD CHARACTER SET ${CHARSET}"
    fi
    if [ -n "${COLLATION:-}" ]; then
        CREATE_CMD="$CREATE_CMD COLLATE ${COLLATION}"
    fi
    CREATE_CMD="$CREATE_CMD'"
    
    if is_debug_mode; then
        log "DEBUG" "Create command: $CREATE_CMD"
    fi
    
    eval "$CREATE_CMD" 2>"$BACKUP_DIR/${DB}_create_error.log"
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create database $LOCAL_DB_NAME"
        if [ -f "$BACKUP_DIR/${DB}_create_error.log" ]; then
            log "ERROR" "Error details: $(head -n 2 "$BACKUP_DIR/${DB}_create_error.log" | tr '\n' ' ')"
        fi
        continue
    fi
    rm -f "$BACKUP_DIR/${DB}_create_error.log"

    log "INFO" "Step 3/3: Importing dump into local database $LOCAL_DB_NAME..."
    
    # Import dump into local DB
    IMPORT_CMD="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
    IMPORT_CMD="$IMPORT_CMD --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
    
    # Set SQL mode if configured
    if [ -n "${SQL_MODE:-}" ]; then
        IMPORT_CMD="$IMPORT_CMD --init-command=\"SET SESSION sql_mode='${SQL_MODE}'\""
    fi
    
    IMPORT_CMD="$IMPORT_CMD \"$LOCAL_DB_NAME\""
    
    if is_debug_mode; then
        log "DEBUG" "Import command: $IMPORT_CMD < \"$BACKUP_DIR/$DB.sql\""
    fi
    
    eval "$IMPORT_CMD" < "$BACKUP_DIR/$DB.sql" 2>"$BACKUP_DIR/${DB}_import_error.log"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to import database $DB into local MySQL database $LOCAL_DB_NAME"
        if [ -f "$BACKUP_DIR/${DB}_import_error.log" ]; then
            log "ERROR" "Error details: $(head -n 3 "$BACKUP_DIR/${DB}_import_error.log" | tr '\n' ' ')"
        fi
        log "WARN" "Database $DB synchronization incomplete"
    else
        log "SUCCESS" "Database $DB synchronization completed successfully"
        log "INFO" "Local database $LOCAL_DB_NAME is now up to date"
        
        # Clean up successful import error log
        rm -f "$BACKUP_DIR/${DB}_import_error.log"
        
        # Verify import by counting tables
        TABLE_COUNT_CMD="mysql -h\"${LOCAL_HOST:-localhost}\" -P\"${LOCAL_PORT:-3306}\" -u\"$LOCAL_USER\" -p\"$LOCAL_PASS\""
        TABLE_COUNT_CMD="$TABLE_COUNT_CMD --connect-timeout=\"${MYSQL_CONNECT_TIMEOUT:-60}\""
        TABLE_COUNT_CMD="$TABLE_COUNT_CMD \"$LOCAL_DB_NAME\" -e 'SHOW TABLES;' 2>/dev/null | wc -l"
        
        table_count=$(eval "$TABLE_COUNT_CMD")
        if [ "${table_count:-0}" -gt 1 ]; then
            log "INFO" "Import verified: $((table_count - 1)) tables found in $LOCAL_DB_NAME"
        fi
    fi
    
    log "INFO" "Finished processing database: $DB -> $LOCAL_DB_NAME"
    echo "----------------------------------------"
done

log "INFO" "Database synchronization process completed"
log "INFO" "All ${#DATABASES[@]} databases have been processed"
log "INFO" "Backup files location: $BACKUP_DIR"

# Clean up old backups if retention policy is set
if [ -n "${BACKUP_RETENTION_DAYS:-}" ] && [ "${BACKUP_RETENTION_DAYS}" -gt 0 ]; then
    log "INFO" "Cleaning up backups older than ${BACKUP_RETENTION_DAYS} days"
    find "$BACKUP_DIR" -name "*.sql" -mtime +${BACKUP_RETENTION_DAYS} -delete 2>/dev/null || true
    log "INFO" "Backup cleanup completed"
fi

# Send notifications if configured
if [ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" = "true" ] && command -v mail >/dev/null 2>&1; then
    echo "Database synchronization completed at $(date)" | \
    mail -s "Database Sync Complete" "${EMAIL_TO:-admin@localhost}"
fi

if [ "${ENABLE_WEBHOOK_NOTIFICATIONS:-false}" = "true" ] && [ -n "${WEBHOOK_URL:-}" ] && command -v curl >/dev/null 2>&1; then
    curl -X POST -H "Content-Type: application/json" \
         -d '{"text":"Database synchronization completed successfully"}' \
         "${WEBHOOK_URL}" >/dev/null 2>&1 || true
fi

log "INFO" "Check the logs above for any errors or warnings"
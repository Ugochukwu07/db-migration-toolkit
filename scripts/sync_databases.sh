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

parse_safety_args "$@" || exit 1

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

# Safety guards + plan + confirmation (before anything is dumped or dropped)
plan_and_confirm_databases DATABASES

# Create backup directory from configuration
BACKUP_DIR="${PROJECT_ROOT}/${BACKUP_DIR:-data/backups}"
mkdir -p "$BACKUP_DIR"
secure_dirs "$BACKUP_DIR"
check_disk_for_databases "$BACKUP_DIR" DATABASES || exit 1

log "INFO" "Starting database synchronization process..."
log "INFO" "Remote host: ${REMOTE_HOST}:${REMOTE_PORT:-3306}"
log "INFO" "Databases to sync: ${DATABASES[*]}"
log "INFO" "Backup directory: $BACKUP_DIR"
log "INFO" "Local database prefix: ${LOCAL_DB_PREFIX:-none}"

# Get mysqldump options from configuration (split into an array, no eval)
declare -a DUMP_OPTS=()
read_dump_options DUMP_OPTS db
log "INFO" "Using mysqldump options: ${DUMP_OPTS[*]}"

FAILED_DBS=()
for DB in "${DATABASES[@]}"; do
    log "INFO" "Processing database: $DB"
    log "INFO" "Step 1/3: Dumping $DB from remote server..."

    # Generate local database name
    LOCAL_DB_NAME=$(get_local_database_name "$DB")
    
    DUMP_FILE="$BACKUP_DIR/$DB$(backup_ext)"
    if is_debug_mode; then
        log "DEBUG" "Dump command: mysqldump [remote connection] --single-transaction ${DUMP_OPTS[*]} $DB > \"$DUMP_FILE\""
    fi
    
    # Dump from remote DB with configured options (compressed + private)
    dump_to_file "$DUMP_FILE" "$BACKUP_DIR/${DB}_dump_error.log" remote_mysqldump --single-transaction "${DUMP_OPTS[@]}" "$DB"

    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to dump database $DB from remote server"
        if [ -f "$BACKUP_DIR/${DB}_dump_error.log" ]; then
            log "ERROR" "Error details: $(head -n 3 "$BACKUP_DIR/${DB}_dump_error.log" | tr '\n' ' ')"
        fi
        rm -f -- "$DUMP_FILE"
        log "WARN" "Skipping $DB and continuing with next database"
        FAILED_DBS+=("$DB")
        continue
    fi

    dump_size=$(du -h "$DUMP_FILE" | cut -f1)
    log "SUCCESS" "Database dump completed successfully (Size: $dump_size)"
    
    # Clean up successful dump error log
    rm -f "$BACKUP_DIR/${DB}_dump_error.log"
    
    log "INFO" "Step 2/3: Replacing local database $LOCAL_DB_NAME (existing data is snapshotted and restored on failure)..."
    SAFETY_FILE="$BACKUP_DIR/pre-sync_${DB}-$(date '+%Y%m%d_%H%M%S')$(backup_ext)"
    IMPORT_ERR="$BACKUP_DIR/${DB}_import_error.log"
    replace_local_database "$LOCAL_DB_NAME" "$DUMP_FILE" "$SAFETY_FILE" "$IMPORT_ERR"
    rc=$?
    
    if [ $rc -eq 0 ]; then
        log "SUCCESS" "Database $DB synchronization completed successfully"
        log "INFO" "Local database $LOCAL_DB_NAME is now up to date"
        rm -f -- "$IMPORT_ERR"
        table_count=$(local_mysql -N -B "$LOCAL_DB_NAME" -e 'SHOW TABLES;' 2>/dev/null | wc -l)
        log "INFO" "Import verified: $table_count tables found in $LOCAL_DB_NAME"
    else
        case $rc in
            2) log "ERROR" "Aborted: could not snapshot existing $LOCAL_DB_NAME; it was left untouched" ;;
            3) log "ERROR" "Import failed AND rollback failed for $LOCAL_DB_NAME" ;;
            *) log "ERROR" "Failed to import database $DB into local MySQL database $LOCAL_DB_NAME" ;;
        esac
        log "ERROR" "Error details: $(tail -n 4 "$IMPORT_ERR" | tr '\n' ' ')"
        log "WARN" "Database $DB synchronization incomplete"
        FAILED_DBS+=("$DB")
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
    cleanup_old_backups "$BACKUP_DIR" "${BACKUP_RETENTION_DAYS}"
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

if [ ${#FAILED_DBS[@]} -gt 0 ]; then
    log "ERROR" "${#FAILED_DBS[@]} database(s) failed: ${FAILED_DBS[*]}"
    exit 1
fi
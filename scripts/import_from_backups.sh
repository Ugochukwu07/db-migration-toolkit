#!/bin/bash

# ==============================================
# Import Database Backups Script
# ==============================================
# This script imports database backups from a specified directory
# Now uses externalized configuration from config.env

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the configuration loader
source "$SCRIPT_DIR/config_loader.sh"

# === MAIN SCRIPT ===

# Initialize configuration
echo "Initializing backup import process..."
if ! init_config "$PROJECT_ROOT/config/config.env"; then
    echo "Error: Failed to initialize configuration"
    exit 1
fi

# Use configured backup directory or fallback
BACKUP_DIR="${PROJECT_ROOT}/${IMPORT_BACKUP_DIR:-./backups}"
LOCAL_DB_PREFIX="${IMPORT_LOCAL_DB_PREFIX:-imported_}"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Error: Backup directory '$BACKUP_DIR' not found!"
    echo "Please check the IMPORT_BACKUP_DIR setting in your configuration."
    exit 1
fi

echo "Starting import from $BACKUP_DIR..."
echo "Local database prefix: $LOCAL_DB_PREFIX"
echo "Target host: ${LOCAL_HOST:-localhost}:${LOCAL_PORT:-3306}"

for SQL_FILE in "$BACKUP_DIR"/*.sql; do
    if [ ! -f "$SQL_FILE" ]; then
        continue # Skip if not a file (e.g. if no .sql files found)
    fi

    DB_NAME_WITH_EXT=$(basename "$SQL_FILE")
    DB_NAME="${DB_NAME_WITH_EXT%.sql}"
    LOCAL_DB_NAME="$LOCAL_DB_PREFIX$DB_NAME"

    echo "Processing $DB_NAME..."

    TEMP_SQL_FILE="${SQL_FILE}.tmp"
    cp "$SQL_FILE" "$TEMP_SQL_FILE"

    # Remove GTID and replication related commands
    sed -i '/SET @@GLOBAL.GTID_PURGED/d' "$TEMP_SQL_FILE"
    sed -i '/SET @@SESSION.SQL_LOG_BIN/d' "$TEMP_SQL_FILE"
    sed -i '/SET @@GLOBAL.GTID_EXECUTED/d' "$TEMP_SQL_FILE"
    sed -i '/CHANGE MASTER/d' "$TEMP_SQL_FILE"

    echo "Importing $DB_NAME into local database $LOCAL_DB_NAME..."

    if ! local_mysql -e "DROP DATABASE IF EXISTS $(sql_ident "$LOCAL_DB_NAME")"; then
        echo "❌ Failed to drop existing database $LOCAL_DB_NAME"
        rm "$TEMP_SQL_FILE"
        continue
    fi

    if ! local_mysql -e "$(create_database_sql "$LOCAL_DB_NAME")"; then
        echo "❌ Failed to create local database $LOCAL_DB_NAME"
        rm "$TEMP_SQL_FILE"
        continue
    fi

    # Create a temporary wrapper SQL file that disables binary logging
    WRAPPER_SQL_FILE="${TEMP_SQL_FILE}.wrapper"
    echo "SET SESSION sql_log_bin=0;" > "$WRAPPER_SQL_FILE"
    echo "SET SESSION foreign_key_checks=0;" >> "$WRAPPER_SQL_FILE"
    
    # Set SQL mode if configured
    if [ -n "${SQL_MODE:-}" ]; then
        echo "SET SESSION sql_mode='${SQL_MODE}';" >> "$WRAPPER_SQL_FILE"
    fi
    
    cat "$TEMP_SQL_FILE" >> "$WRAPPER_SQL_FILE"
    echo "SET SESSION sql_log_bin=1;" >> "$WRAPPER_SQL_FILE"

    # Import dump into local DB
    local_mysql "$LOCAL_DB_NAME" < "$WRAPPER_SQL_FILE"
    IMPORT_STATUS=$?

    rm "$TEMP_SQL_FILE" "$WRAPPER_SQL_FILE"

    if [ $IMPORT_STATUS -ne 0 ]; then
        echo "❌ Failed to import $DB_NAME into $LOCAL_DB_NAME"
    else
        echo "✅ $DB_NAME imported into $LOCAL_DB_NAME successfully."
        
        # Verify import by counting tables
        table_count=$(local_mysql -N -B "$LOCAL_DB_NAME" -e 'SHOW TABLES;' 2>/dev/null | wc -l)
        if [ "${table_count:-0}" -gt 0 ]; then
            echo "   Import verified: $table_count tables found"
        fi
    fi
done

echo "All done!"
echo "Import process completed from: $BACKUP_DIR"
echo "Local databases created with prefix: $LOCAL_DB_PREFIX"

# Send notifications if configured
if [ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" = "true" ] && command -v mail >/dev/null 2>&1; then
    echo "Backup import process completed at $(date)" | \
    mail -s "Database Import Complete" "${EMAIL_TO:-admin@localhost}"
fi

if [ "${ENABLE_WEBHOOK_NOTIFICATIONS:-false}" = "true" ] && [ -n "${WEBHOOK_URL:-}" ] && command -v curl >/dev/null 2>&1; then
    curl -X POST -H "Content-Type: application/json" \
         -d '{"text":"Database backup import process completed successfully"}' \
         "${WEBHOOK_URL}" >/dev/null 2>&1 || true
fi
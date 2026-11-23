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

parse_safety_args "$@" || exit 1

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

# Safety guards + plan + confirmation (before any database is dropped).
# There is no remote source here, so only the protected-schema rule applies.
declare -a IMPORT_SRC=() IMPORT_DST=() IMPORT_PLAN=() IMPORT_FILES=()
IMPORT_FAILED=0
for SQL_FILE in "$BACKUP_DIR"/*.sql "$BACKUP_DIR"/*.sql.gz; do
    [ -f "$SQL_FILE" ] || continue
    n=$(basename "$SQL_FILE"); n="${n%.gz}"; n="${n%.sql}"
    IMPORT_SRC+=("$n"); IMPORT_DST+=("$LOCAL_DB_PREFIX$n"); IMPORT_FILES+=("$(basename "$SQL_FILE")")
done
if [ ${#IMPORT_SRC[@]} -eq 0 ]; then
    echo "No .sql or .sql.gz files found in $BACKUP_DIR"
    exit 1
fi
guard_plan IMPORT_SRC IMPORT_DST true || { echo "Safety checks failed. Nothing was changed."; exit 1; }
for i in "${!IMPORT_SRC[@]}"; do
    if local_db_exists "${IMPORT_DST[$i]}"; then
        IMPORT_PLAN+=("${IMPORT_FILES[$i]} -> ${IMPORT_DST[$i]}   [EXISTS: dropped and replaced]")
    else
        IMPORT_PLAN+=("${IMPORT_FILES[$i]} -> ${IMPORT_DST[$i]}   [new]")
    fi
done
confirm_plan IMPORT_PLAN

echo "Starting import from $BACKUP_DIR..."
echo "Local database prefix: $LOCAL_DB_PREFIX"
echo "Target host: ${LOCAL_HOST:-localhost}:${LOCAL_PORT:-3306}"

for SQL_FILE in "$BACKUP_DIR"/*.sql "$BACKUP_DIR"/*.sql.gz; do
    if [ ! -f "$SQL_FILE" ]; then
        continue # Skip if not a file (e.g. if no dump files found)
    fi

    DB_NAME_WITH_EXT=$(basename "$SQL_FILE")
    DB_NAME="${DB_NAME_WITH_EXT%.gz}"
    DB_NAME="${DB_NAME%.sql}"
    LOCAL_DB_NAME="$LOCAL_DB_PREFIX$DB_NAME"

    echo "Processing $DB_NAME..."
    echo "Importing $DB_NAME into local database $LOCAL_DB_NAME..."

    if ! local_mysql -e "DROP DATABASE IF EXISTS $(sql_ident "$LOCAL_DB_NAME")"; then
        echo "❌ Failed to drop existing database $LOCAL_DB_NAME"
        continue
    fi

    if ! local_mysql -e "$(create_database_sql "$LOCAL_DB_NAME")"; then
        echo "❌ Failed to create local database $LOCAL_DB_NAME"
        continue
    fi

    # Stream the dump straight into mysql (no plaintext copy on disk): disable
    # binary logging and FK checks, strip GTID / replication statements.
    (
        set -o pipefail
        {
            echo "SET SESSION sql_log_bin=0;"
            echo "SET SESSION foreign_key_checks=0;"
            if [ -n "${SQL_MODE:-}" ]; then echo "SET SESSION sql_mode='${SQL_MODE//\'/\'\'}';"; fi
            read_backup "$SQL_FILE" | sed -e '/SET @@GLOBAL.GTID_PURGED/d' \
                                          -e '/SET @@SESSION.SQL_LOG_BIN/d' \
                                          -e '/SET @@GLOBAL.GTID_EXECUTED/d' \
                                          -e '/CHANGE MASTER/d'
            echo "SET SESSION sql_log_bin=1;"
        } | local_mysql "$LOCAL_DB_NAME"
    )
    IMPORT_STATUS=$?

    if [ $IMPORT_STATUS -ne 0 ]; then
        echo "❌ Failed to import $DB_NAME into $LOCAL_DB_NAME"
        IMPORT_FAILED=1
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

if [ "$IMPORT_FAILED" -ne 0 ]; then
    echo "One or more imports failed."
    exit 1
fi

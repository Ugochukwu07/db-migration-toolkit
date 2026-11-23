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

# Where pre-import snapshots live. This is deliberately NOT the backup directory
# being imported, so a snapshot can never be picked up as a backup to import.
SAFETY_DIR="${PROJECT_ROOT}/data/tmp/import_from_backups"
mkdir -p "$SAFETY_DIR"
secure_dirs "$SAFETY_DIR"

# Safety guards + plan + confirmation (before any database is replaced).
# There is no remote source here, so only the protected-schema rule applies.
declare -a IMPORT_SRC=() IMPORT_DST=() IMPORT_PLAN=() IMPORT_FILES=() IMPORT_PATHS=()
IMPORT_FAILED=0
for SQL_FILE in "$BACKUP_DIR"/*.sql "$BACKUP_DIR"/*.sql.gz; do
    [ -f "$SQL_FILE" ] || continue
    n=$(basename "$SQL_FILE"); n="${n%.gz}"; n="${n%.sql}"
    case "$n" in pre-sync_*|pre-import_*) continue ;; esac   # leftover snapshots are never imported
    IMPORT_SRC+=("$n"); IMPORT_DST+=("$LOCAL_DB_PREFIX$n"); IMPORT_FILES+=("$(basename "$SQL_FILE")"); IMPORT_PATHS+=("$SQL_FILE")
done
if [ ${#IMPORT_SRC[@]} -eq 0 ]; then
    echo "No .sql or .sql.gz files found in $BACKUP_DIR"
    exit 1
fi
guard_plan IMPORT_SRC IMPORT_DST true || { echo "Safety checks failed. Nothing was changed."; exit 1; }

# A dump that switches database (CREATE DATABASE / USE) would write somewhere
# other than the planned target, bypassing the checks above.
SWITCHING=0
for i in "${!IMPORT_PATHS[@]}"; do
    if backup_switches_database "${IMPORT_PATHS[$i]}"; then
        echo "ERROR: ${IMPORT_FILES[$i]} contains CREATE DATABASE / USE statements (a mysqldump --databases dump)."
        echo "       It would write into the database it names instead of ${IMPORT_DST[$i]}. Re-create it without --databases."
        SWITCHING=1
    fi
done
[ "$SWITCHING" -eq 0 ] || { echo "Safety checks failed. Nothing was changed."; exit 1; }

LOCAL_BYTES=0
for i in "${!IMPORT_SRC[@]}"; do
    if local_db_exists "${IMPORT_DST[$i]}"; then
        IMPORT_PLAN+=("${IMPORT_FILES[$i]} -> ${IMPORT_DST[$i]}   [EXISTS: replaced; snapshot restored on failure]")
        LOCAL_BYTES=$(( LOCAL_BYTES + $(local_bytes "${IMPORT_DST[$i]}") ))
    else
        IMPORT_PLAN+=("${IMPORT_FILES[$i]} -> ${IMPORT_DST[$i]}   [new]")
    fi
done
confirm_plan IMPORT_PLAN
check_disk_space "$SAFETY_DIR" 0 "$LOCAL_BYTES" || exit 1

echo "Starting import from $BACKUP_DIR..."
echo "Local database prefix: $LOCAL_DB_PREFIX"
echo "Target host: ${LOCAL_HOST:-localhost}:${LOCAL_PORT:-3306}"

for i in "${!IMPORT_PATHS[@]}"; do
    SQL_FILE="${IMPORT_PATHS[$i]}"
    DB_NAME="${IMPORT_SRC[$i]}"
    LOCAL_DB_NAME="${IMPORT_DST[$i]}"
    SAFETY_FILE="$SAFETY_DIR/pre-import_${LOCAL_DB_NAME}-$(date '+%Y%m%d_%H%M%S')$(backup_ext)"
    ERR_FILE="$SAFETY_DIR/${LOCAL_DB_NAME}_import_error.log"

    echo "Importing $DB_NAME into local database $LOCAL_DB_NAME (existing data is snapshotted and restored on failure)..."

    # Snapshot, replace, verify; restore the snapshot if anything fails.
    replace_local_database "$LOCAL_DB_NAME" "$SQL_FILE" "$SAFETY_FILE" "$ERR_FILE" true
    rc=$?

    if [ $rc -eq 0 ]; then
        echo "✅ $DB_NAME imported into $LOCAL_DB_NAME successfully."
        table_count=$(local_mysql -N -B "$LOCAL_DB_NAME" -e 'SHOW TABLES;' 2>/dev/null | wc -l)
        if [ "${table_count:-0}" -gt 0 ]; then
            echo "   Import verified: $table_count tables found"
        fi
        rm -f -- "${ERR_FILE:?}"
    else
        case $rc in
            2) echo "❌ Aborted $DB_NAME: could not snapshot existing $LOCAL_DB_NAME; it was left untouched" ;;
            3) echo "❌ Import of $DB_NAME failed AND rollback failed. Previous data is kept in $SAFETY_FILE" ;;
            *) echo "❌ Failed to import $DB_NAME into $LOCAL_DB_NAME" ;;
        esac
        echo "   Details: $(tail -n 4 "$ERR_FILE" 2>/dev/null | tr '\n' ' ')"
        IMPORT_FAILED=1
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

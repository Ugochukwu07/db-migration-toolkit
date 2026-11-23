#!/bin/bash

# ==============================================
# Configuration Loader for Database Migration Toolkit
# ==============================================
# This script provides functions to load and validate configuration
# Source this script in other scripts to use configuration functions

# Default configuration file path
DEFAULT_CONFIG_FILE="./config/config.env"

# === LOGGING FUNCTION ===
config_log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "ERROR")
            echo "[$timestamp] [CONFIG] [ERROR] $message" >&2
            ;;
        "WARN")
            echo "[$timestamp] [CONFIG] [WARN] $message" >&2
            ;;
        "INFO")
            echo "[$timestamp] [CONFIG] [INFO] $message"
            ;;
        "DEBUG")
            if [ "${DEBUG_MODE:-false}" = "true" ]; then
                echo "[$timestamp] [CONFIG] [DEBUG] $message"
            fi
            ;;
    esac
}

# === CONFIGURATION LOADING FUNCTION ===
load_config() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    
    config_log "INFO" "Loading configuration from: $config_file"
    
    if [ ! -f "$config_file" ]; then
        config_log "ERROR" "Configuration file not found: $config_file"
        config_log "ERROR" "Please copy config/config.env.example to config/config.env and configure your settings."
        return 1
    fi
    
    # The config holds passwords: warn if other users can read it
    local perms
    perms=$(stat -c '%a' "$config_file" 2>/dev/null || stat -f '%Lp' "$config_file" 2>/dev/null)
    if [ -n "$perms" ] && [ "${perms: -2}" != "00" ]; then
        config_log "WARN" "$config_file is readable by other users (mode $perms) and contains passwords. Run: chmod 600 \"$config_file\""
    fi

    # Source the configuration file with error handling
    if ! source "$config_file" 2>/dev/null; then
        config_log "ERROR" "Failed to source configuration file: $config_file"
        config_log "ERROR" "Please check the file syntax and permissions."
        return 1
    fi
    
    # Export all variables so they're available to child processes
    set -a
    source "$config_file"
    set +a
    
    config_log "INFO" "Configuration loaded successfully"
    return 0
}

# === DATABASE LIST PARSING FUNCTION ===
parse_database_list() {
    local db_string="${SYNC_DATABASES:-}"
    local -n db_array_ref=$1
    
    if [ -z "$db_string" ]; then
        config_log "WARN" "No databases specified in SYNC_DATABASES"
        return 1
    fi
    
    # Split comma-separated values into array
    IFS=',' read -ra db_array_ref <<< "$db_string"
    
    # Trim whitespace from each database name
    local i
    for i in "${!db_array_ref[@]}"; do
        db_array_ref[$i]=$(echo "${db_array_ref[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    done
    
    config_log "INFO" "Parsed ${#db_array_ref[@]} databases: ${db_array_ref[*]}"
    return 0
}

# === TABLE SYNC CONFIG PARSING FUNCTION ===
parse_table_sync_config() {
    local -n config_array_ref=$1
    local config_string=""
    
    # Use multiline config if available, otherwise use single line
    if [ -n "${TABLE_SYNC_CONFIG_MULTILINE:-}" ]; then
        config_string="$TABLE_SYNC_CONFIG_MULTILINE"
        config_log "INFO" "Using multiline table sync configuration"
    else
        config_string="${TABLE_SYNC_CONFIG:-}"
        config_log "INFO" "Using single line table sync configuration"
    fi
    
    if [ -z "$config_string" ]; then
        config_log "WARN" "No table sync configuration specified"
        return 1
    fi
    
    # Handle multiline configuration
    if [ -n "${TABLE_SYNC_CONFIG_MULTILINE:-}" ]; then
        # Split by newlines and filter out empty lines
        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$line" ] && [[ ! "$line" =~ ^# ]]; then
                config_array_ref+=("$line")
            fi
        done <<< "$config_string"
    else
        # Split by pipe separator
        IFS='|' read -ra config_array_ref <<< "$config_string"
        
        # Trim whitespace from each entry
        local i
        for i in "${!config_array_ref[@]}"; do
            config_array_ref[$i]=$(echo "${config_array_ref[$i]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        done
    fi
    
    config_log "INFO" "Parsed ${#config_array_ref[@]} table sync configurations"
    return 0
}

# === CONFIGURATION VALIDATION FUNCTION ===
validate_config() {
    local validation_errors=0
    
    config_log "INFO" "Validating configuration..."
    
    # Check required variables
    local required_vars=(
        "REMOTE_HOST"
        "REMOTE_USER" 
        "REMOTE_PASS"
        "LOCAL_USER"
        "LOCAL_PASS"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            config_log "ERROR" "Required configuration variable '$var' is not set"
            ((validation_errors++))
        fi
    done
    
    # Validate numeric values
    if ! [[ "${MAX_THREADS:-4}" =~ ^[0-9]+$ ]] || [ "${MAX_THREADS:-4}" -lt 1 ] || [ "${MAX_THREADS:-4}" -gt 32 ]; then
        config_log "ERROR" "MAX_THREADS must be a number between 1 and 32"
        ((validation_errors++))
    fi
    
    if ! [[ "${MAX_RETRY_ATTEMPTS:-3}" =~ ^[0-9]+$ ]] || [ "${MAX_RETRY_ATTEMPTS:-3}" -lt 1 ]; then
        config_log "ERROR" "MAX_RETRY_ATTEMPTS must be a positive number"
        ((validation_errors++))
    fi
    
    if ! [[ "${RETRY_DELAY:-10}" =~ ^[0-9]+$ ]] || [ "${RETRY_DELAY:-10}" -lt 1 ]; then
        config_log "ERROR" "RETRY_DELAY must be a positive number"
        ((validation_errors++))
    fi
    
    # Validate boolean values
    local bool_vars=(
        "DROP_EXISTING_TABLE"
        "DEBUG_MODE"
        "VALIDATE_CONFIG"
        "TEST_CONNECTIONS"
        "ENABLE_EMAIL_NOTIFICATIONS"
        "ENABLE_WEBHOOK_NOTIFICATIONS"
    )
    
    for var in "${bool_vars[@]}"; do
        if [ -n "${!var}" ] && [[ ! "${!var}" =~ ^(true|false)$ ]]; then
            config_log "ERROR" "Configuration variable '$var' must be 'true' or 'false'"
            ((validation_errors++))
        fi
    done
    
    # Validate port numbers
    for port_var in "REMOTE_PORT" "LOCAL_PORT"; do
        local port_value="${!port_var}"
        if [ -n "$port_value" ] && (! [[ "$port_value" =~ ^[0-9]+$ ]] || [ "$port_value" -lt 1 ] || [ "$port_value" -gt 65535 ]); then
            config_log "ERROR" "$port_var must be a valid port number (1-65535)"
            ((validation_errors++))
        fi
    done
    
    # Dump handling
    case "${BACKUP_COMPRESSION:-gzip}" in
        gzip|none) ;;
        *) config_log "ERROR" "BACKUP_COMPRESSION must be 'gzip' or 'none'"; ((validation_errors++)) ;;
    esac
    if [ "${BACKUP_COMPRESSION:-gzip}" = "gzip" ] && ! command -v gzip >/dev/null 2>&1; then
        config_log "ERROR" "BACKUP_COMPRESSION=gzip but gzip is not installed (install it or set BACKUP_COMPRESSION=none)"
        ((validation_errors++))
    fi
    if [ -n "${DISK_SPACE_CHECK:-}" ] && [[ ! "${DISK_SPACE_CHECK}" =~ ^(true|false)$ ]]; then
        config_log "ERROR" "DISK_SPACE_CHECK must be 'true' or 'false'"
        ((validation_errors++))
    fi
    if [ -n "${MIN_FREE_DISK_MB:-}" ] && ! [[ "${MIN_FREE_DISK_MB}" =~ ^[0-9]+$ ]]; then
        config_log "ERROR" "MIN_FREE_DISK_MB must be a non-negative number"
        ((validation_errors++))
    fi

    # TLS settings
    local side mode_var ca_var mode ca
    for side in REMOTE LOCAL; do
        mode_var="${side}_SSL_MODE"; ca_var="${side}_SSL_CA"
        mode="${!mode_var:-}"; ca="${!ca_var:-}"
        if [ -n "$mode" ] && [[ ! "${mode^^}" =~ ^(DISABLED|PREFERRED|REQUIRED|VERIFY_CA|VERIFY_IDENTITY)$ ]]; then
            config_log "ERROR" "$mode_var must be one of DISABLED, PREFERRED, REQUIRED, VERIFY_CA, VERIFY_IDENTITY"
            ((validation_errors++))
        fi
        if [ -n "$ca" ] && [ ! -r "$ca" ]; then
            config_log "ERROR" "$ca_var points to a file that does not exist or is not readable: $ca"
            ((validation_errors++))
        fi
        if [ "${mode^^}" = "VERIFY_CA" ] && [ -z "$ca" ]; then
            config_log "ERROR" "$mode_var=VERIFY_CA requires $ca_var"
            ((validation_errors++))
        fi
    done

    # CHARSET / COLLATION are interpolated into SQL, so restrict them
    for var in CHARSET COLLATION; do
        if [ -n "${!var:-}" ] && ! [[ "${!var}" =~ ^[A-Za-z0-9_]+$ ]]; then
            config_log "ERROR" "$var may only contain letters, digits and underscores"
            ((validation_errors++))
        fi
    done
    
    if [ $validation_errors -eq 0 ]; then
        config_log "INFO" "Configuration validation passed"
        return 0
    else
        config_log "ERROR" "Configuration validation failed with $validation_errors errors"
        return 1
    fi
}

# === DATABASE CONNECTION TEST FUNCTION ===
test_database_connections() {
    local test_errors=0
    
    config_log "INFO" "Testing database connections..."
    
    # Test remote database connection
    config_log "INFO" "Testing remote database connection..."
    if remote_mysql -e "SELECT VERSION();" >/dev/null 2>&1; then
        config_log "INFO" "Remote database connection successful"
    else
        config_log "ERROR" "Remote database connection failed"
        ((test_errors++))
    fi
    
    # Test local database connection
    config_log "INFO" "Testing local database connection..."
    if local_mysql -e "SELECT VERSION();" >/dev/null 2>&1; then
        config_log "INFO" "Local database connection successful"
    else
        config_log "ERROR" "Local database connection failed"
        ((test_errors++))
    fi
    
    if [ $test_errors -eq 0 ]; then
        report_tls_status remote
        report_tls_status local
        config_log "INFO" "Database connection tests passed"
        return 0
    else
        config_log "ERROR" "Database connection tests failed"
        return 1
    fi
}

# === CONFIGURATION SUMMARY FUNCTION ===
show_config_summary() {
    config_log "INFO" "Configuration Summary:"
    config_log "INFO" "  Remote Host: ${REMOTE_HOST}:${REMOTE_PORT:-3306}"
    config_log "INFO" "  Remote User: ${REMOTE_USER}"
    config_log "INFO" "  Local Host: ${LOCAL_HOST:-localhost}:${LOCAL_PORT:-3306}"
    config_log "INFO" "  Local User: ${LOCAL_USER}"
    config_log "INFO" "  Max Threads: ${MAX_THREADS:-4}"
    config_log "INFO" "  Max Retry Attempts: ${MAX_RETRY_ATTEMPTS:-3}"
    config_log "INFO" "  Retry Delay: ${RETRY_DELAY:-10}s"
    config_log "INFO" "  Drop Existing Tables: ${DROP_EXISTING_TABLE:-true}"
    config_log "INFO" "  Local DB Prefix: ${LOCAL_DB_PREFIX:-none}"
    config_log "INFO" "  Debug Mode: ${DEBUG_MODE:-false}"
    
    # Show database list if available
    if [ -n "${SYNC_DATABASES:-}" ]; then
        local databases
        if parse_database_list databases; then
            config_log "INFO" "  Sync Databases (${#databases[@]}): ${databases[*]}"
        fi
    fi
    
    # Show table sync config if available
    if [ -n "${TABLE_SYNC_CONFIG:-}${TABLE_SYNC_CONFIG_MULTILINE:-}" ]; then
        local table_configs
        if parse_table_sync_config table_configs; then
            config_log "INFO" "  Table Sync Configurations: ${#table_configs[@]} entries"
            for config in "${table_configs[@]}"; do
                config_log "INFO" "    - $config"
            done
        fi
    fi
}

# === MAIN CONFIGURATION INITIALIZATION FUNCTION ===
init_config() {
    local config_file="${1:-$DEFAULT_CONFIG_FILE}"
    local validate_only="${2:-false}"
    
    # Everything we write (dumps, logs, temp files) holds database contents:
    # make new files 600 and new directories 700.
    umask 077

    # Load configuration
    if ! load_config "$config_file"; then
        return 1
    fi
    
    # Validate configuration if enabled
    if [ "${VALIDATE_CONFIG:-true}" = "true" ]; then
        if ! validate_config; then
            config_log "ERROR" "Configuration validation failed"
            return 1
        fi
    fi
    
    # Create private credential files (no passwords on command lines)
    if ! init_credentials; then
        return 1
    fi
    
    # Test database connections if enabled and not validation-only
    if [ "$validate_only" != "true" ] && [ "${TEST_CONNECTIONS:-true}" = "true" ]; then
        if ! test_database_connections; then
            config_log "WARN" "Database connection tests failed - continuing anyway"
        fi
    fi
    
    # Show configuration summary if debug mode is enabled
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        show_config_summary
    fi
    
    config_log "INFO" "Configuration initialization completed"
    return 0
}

# === UTILITY FUNCTIONS ===

# Get effective database name with prefix
get_local_database_name() {
    local source_db="$1"
    local custom_target="${2:-}"
    
    if [ -n "$custom_target" ]; then
        echo "$custom_target"
    else
        echo "${LOCAL_DB_PREFIX:-}${source_db}"
    fi
}

# Get mysqldump options for database sync
get_mysqldump_options() {
    echo "${MYSQLDUMP_OPTIONS:-"--set-gtid-purged=OFF --skip-add-locks --skip-lock-tables --single-transaction --routines --triggers"}"
}

# Get mysqldump options for table sync
get_mysqldump_table_options() {
    echo "${MYSQLDUMP_TABLE_OPTIONS:-"--set-gtid-purged=OFF --skip-add-locks --skip-lock-tables --skip-triggers --skip-opt --single-transaction --add-drop-table --create-options --extended-insert --quick --lock-tables=false"}"
}

# Check if debug mode is enabled
is_debug_mode() {
    [ "${DEBUG_MODE:-false}" = "true" ]
}

# Check if we should drop existing tables
should_drop_existing_tables() {
    [ "${DROP_EXISTING_TABLE:-true}" = "true" ]
}

# === SAFE MYSQL INVOCATION HELPERS ===
# Credentials are never placed on a command line (visible in `ps`) and
# commands are never built as strings for eval. Instead each connection gets
# a private (mode 600) option file passed with --defaults-extra-file, and all
# arguments are passed as properly quoted words.

_CRED_DIR=""

# Escape a value for use inside a double-quoted option-file string
_cnf_escape() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '%s' "$v"
}

# Write a client option file: _write_cnf <file> <host> <port> <user> <password>
_write_cnf() {
    local file="$1" host="$2" port="$3" user="$4" pass="$5" ssl_mode="${6:-}" ssl_ca="${7:-}"
    case "$host$port$user$pass$ssl_mode$ssl_ca" in
        *$'\n'*|*$'\r'*)
            config_log "ERROR" "Credentials must not contain newline characters"
            return 1
            ;;
    esac
    (
        umask 077
        {
            echo "[client]"
            echo "host=\"$(_cnf_escape "$host")\""
            echo "port=\"$(_cnf_escape "$port")\""
            echo "user=\"$(_cnf_escape "$user")\""
            echo "password=\"$(_cnf_escape "$pass")\""
            if [ -n "$ssl_mode" ]; then echo "ssl-mode=${ssl_mode^^}"; fi
            if [ -n "$ssl_ca" ]; then echo "ssl-ca=\"$(_cnf_escape "$ssl_ca")\""; fi
        } > "$file"
    )
}

# Remove credential files (also runs on exit)
cleanup_credentials() {
    if [ -n "$_CRED_DIR" ] && [ -d "$_CRED_DIR" ]; then
        rm -rf "$_CRED_DIR"
    fi
    _CRED_DIR=""
}

# Create credential files for the remote and local servers.
# Must be called once in the main process BEFORE any background jobs start.
init_credentials() {
    cleanup_credentials
    _CRED_DIR=$(umask 077 && mktemp -d "${TMPDIR:-/tmp}/dbmig-cred.XXXXXX") || {
        config_log "ERROR" "Could not create a private directory for credentials"
        return 1
    }
    REMOTE_CNF="$_CRED_DIR/remote.cnf"
    LOCAL_CNF="$_CRED_DIR/local.cnf"
    _write_cnf "$REMOTE_CNF" "$REMOTE_HOST" "${REMOTE_PORT:-3306}" "$REMOTE_USER" "$REMOTE_PASS" "${REMOTE_SSL_MODE:-}" "${REMOTE_SSL_CA:-}" || return 1
    _write_cnf "$LOCAL_CNF" "${LOCAL_HOST:-localhost}" "${LOCAL_PORT:-3306}" "$LOCAL_USER" "$LOCAL_PASS" "${LOCAL_SSL_MODE:-}" "${LOCAL_SSL_CA:-}" || return 1
    export REMOTE_CNF LOCAL_CNF
    trap cleanup_credentials EXIT
    trap 'cleanup_credentials; exit 130' INT
    trap 'cleanup_credentials; exit 143' TERM
}

# Run mysql / mysqldump against the remote or local server.
remote_mysql() {
    mysql --defaults-extra-file="$REMOTE_CNF" --connect-timeout="${MYSQL_CONNECT_TIMEOUT:-60}" "$@"
}
local_mysql() {
    mysql --defaults-extra-file="$LOCAL_CNF" --connect-timeout="${MYSQL_CONNECT_TIMEOUT:-60}" "$@"
}
remote_mysqldump() {
    mysqldump --defaults-extra-file="$REMOTE_CNF" --connect-timeout="${MYSQL_CONNECT_TIMEOUT:-60}" "$@"
}

# Quote an SQL identifier (database/table name) with backticks
sql_ident() {
    local v="${1//\`/\`\`}"
    printf '`%s`' "$v"
}

# CREATE DATABASE statement honouring CHARSET / COLLATION (validated elsewhere)
create_database_sql() {
    local name="$1" if_not_exists="${2:-false}" sql="CREATE DATABASE "
    [ "$if_not_exists" = "true" ] && sql+="IF NOT EXISTS "
    sql+="$(sql_ident "$name")"
    [ -n "${CHARSET:-}" ] && sql+=" CHARACTER SET ${CHARSET}"
    [ -n "${COLLATION:-}" ] && sql+=" COLLATE ${COLLATION}"
    printf '%s' "$sql"
}

# Split the configured mysqldump option string into an array (no eval, no globbing)
# Usage: read_dump_options <array_name> <table|db>
read_dump_options() {
    local -n _opts_ref=$1
    local raw
    if [ "${2:-db}" = "table" ]; then raw=$(get_mysqldump_table_options); else raw=$(get_mysqldump_options); fi
    read -r -a _opts_ref <<< "$raw"
    # mysqldump 8.x queries information_schema.COLUMN_STATISTICS, which 5.7
    # servers lack. Disable it when the client supports the flag (it is
    # unknown to 5.7 and MariaDB clients, so only add it when advertised).
    if mysqldump --help 2>/dev/null | grep -q -- '--column-statistics'; then
        case " $raw " in *" --column-statistics"*) ;; *) _opts_ref+=(--column-statistics=0) ;; esac
    fi
}

# Extra mysql args for imports. Foreign key checks are disabled for the import
# session (tables are imported independently/in parallel, so a child table may
# arrive before its parent); sql_mode is applied when configured.
# Usage: local_import_args <array_name>
local_import_args() {
    local -n _args_ref=$1
    local init="SET SESSION foreign_key_checks=0"
    if [ -n "${SQL_MODE:-}" ]; then
        init+=", sql_mode='${SQL_MODE//\'/\'\'}'"
    fi
    _args_ref=(--init-command="$init")
}

# === SAFETY GUARDS (run before anything destructive) ===
# 1. System schemas can never be a source or a target.
# 2. The target can never be the source server's own copy of the same database.
# 3. The user sees the plan and must confirm (or pass --yes / run in CI).
#    --dry-run prints the plan and stops.

BUILTIN_PROTECTED_DATABASES="mysql sys information_schema performance_schema"
DRY_RUN="${DRY_RUN:-false}"
ASSUME_YES="${ASSUME_YES:-false}"

print_safety_usage() {
    cat <<USAGE
Usage: $(basename "$0") [--dry-run] [--yes]

  --dry-run   Validate the configuration, run all safety checks, print what
              would be replaced, then exit without changing anything.
  -y, --yes   Do not ask for confirmation (also skipped when CI=true).
  -h, --help  Show this help.

Without --yes the script asks for confirmation before the first drop and
refuses to run non-interactively.
USAGE
}

# Parse the common safety flags. Usage: parse_safety_args "$@"
parse_safety_args() {
    local a
    for a in "$@"; do
        case "$a" in
            --dry-run) DRY_RUN=true ;;
            -y|--yes) ASSUME_YES=true ;;
            -h|--help) print_safety_usage; exit 0 ;;
            *) echo "Unknown option: $a" >&2; print_safety_usage >&2; return 1 ;;
        esac
    done
    return 0
}

# Is this a protected schema? Built-ins plus PROTECTED_DATABASES (comma separated).
is_protected_database() {
    local name="${1,,}" p extra
    for p in $BUILTIN_PROTECTED_DATABASES; do
        [ "$name" = "$p" ] && return 0
    done
    IFS=',' read -ra extra <<< "${PROTECTED_DATABASES:-}"
    for p in "${extra[@]}"; do
        p="${p#"${p%%[![:space:]]*}"}"; p="${p%"${p##*[![:space:]]}"}"
        [ -n "$p" ] && [ "$name" = "${p,,}" ] && return 0
    done
    return 1
}

_SAME_SERVER_CACHE=""

# Are the remote (source) and local (target) connections the same MySQL server?
# Compares a server identity (hostname|port|server_uuid) so aliases such as
# 127.0.0.1 vs 127.0.0.2 vs a DNS name are caught. Falls back to comparing the
# configured host and port only when the identity can't be read.
servers_are_same() {
    [ -n "$_SAME_SERVER_CACHE" ] && { [ "$_SAME_SERVER_CACHE" = "yes" ]; return; }
    local rid lid
    rid=$(remote_mysql -N -B -e "SELECT CONCAT_WS('|',@@hostname,@@port,@@server_uuid)" 2>/dev/null) \
        || rid=$(remote_mysql -N -B -e "SELECT CONCAT_WS('|',@@hostname,@@port,@@datadir)" 2>/dev/null) || rid=""
    lid=$(local_mysql -N -B -e "SELECT CONCAT_WS('|',@@hostname,@@port,@@server_uuid)" 2>/dev/null) \
        || lid=$(local_mysql -N -B -e "SELECT CONCAT_WS('|',@@hostname,@@port,@@datadir)" 2>/dev/null) || lid=""
    if [ -n "$rid" ] && [ -n "$lid" ]; then
        [ "$rid" = "$lid" ] && _SAME_SERVER_CACHE=yes || _SAME_SERVER_CACHE=no
    else
        local rh="${REMOTE_HOST,,}" lh="${LOCAL_HOST:-localhost}"
        lh="${lh,,}"
        # 'localhost' means a unix socket, whose port is ignored, so it proves nothing
        if [ "$rh" = "$lh" ] && [ "$rh" != "localhost" ] && [ "${REMOTE_PORT:-3306}" = "${LOCAL_PORT:-3306}" ]; then
            _SAME_SERVER_CACHE=yes
        else
            _SAME_SERVER_CACHE=no
        fi
    fi
    [ "$_SAME_SERVER_CACHE" = "yes" ]
}

# Validate every (source, target) database pair of a plan. Prints every problem
# found and returns 1 if there is any.
# Usage: guard_plan <src_array_name> <dst_array_name> [skip_same_server=false]
guard_plan() {
    local -n _gp_src=$1
    local -n _gp_dst=$2
    local skip_same="${3:-false}" i s d bad=0 same=false o
    if [ "$skip_same" != "true" ] && servers_are_same; then
        same=true
    fi
    for i in "${!_gp_src[@]}"; do
        s="${_gp_src[$i]}"; d="${_gp_dst[$i]}"
        if [ "$skip_same" != "true" ] && is_protected_database "$s"; then
            config_log "ERROR" "Refusing to sync from '$s': it is a protected system schema"
            bad=1
        fi
        if is_protected_database "$d"; then
            config_log "ERROR" "Refusing to write to '$d': it is a protected system schema"
            bad=1
        fi
        if [ "$same" = "true" ]; then
            if [ "${s,,}" = "${d,,}" ]; then
                config_log "ERROR" "Refusing to sync '$s' onto itself: the local target is the SAME server as the remote source and the database name is identical."
                config_log "ERROR" "Set LOCAL_DB_PREFIX (e.g. LOCAL_DB_PREFIX=\"copy_\") or use a different target database."
                bad=1
            else
                for o in "${_gp_src[@]}"; do
                    if [ "${o,,}" = "${d,,}" ]; then
                        config_log "ERROR" "Refusing to write '$d': on the same server it is also a SOURCE database in this run."
                        bad=1
                    fi
                done
            fi
        fi
    done
    return $bad
}

# Does a database exist on the local (target) server?
local_db_exists() {
    local n
    n=$(local_mysql -N -B -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$(_sql_str "$1")'" 2>/dev/null) || return 1
    [ "${n:-0}" -gt 0 ]
}

# Show the plan and decide whether to continue. Exits the script for --dry-run
# (status 0) and for a declined / impossible confirmation (status 1).
# Usage: confirm_plan <plan_lines_array_name>
confirm_plan() {
    local -n _cp_lines=$1
    local line answer
    echo
    echo "================ PLANNED CHANGES ================"
    echo "Source (read only):       ${REMOTE_HOST}:${REMOTE_PORT:-3306}"
    echo "Target (WILL BE CHANGED): ${LOCAL_HOST:-localhost}:${LOCAL_PORT:-3306}"
    echo
    for line in "${_cp_lines[@]}"; do echo "  $line"; done
    echo "================================================="
    echo

    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY RUN: all safety checks passed. Nothing was changed."
        exit 0
    fi
    if [ "$ASSUME_YES" = "true" ]; then
        config_log "INFO" "Confirmation skipped (--yes)"
        return 0
    fi
    if [ "${CI:-}" = "true" ]; then
        config_log "INFO" "Confirmation skipped (CI=true)"
        return 0
    fi
    if [ ! -t 0 ]; then
        config_log "ERROR" "This run would replace the databases listed above, but there is no terminal to ask for confirmation."
        config_log "ERROR" "Re-run with --yes to proceed non-interactively, or --dry-run to preview."
        exit 1
    fi
    read -r -p "Type 'yes' to replace the databases listed above: " answer
    if [ "$answer" != "yes" ]; then
        config_log "ERROR" "Aborted: nothing was changed."
        exit 1
    fi
    return 0
}

# Full pre-flight for whole-database syncs: guards + plan + confirmation.
# Usage: plan_and_confirm_databases <databases_array_name>
plan_and_confirm_databases() {
    local -n _pd_dbs=$1
    local -a src=() dst=() lines=()
    local db t
    for db in "${_pd_dbs[@]}"; do
        t=$(get_local_database_name "$db")
        src+=("$db"); dst+=("$t")
    done
    guard_plan src dst || { config_log "ERROR" "Safety checks failed. Nothing was changed."; exit 1; }
    for i in "${!src[@]}"; do
        if local_db_exists "${dst[$i]}"; then
            lines+=("${src[$i]} -> ${dst[$i]}   [EXISTS: dropped and replaced; snapshot restored on failure]")
        else
            lines+=("${src[$i]} -> ${dst[$i]}   [new]")
        fi
    done
    confirm_plan lines
}

# Full pre-flight for table syncs. Entries are "source_db:target_db:table".
# Usage: plan_and_confirm_tables <table_list_array_name>
plan_and_confirm_tables() {
    local -n _pt_list=$1
    local -a src=() dst=() lines=()
    local e s d t
    for e in "${_pt_list[@]}"; do
        IFS=':' read -r s d t <<< "$e"
        src+=("$s"); dst+=("$d")
    done
    guard_plan src dst || { config_log "ERROR" "Safety checks failed. Nothing was changed."; exit 1; }
    for e in "${_pt_list[@]}"; do
        IFS=':' read -r s d t <<< "$e"
        if local_mysql -N -B "$d" -e 'SHOW TABLES;' 2>/dev/null | grep -Fxq -- "$t"; then
            lines+=("$s.$t -> $d.$t   [EXISTS: replaced; snapshot restored on failure]")
        else
            lines+=("$s.$t -> $d.$t   [new]")
        fi
    done
    confirm_plan lines
}

# === DUMP FILE HELPERS (private files, optional gzip) ===

# Extension for new dump files
backup_ext() {
    if [ "${BACKUP_COMPRESSION:-gzip}" = "gzip" ]; then echo ".sql.gz"; else echo ".sql"; fi
}

# Run a dump command and store its stdout in <outfile>, gzip-compressed when the
# name ends in .gz. A failure anywhere in the pipeline (dump OR gzip) fails the
# call, and compressed output is integrity-checked.
# Usage: dump_to_file <outfile> <errfile> <command...>
dump_to_file() {
    local out="${1:?}" err="${2:?}"
    shift 2
    if [[ "$out" == *.gz ]]; then
        ( set -o pipefail; "$@" 2>"$err" | gzip -c > "$out" ) || return 1
        gzip -t -- "$out" 2>>"$err" || return 1
    else
        "$@" > "$out" 2>"$err" || return 1
    fi
}

# Print a dump file as plain SQL, whether or not it is compressed
read_backup() {
    case "$1" in
        *.gz) gzip -dc -- "$1" ;;
        *)    cat -- "$1" ;;
    esac
}
backup_has_text() { read_backup "$1" 2>/dev/null | grep -q -- "$2"; }
backup_count_text() { local n; n=$(read_backup "$1" 2>/dev/null | grep -c -- "$2"); echo "${n:-0}"; }

# Delete dumps older than N days (plain and compressed)
cleanup_old_backups() {
    local dir="${1:?}" days="${2:?}"
    find "$dir" \( -name '*.sql' -o -name '*.sql.gz' \) -mtime +"$days" -delete 2>/dev/null || true
}

# Lock down directories we write dumps/logs to, and any dumps left by older
# versions that were created world-readable.
secure_dirs() {
    local d
    for d in "$@"; do
        [ -d "$d" ] || continue
        chmod 700 "$d" 2>/dev/null || true
        find "$d" -type f \( -name '*.sql' -o -name '*.sql.gz' -o -name '*.log' -o -name '*.tmp' \) ! -perm 600 -exec chmod 600 {} + 2>/dev/null || true
    done
    return 0
}

# === DISK SPACE CHECK ===

_free_kb() {
    local p="$1"
    while [ ! -d "$p" ] && [ "$p" != "/" ]; do p=$(dirname "$p"); done
    df -Pk "$p" 2>/dev/null | awk 'NR==2 {print $4}'
}

# Approximate on-disk size (bytes) of a remote database or one table
remote_bytes() {
    local db="$1" table="${2:-}" q n
    q="SELECT COALESCE(SUM(data_length+index_length),0) FROM information_schema.tables WHERE table_schema='$(_sql_str "$db")'"
    [ -n "$table" ] && q+=" AND table_name='$(_sql_str "$table")'"
    n=$(remote_mysql -N -B -e "$q" 2>/dev/null)
    [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo 0
}
local_bytes() {
    local db="$1" table="${2:-}" q n
    q="SELECT COALESCE(SUM(data_length+index_length),0) FROM information_schema.tables WHERE table_schema='$(_sql_str "$db")'"
    [ -n "$table" ] && q+=" AND table_name='$(_sql_str "$table")'"
    n=$(local_mysql -N -B -e "$q" 2>/dev/null)
    [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo 0
}

# Refuse to start when the dumps (new dumps from the remote + safety snapshots
# of what is replaced locally) would not fit, leaving MIN_FREE_DISK_MB spare.
# Usage: check_disk_space <dir> <remote_bytes> <local_bytes>
check_disk_space() {
    [ "${DISK_SPACE_CHECK:-true}" = "true" ] || return 0
    local dir="${1:?}" rbytes="${2:-0}" lbytes="${3:-0}"
    local pct=100 free_kb need_mb reserve_mb free_mb
    [ "${BACKUP_COMPRESSION:-gzip}" = "gzip" ] && pct=40   # text dumps compress roughly 3-5x
    reserve_mb="${MIN_FREE_DISK_MB:-200}"
    need_mb=$(( (rbytes + lbytes) * pct / 100 / 1048576 ))
    free_kb=$(_free_kb "$dir")
    if ! [[ "$free_kb" =~ ^[0-9]+$ ]]; then
        config_log "WARN" "Could not determine free disk space for $dir; skipping the disk space check"
        return 0
    fi
    free_mb=$(( free_kb / 1024 ))
    config_log "INFO" "Disk space: ~${need_mb} MB needed (+${reserve_mb} MB reserve), ${free_mb} MB free in $dir"
    if [ "$free_mb" -lt $(( need_mb + reserve_mb )) ]; then
        config_log "ERROR" "Not enough free disk space in $dir: need ~${need_mb} MB plus ${reserve_mb} MB reserve, only ${free_mb} MB free."
        config_log "ERROR" "Free some space, point BACKUP_DIR elsewhere, lower MIN_FREE_DISK_MB, or set DISK_SPACE_CHECK=false. Nothing was changed."
        return 1
    fi
    return 0
}

# Usage: check_disk_for_databases <dir> <databases_array_name>
check_disk_for_databases() {
    [ "${DISK_SPACE_CHECK:-true}" = "true" ] || return 0
    local dir="$1"; local -n _cd_dbs=$2
    local db t r=0 l=0
    for db in "${_cd_dbs[@]}"; do
        t=$(get_local_database_name "$db")
        r=$(( r + $(remote_bytes "$db") ))
        l=$(( l + $(local_bytes "$t") ))
    done
    check_disk_space "$dir" "$r" "$l"
}

# Usage: check_disk_for_tables <dir> <table_list_array_name>   (entries "src:dst:table")
check_disk_for_tables() {
    [ "${DISK_SPACE_CHECK:-true}" = "true" ] || return 0
    local dir="$1"; local -n _ct_list=$2
    local e s d t r=0 l=0
    for e in "${_ct_list[@]}"; do
        IFS=':' read -r s d t <<< "$e"
        r=$(( r + $(remote_bytes "$s" "$t") ))
        l=$(( l + $(local_bytes "$d" "$t") ))
    done
    check_disk_space "$dir" "$r" "$l"
}

# === TLS STATUS ===

# Report whether the connection to the remote/local server is encrypted.
# Usage: report_tls_status <remote|local>
report_tls_status() {
    local side="$1" fn host cipher
    fn="${side}_mysql"
    if [ "$side" = "remote" ]; then host="${REMOTE_HOST}"; else host="${LOCAL_HOST:-localhost}"; fi
    cipher=$("$fn" -N -B -e "SHOW SESSION STATUS LIKE 'Ssl_cipher'" 2>/dev/null | awk '{print $2}')
    if [ -n "$cipher" ]; then
        config_log "INFO" "${side^} connection is encrypted ($cipher)"
        return 0
    fi
    case "${host,,}" in
        localhost|127.*|::1)
            config_log "INFO" "${side^} connection is NOT encrypted (loopback address)"
            ;;
        *)
            config_log "WARN" "${side^} connection is NOT encrypted: credentials and data cross the network in clear text. Set ${side^^}_SSL_MODE=REQUIRED (or VERIFY_CA with ${side^^}_SSL_CA)."
            ;;
    esac
}

# Import a (possibly gzip-compressed) dump file; fails if either the
# decompression or the mysql client fails.
# With sanitize=true, GTID / replication statements are stripped and binary
# logging is disabled for the session (for dumps taken elsewhere).
# Usage: _import_backup <db> <file> <errfile> <import_args_array> [sanitize]
_import_backup() {
    local db="$1" f="$2" err="$3"
    local -n _ib_args=$4
    local sanitize="${5:-false}"
    if [ "$sanitize" = "true" ]; then
        (
            set -o pipefail
            {
                echo "SET SESSION sql_log_bin=0;"
                read_backup "$f" | sed -e '/SET @@GLOBAL.GTID_PURGED/d' \
                                       -e '/SET @@SESSION.SQL_LOG_BIN/d' \
                                       -e '/SET @@GLOBAL.GTID_EXECUTED/d' \
                                       -e '/CHANGE MASTER/d'
            } | local_mysql "${_ib_args[@]}" "$db"
        ) 2>>"$err"
    else
        ( set -o pipefail; read_backup "$f" | local_mysql "${_ib_args[@]}" "$db" ) 2>>"$err"
    fi
}

# Does a dump contain statements that switch the target database
# (CREATE DATABASE / USE, as written by mysqldump --databases)? Importing such a
# file would write into whatever database it names, bypassing the target name
# and the protected-schema guard.
backup_switches_database() {
    read_backup "$1" 2>/dev/null | grep -m1 -qiE '^[[:space:]]*(CREATE[[:space:]]+(DATABASE|SCHEMA)|USE[[:space:]]+[`"a-zA-Z0-9_])'
}

# === SAFE REPLACE HELPERS (no data loss on a failed import) ===
# Return codes for replace_local_database / replace_local_table:
#   0 = replaced and verified
#   1 = import/verification failed; previous data was restored (or nothing existed)
#   2 = aborted before touching anything (could not snapshot existing data)
#   3 = import failed AND restore failed; the pre-sync snapshot is kept on disk

local_mysqldump() {
    mysqldump --defaults-extra-file="$LOCAL_CNF" --connect-timeout="${MYSQL_CONNECT_TIMEOUT:-60}" "$@"
}

# Escape a value for a single-quoted SQL string literal
_sql_str() { printf '%s' "${1//\'/\'\'}"; }

# Remove the pre-sync snapshot unless the user asked to keep it
_discard_safety() {
    [ "${KEEP_PRE_SYNC_BACKUP:-false}" = "true" ] || rm -f -- "${1:?safety file required}"
}

# Replace a local database with the contents of a dump, rolling back on failure.
# Usage: replace_local_database <local_db> <dump_file> <safety_file> <error_file> [sanitize:true|false]
replace_local_database() {
    local db="${1:?}" dump_file="${2:?}" safety_file="${3:?}" err_file="${4:?}" sanitize="${5:-false}"
    local existed=0 found
    local -a import_args=()
    local_import_args import_args
    : > "$err_file"

    if is_protected_database "$db"; then
        echo "Refusing to replace protected schema '$db'" >> "$err_file"
        return 2
    fi

    found=$(local_mysql -N -B -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$(_sql_str "$db")'" 2>>"$err_file") || return 2
    [ "${found:-0}" -gt 0 ] && existed=1

    # 1. Snapshot the current local database so a failure cannot lose it
    if [ "$existed" -eq 1 ]; then
        if ! ( umask 077; dump_to_file "$safety_file" "$err_file.snap" local_mysqldump --single-transaction --routines --triggers --events --set-gtid-purged=OFF "$db" ); then
            cat "$err_file.snap" >> "$err_file" 2>/dev/null; rm -f -- "${err_file:?}.snap"
            echo "Could not snapshot existing database '$db'; leaving it untouched" >> "$err_file"
            rm -f -- "$safety_file"
            return 2
        fi
        rm -f -- "${err_file:?}.snap"
    fi

    # 2. Replace
    local ok=1
    local_mysql -e "DROP DATABASE IF EXISTS $(sql_ident "$db")" 2>>"$err_file" || ok=0
    [ $ok -eq 1 ] && { local_mysql -e "$(create_database_sql "$db")" 2>>"$err_file" || ok=0; }
    [ $ok -eq 1 ] && { _import_backup "$db" "$dump_file" "$err_file" import_args "$sanitize" || ok=0; }

    # 3. Verify: if the dump defines tables, they must exist now
    if [ $ok -eq 1 ] && backup_has_text "$dump_file" "CREATE TABLE"; then
        local tables
        tables=$(local_mysql -N -B "$db" -e 'SHOW TABLES;' 2>>"$err_file" | wc -l)
        if [ "${tables:-0}" -lt 1 ]; then
            echo "Import verification failed: no tables found in '$db'" >> "$err_file"
            ok=0
        fi
    fi

    if [ $ok -eq 1 ]; then
        _discard_safety "$safety_file"
        return 0
    fi

    # 4. Roll back
    local_mysql -e "DROP DATABASE IF EXISTS $(sql_ident "$db")" 2>>"$err_file"
    if [ "$existed" -eq 1 ]; then
        if local_mysql -e "$(create_database_sql "$db")" 2>>"$err_file" \
           && _import_backup "$db" "$safety_file" "$err_file" import_args; then
            echo "Rolled back: previous contents of '$db' restored" >> "$err_file"
            _discard_safety "$safety_file"
            return 1
        fi
        echo "ROLLBACK FAILED for '$db'. Previous data is preserved in: $safety_file" >> "$err_file"
        return 3
    fi
    return 1
}

# Replace one local table with the contents of a dump, rolling back on failure.
# Usage: replace_local_table <db> <table> <dump_file> <safety_file> <error_file> <drop_first:true|false>
replace_local_table() {
    local db="${1:?}" table="${2:?}" dump_file="${3:?}" safety_file="${4:?}" err_file="${5:?}" drop_first="${6:-true}"
    local existed=0
    local -a import_args=()
    local_import_args import_args
    : > "$err_file"

    if is_protected_database "$db"; then
        echo "Refusing to replace tables in protected schema '$db'" >> "$err_file"
        return 2
    fi

    if local_mysql -N -B "$db" -e 'SHOW TABLES;' 2>>"$err_file" | grep -Fxq -- "$table"; then
        existed=1
    fi

    if [ "$existed" -eq 1 ]; then
        if ! ( umask 077; dump_to_file "$safety_file" "$err_file.snap" local_mysqldump --single-transaction --triggers --set-gtid-purged=OFF "$db" "$table" ); then
            cat "$err_file.snap" >> "$err_file" 2>/dev/null; rm -f -- "${err_file:?}.snap"
            echo "Could not snapshot existing table '$db.$table'; leaving it untouched" >> "$err_file"
            rm -f -- "$safety_file"
            return 2
        fi
        rm -f -- "${err_file:?}.snap"
    fi

    local ok=1
    if [ "$drop_first" = "true" ]; then
        local_mysql "$db" -e "SET FOREIGN_KEY_CHECKS=0; DROP TABLE IF EXISTS $(sql_ident "$table")" 2>>"$err_file" || ok=0
    fi
    [ $ok -eq 1 ] && { _import_backup "$db" "$dump_file" "$err_file" import_args || ok=0; }
    if [ $ok -eq 1 ] && ! local_mysql -N -B "$db" -e 'SHOW TABLES;' 2>>"$err_file" | grep -Fxq -- "$table"; then
        echo "Import verification failed: table '$table' not found after import" >> "$err_file"
        ok=0
    fi

    if [ $ok -eq 1 ]; then
        _discard_safety "$safety_file"
        return 0
    fi

    local_mysql "$db" -e "SET FOREIGN_KEY_CHECKS=0; DROP TABLE IF EXISTS $(sql_ident "$table")" 2>>"$err_file"
    if [ "$existed" -eq 1 ]; then
        if _import_backup "$db" "$safety_file" "$err_file" import_args; then
            echo "Rolled back: previous contents of '$db.$table' restored" >> "$err_file"
            _discard_safety "$safety_file"
            return 1
        fi
        echo "ROLLBACK FAILED for '$db.$table'. Previous data is preserved in: $safety_file" >> "$err_file"
        return 3
    fi
    return 1
}

# Export functions for use in other scripts
export -f config_log
export -f load_config
export -f parse_database_list
export -f parse_table_sync_config
export -f validate_config
export -f test_database_connections
export -f show_config_summary
export -f init_config
export -f get_local_database_name
export -f get_mysqldump_options
export -f get_mysqldump_table_options
export -f is_debug_mode
export -f should_drop_existing_tables
export -f _cnf_escape _write_cnf cleanup_credentials init_credentials
export -f remote_mysql local_mysql remote_mysqldump
export -f sql_ident create_database_sql read_dump_options local_import_args
export -f backup_switches_database backup_ext dump_to_file read_backup backup_has_text backup_count_text cleanup_old_backups secure_dirs remote_bytes local_bytes check_disk_space check_disk_for_databases check_disk_for_tables report_tls_status _import_backup local_mysqldump _sql_str _discard_safety replace_local_database replace_local_table
export -f print_safety_usage parse_safety_args is_protected_database servers_are_same guard_plan local_db_exists confirm_plan plan_and_confirm_databases plan_and_confirm_tables

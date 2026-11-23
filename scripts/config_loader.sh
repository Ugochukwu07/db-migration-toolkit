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
    local file="$1" host="$2" port="$3" user="$4" pass="$5"
    case "$host$port$user$pass" in
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
    _write_cnf "$REMOTE_CNF" "$REMOTE_HOST" "${REMOTE_PORT:-3306}" "$REMOTE_USER" "$REMOTE_PASS" || return 1
    _write_cnf "$LOCAL_CNF" "${LOCAL_HOST:-localhost}" "${LOCAL_PORT:-3306}" "$LOCAL_USER" "$LOCAL_PASS" || return 1
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
}

# Extra mysql args for imports (sql_mode). Usage: local_import_args <array_name>
local_import_args() {
    local -n _args_ref=$1
    _args_ref=()
    if [ -n "${SQL_MODE:-}" ]; then
        _args_ref+=(--init-command="SET SESSION sql_mode='${SQL_MODE//\'/\'\'}'")
    fi
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

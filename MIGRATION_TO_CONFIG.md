# Migration to Externalized Configuration

This document describes the major improvements made to the Database Migration Toolkit to externalize all requirements to configuration files.

## What Changed

### Before: Hardcoded Values
Previously, database names, table specifications, and settings were hardcoded in individual scripts:

```bash
# In sync_databases.sh
DATABASES=("pref_db")

# In multi_thread_sync.sh  
DATABASES=("admin_db ads_db auth_db errandaar_db messaging_db...")

# In multi_thread_table_sync.sh
SYNC_CONFIG=(
    "errandaar_db:errandaar_db:referrals"
)
```

### After: Centralized Configuration
Now everything is externalized to `config/config.env`:

```bash
# Databases to sync (comma-separated)
SYNC_DATABASES="database1,database2,database3"

# Table sync configuration
TABLE_SYNC_CONFIG="source_db:target_db:table1,table2|another_db:local_another:*"

# Or multi-line format for complex configurations
TABLE_SYNC_CONFIG_MULTILINE="
source_db:target_db:table1,table2,table3
another_db:local_another:*
legacy_db:modern_db:users,orders,products
"
```

## New Configuration System

### 1. Configuration Loader (`scripts/config_loader.sh`)
A new configuration loading system that provides:
- **Centralized configuration loading**
- **Validation of all settings**
- **Database connection testing**
- **Error handling and logging**
- **Utility functions for common operations**

### 2. Enhanced Configuration File (`config/config.env.example`)
Comprehensive configuration covering:
- **Database connections** (remote and local)
- **Database lists** for synchronization
- **Table sync specifications** (single line and multi-line)
- **Performance settings** (threads, retries, timeouts)
- **Backup management** (retention, directories)
- **Advanced options** (character sets, SQL modes)
- **Notifications** (email, webhooks)
- **Debug and logging** settings

### 3. Environment-Specific Examples (`config/examples/`)
Pre-configured examples for different scenarios:
- **`development.env`** - Development environment settings
- **`staging.env`** - Staging environment configuration
- **`production.env`** - Production backup scenarios
- **`migration.env`** - Data migration projects

## Updated Scripts

### All Scripts Now Use Configuration
Every script has been updated to use the centralized configuration:

1. **`sync_databases.sh`** - Reads `SYNC_DATABASES` from config
2. **`multi_thread_sync.sh`** - Uses `SYNC_DATABASES` and all performance settings
3. **`multi_thread_table_sync.sh`** - Uses `TABLE_SYNC_CONFIG` or `TABLE_SYNC_CONFIG_MULTILINE`
4. **`import_from_backups.sh`** - Uses all backup and import settings
5. **`monitor_sync.sh`** - Uses monitoring intervals and directory settings
6. **`view_errors.sh`** - Uses configured directories to find error logs

### Configuration Loading Pattern
All scripts now follow this pattern:

```bash
# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the configuration loader
source "$SCRIPT_DIR/config_loader.sh"

# Initialize configuration
if ! init_config "$PROJECT_ROOT/config/config.env"; then
    log "ERROR" "Failed to initialize configuration"
    exit 1
fi
```

## Key Benefits

### 1. **No More Script Editing**
- No need to edit individual scripts
- All settings in one place
- Easy to manage multiple environments

### 2. **Environment-Specific Configurations**
```bash
# Development
cp config/examples/development.env config/config.env

# Staging  
cp config/examples/staging.env config/config.env

# Production
cp config/examples/production.env config/config.env
```

### 3. **Advanced Configuration Options**
- **Database naming**: `LOCAL_DB_PREFIX="dev_"`
- **Performance tuning**: `MAX_THREADS=8`
- **Backup management**: `BACKUP_RETENTION_DAYS=30`
- **Character sets**: `CHARSET="utf8mb4"`
- **SQL modes**: `SQL_MODE="TRADITIONAL"`
- **Custom mysqldump options**
- **Notification settings**

### 4. **Validation and Testing**
```bash
# Test configuration
./setup.sh --test

# Automatic validation on startup
VALIDATE_CONFIG="true"
TEST_CONNECTIONS="true"
```

## Configuration Formats

### Database Lists
```bash
# Simple comma-separated list
SYNC_DATABASES="db1,db2,db3"

# Real-world example
SYNC_DATABASES="user_management,product_catalog,order_processing,analytics"
```

### Table Sync Configurations
```bash
# Single line format (pipe-separated)
TABLE_SYNC_CONFIG="source_db:target_db:table1,table2|another_db:local_another:*"

# Multi-line format (recommended for complex setups)
TABLE_SYNC_CONFIG_MULTILINE="
production_app:dev_app:users,orders,products
analytics_db:dev_analytics:*
billing_db:dev_billing:invoices,payments,subscriptions
logs_db:dev_logs:error_logs,access_logs
"
```

### Table Sync Format Options
1. **Full format**: `"source_db:target_db:tables"`
2. **Legacy format**: `"source_db:tables"` (auto-generates target as `${LOCAL_DB_PREFIX}source_db`)
3. **Wildcard tables**: Use `*` for all tables
4. **Specific tables**: `table1,table2,table3`

## Migration Guide

### For Existing Users

1. **Backup your current configuration**:
   ```bash
   # Note your current database lists and settings
   grep -E "(DATABASES|SYNC_CONFIG)" scripts/*.sh
   ```

2. **Create your configuration**:
   ```bash
   # Copy the example
   cp config/config.env.example config/config.env
   
   # Edit with your settings
   nano config/config.env
   ```

3. **Migrate your database lists**:
   ```bash
   # Old way (in scripts)
   DATABASES=("db1" "db2" "db3")
   
   # New way (in config/config.env)
   SYNC_DATABASES="db1,db2,db3"
   ```

4. **Migrate your table configurations**:
   ```bash
   # Old way (in multi_thread_table_sync.sh)
   SYNC_CONFIG=(
       "source_db:target_db:table1,table2"
       "another_db:local_another:*"
   )
   
   # New way (in config/config.env)
   TABLE_SYNC_CONFIG="source_db:target_db:table1,table2|another_db:local_another:*"
   ```

5. **Test your configuration**:
   ```bash
   ./setup.sh --test
   ```

### For New Users

1. **Use the setup script**:
   ```bash
   ./setup.sh
   ```

2. **Choose an environment example**:
   ```bash
   # Development
   cp config/examples/development.env config/config.env
   
   # Staging
   cp config/examples/staging.env config/config.env
   ```

3. **Customize for your environment**:
   ```bash
   nano config/config.env
   ```

## Backwards Compatibility

The updated scripts are **fully backwards compatible**:
- If configuration is missing, scripts provide helpful error messages
- All existing functionality is preserved
- Default values are used when settings are not specified

## Documentation Updates

### New Documentation
- **`docs/CONFIGURATION.md`** - Comprehensive configuration guide
- **`config/examples/`** - Environment-specific examples
- **`MIGRATION_TO_CONFIG.md`** - This migration guide

### Updated Documentation
- **`README.md`** - Updated with new configuration approach
- **`QUICKSTART.md`** - Updated quick start examples
- **`docs/EXAMPLES.md`** - Updated usage examples

## Benefits Summary

✅ **Centralized Configuration** - All settings in one place  
✅ **Environment Management** - Easy switching between environments  
✅ **No Script Editing** - Configure without touching code  
✅ **Advanced Options** - Comprehensive customization  
✅ **Validation** - Automatic configuration validation  
✅ **Examples** - Pre-configured environment templates  
✅ **Documentation** - Comprehensive configuration guide  
✅ **Backwards Compatible** - Works with existing setups  

The Database Migration Toolkit is now much more flexible, maintainable, and user-friendly with this centralized configuration system!

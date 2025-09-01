# Multi-Threaded Table Synchronization Script

## Overview

The `multi_thread_table_sync.sh` script is designed to synchronize individual database tables from DigitalOcean to local databases using multi-threading for optimal performance. It maintains all the robust features of the original `multi_thread_sync.sh` script but focuses on table-level granular control.

## Key Features

- **Multi-threaded processing**: Sync multiple tables in parallel
- **Automatic retry mechanism**: Configurable retry attempts with delays
- **Progress monitoring**: Real-time progress tracking
- **Comprehensive logging**: Thread-safe logging with detailed error reporting
- **Table auto-discovery**: Automatically discover all tables in a database
- **Selective synchronization**: Sync specific tables or entire databases
- **Local database management**: Automatic local database creation
- **Error handling**: Robust error handling and recovery

## Configuration

### Environment Variables (config.env)

The script uses the same `config.env` file as the original script. Ensure you have:

```bash
# Remote DigitalOcean Database Configuration
REMOTE_HOST=your-do-database-host
REMOTE_PORT=25060
REMOTE_USER=your-username
REMOTE_PASS=your-password

# Local Database Configuration
LOCAL_USER=your-local-username
LOCAL_PASS=your-local-password

# Table Sync Specific Configuration
LOCAL_DB_PREFIX=local_          # Prefix for local databases (optional)
DROP_EXISTING_TABLE=true        # Drop existing tables before import
MAX_THREADS=4                   # Maximum concurrent threads
MAX_RETRY_ATTEMPTS=3            # Retry attempts per table
RETRY_DELAY=10                  # Delay between retries (seconds)
```

### Sync Configuration

Edit the script to configure which databases and tables to sync:

```bash
# Configuration examples with target database specification:
SYNC_CONFIG=(
    "errandaar_db:prod_errandaar:*"                    # Sync all tables to specified target
    "messaging_db:test_messaging:*"                    # Sync all tables to specified target
    "payment_db:local_payments:transactions,invoices"  # Sync specific tables to specified target
    "auth_db:custom_auth:users,sessions,tokens"       # Sync multiple specific tables
)

# Legacy format (auto-generates target database name):
SYNC_CONFIG=(
    "errandaar_db:*"                    # Target: test_local_errandaar_db (auto-generated)
    "messaging_db:messages,threads"     # Target: test_local_messaging_db (auto-generated)
)

# Mixed formats:
SYNC_CONFIG=(
    "errandaar_db:prod_errandaar:*"           # All tables to specific target
    "messaging_db:messages,threads"           # Specific tables to auto-generated target
    "auth_db:custom_auth:users,sessions"     # Specific tables to specific target
)
```

## Usage

### Basic Usage

```bash
# Make sure the script is executable
chmod +x multi_thread_table_sync.sh

# Run the synchronization
./multi_thread_table_sync.sh
```

### Configuration Options

1. **Sync all tables to specific target databases:**
   ```bash
   SYNC_CONFIG=(
       "source_db1:target_db1:*"
       "source_db2:target_db2:*"
   )
   ```

2. **Sync specific tables to specific targets:**
   ```bash
   SYNC_CONFIG=(
       "source_db1:target_db1:table1,table2,table3"
       "source_db2:target_db2:users,sessions"
   )
   ```

3. **Mixed configuration (new and legacy formats):**
   ```bash
   SYNC_CONFIG=(
       "main_db:prod_main:*"          # All tables to specific target
       "user_db:users,profiles"       # Specific tables to auto-generated target
       "log_db:custom_logs:error_logs"  # Single table to specific target
   )
   ```

## Local Database Naming

The script supports two approaches for database naming:

### New Format (Explicit Target):
- **Format**: `"source_db:target_db:tables"`
- **Example**: `"errandaar_db:prod_errandaar:*"` creates `prod_errandaar` database
- **Benefit**: Full control over target database names

### Legacy Format (Auto-Generated Target):
- **Format**: `"source_db:tables"`
- **Convention**: `test_{LOCAL_DB_PREFIX}source_db`
- **Example**: `"errandaar_db:*"` creates `test_local_errandaar_db` (with default prefix)

## Output Structure

### Backup Files
- Location: `./data/backups/multi_thread_table_sync/`
- Format: `{database}_{table}-{timestamp}.sql`
- Example: `errandaar_db_users-20240115_143022.sql`

### Log Files
- Status file: `./data/tmp/multi_thread_table_sync/sync_status-{timestamp}.tmp`
- Error log: `./data/tmp/multi_thread_table_sync/error_log-{timestamp}.tmp`
- Individual error logs: `{database}_{table}_dump_error-{timestamp}.log`

## Monitoring and Progress

The script provides real-time monitoring:

```
[2024-01-15 14:30:22] [INFO] [Thread-1234] Progress: 15/50 tables completed (120s elapsed)
[2024-01-15 14:30:25] [SUCCESS] [DB:errandaar_db] [Table:users] [Thread-5678] Table synchronization completed successfully in 45s (attempt 1/3)
```

## Error Handling

### Automatic Retry
- Each table sync has configurable retry attempts
- Exponential backoff between retries
- Detailed error logging for troubleshooting

### Common Issues and Solutions

1. **Connection errors:**
   - Check `config.env` credentials
   - Verify network connectivity to DigitalOcean

2. **Permission errors:**
   - Ensure local MySQL user has CREATE/DROP privileges
   - Check file system permissions on backup directories

3. **Large table timeouts:**
   - Increase MySQL timeout settings
   - Consider syncing large tables separately

## Performance Tuning

### Thread Configuration
```bash
# For high-performance systems
MAX_THREADS=8

# For limited resources
MAX_THREADS=2
```

### Memory Optimization
- Large tables are processed with `--single-transaction` and `--quick` flags
- Minimal memory footprint per thread
- Automatic cleanup of temporary files

## Security Considerations

1. **Password Security:**
   - Passwords are passed via environment variables
   - No passwords stored in command history
   - Automatic cleanup of temporary files

2. **Network Security:**
   - Uses encrypted connections to DigitalOcean
   - Local database access restricted to configured user

## Monitoring Script Status

### Check running processes:
```bash
ps aux | grep multi_thread_table_sync
```

### View real-time logs:
```bash
tail -f ./data/tmp/multi_thread_table_sync/sync_status-*.tmp
```

### Check for errors:
```bash
cat ./data/tmp/multi_thread_table_sync/error_log-*.tmp
```

## Integration with Existing Scripts

The table sync script is designed to complement the existing database sync script:

- Use `multi_thread_sync.sh` for full database synchronization
- Use `multi_thread_table_sync.sh` for selective table updates
- Both scripts share the same configuration and directory structure

## Troubleshooting

### Script won't start:
1. Check `config.env` exists and is readable
2. Verify MySQL client is installed
3. Test database connections manually

### Tables not syncing:
1. Verify table names are correct (case-sensitive)
2. Check source database permissions
3. Review error logs for specific issues

### Performance issues:
1. Reduce `MAX_THREADS` if system is overloaded
2. Check available disk space for backups
3. Monitor MySQL process list during sync

## Example Complete Workflow

```bash
# 1. Configure the sync
nano multi_thread_table_sync.sh
# Edit SYNC_CONFIG array

# 2. Test with a single table first
SYNC_CONFIG=("test_db:small_table")

# 3. Run the sync
./multi_thread_table_sync.sh

# 4. Monitor progress
tail -f ./data/tmp/multi_thread_table_sync/sync_status-*.tmp

# 5. Check results
mysql -u local_user -p local_test_db -e "SHOW TABLES;"
```

This script provides a robust, scalable solution for table-level database synchronization while maintaining all the reliability features of the original multi-threaded approach.

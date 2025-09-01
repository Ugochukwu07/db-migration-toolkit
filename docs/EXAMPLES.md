# Usage Examples

This document provides practical examples of how to use the Database Migration Toolkit for various scenarios.

## Basic Examples

### 1. Simple Database Sync

Synchronize a single database with basic configuration:

```bash
# Edit sync_databases.sh to specify databases
nano scripts/sync_databases.sh

# Update the DATABASES array
DATABASES=("my_app_db")

# Run synchronization
./scripts/sync_databases.sh
```

### 2. Multi-Database Sync

Synchronize multiple databases in parallel:

```bash
# Edit multi_thread_sync.sh
nano scripts/multi_thread_sync.sh

# Configure databases to sync
DATABASES=("user_db" "product_db" "order_db" "analytics_db")

# Run with 4 threads
./scripts/multi_thread_sync.sh
```

## Advanced Examples

### 3. Selective Table Synchronization

Sync specific tables from different databases:

```bash
# Edit multi_thread_table_sync.sh
nano scripts/multi_thread_table_sync.sh

# Configure specific table syncs
SYNC_CONFIG=(
    "production_db:local_prod:users,orders,products"
    "analytics_db:local_analytics:*"
    "logs_db:local_logs:error_logs,access_logs"
)

# Run table-level sync
./scripts/multi_thread_table_sync.sh
```

### 4. Development Environment Setup

Set up a complete development environment:

```bash
# Configuration for development
cat > config/config.env << 'EOF'
REMOTE_HOST="prod-db.company.com"
REMOTE_PORT="3306"
REMOTE_USER="readonly_user"
REMOTE_PASS="readonly_password"

LOCAL_USER="root"
LOCAL_PASS="dev_password"

MAX_THREADS=2  # Lower for dev machine
MAX_RETRY_ATTEMPTS=2
RETRY_DELAY=5
EOF

# Sync development databases
DATABASES=("app_db" "test_db")
./scripts/multi_thread_sync.sh
```

## Production Scenarios

### 5. Production to Staging Migration

Weekly staging database refresh:

```bash
#!/bin/bash
# weekly_staging_refresh.sh

# Configure for staging environment
export REMOTE_HOST="prod-cluster.company.com"
export REMOTE_PORT="25060"
export LOCAL_USER="staging_user"
export LOCAL_PASS="staging_password"

# Sync critical databases
DATABASES=(
    "user_management"
    "product_catalog" 
    "order_processing"
    "inventory_system"
)

# Run with monitoring
./scripts/run_with_monitor.sh

# Send notification
if [ $? -eq 0 ]; then
    echo "Staging refresh completed successfully" | mail -s "Staging Refresh" team@company.com
else
    echo "Staging refresh failed - check logs" | mail -s "Staging Refresh FAILED" team@company.com
fi
```

### 6. Disaster Recovery Sync

Emergency backup and sync scenario:

```bash
#!/bin/bash
# disaster_recovery.sh

# Emergency configuration
export MAX_THREADS=8  # Use all available resources
export MAX_RETRY_ATTEMPTS=5
export RETRY_DELAY=30

# Priority databases (most critical first)
DATABASES=(
    "customer_data"
    "financial_records"
    "user_accounts"
    "transaction_logs"
    "audit_trail"
)

# Run emergency sync
echo "Starting emergency database sync..."
./scripts/multi_thread_sync.sh

# Verify data integrity
echo "Verifying data integrity..."
for db in "${DATABASES[@]}"; do
    mysql -u"$LOCAL_USER" -p"$LOCAL_PASS" "test_$db" -e "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='test_$db';"
done
```

## Table-Level Examples

### 7. Customer Data Migration

Migrate customer-related tables across multiple databases:

```bash
# Configure customer data sync
SYNC_CONFIG=(
    "user_db:customer_db:users,profiles,preferences"
    "billing_db:customer_db:subscriptions,payments,invoices"
    "support_db:customer_db:tickets,interactions"
    "analytics_db:customer_db:user_metrics,behavior_data"
)

# Local database prefix
LOCAL_DB_PREFIX="customer_"

./scripts/multi_thread_table_sync.sh
```

### 8. Feature-Specific Table Sync

Sync tables for a specific application feature:

```bash
# E-commerce order processing tables
SYNC_CONFIG=(
    "main_db:ecommerce_local:products,categories,inventory"
    "order_db:ecommerce_local:orders,order_items,shipping"
    "payment_db:ecommerce_local:transactions,refunds"
    "user_db:ecommerce_local:customers,addresses"
)

# Drop existing tables for clean import
export DROP_EXISTING_TABLE="true"

./scripts/multi_thread_table_sync.sh
```

## Monitoring Examples

### 9. Automated Monitoring Setup

Set up continuous monitoring for long-running syncs:

```bash
#!/bin/bash
# monitored_sync.sh

# Start sync in background with logging
nohup ./scripts/multi_thread_sync.sh > sync_$(date +%Y%m%d_%H%M%S).log 2>&1 &
SYNC_PID=$!

# Monitor progress
./scripts/monitor_sync.sh &
MONITOR_PID=$!

# Set up cleanup on exit
trap 'kill $MONITOR_PID 2>/dev/null' EXIT

# Wait for sync completion
wait $SYNC_PID
SYNC_EXIT_CODE=$?

# Stop monitoring
kill $MONITOR_PID 2>/dev/null

if [ $SYNC_EXIT_CODE -eq 0 ]; then
    echo "Sync completed successfully"
else
    echo "Sync failed with exit code: $SYNC_EXIT_CODE"
    ./scripts/view_errors.sh
fi
```

### 10. Health Check Script

Regular health checks and maintenance:

```bash
#!/bin/bash
# health_check.sh

echo "=== Database Migration Toolkit Health Check ==="

# Check for running processes
if pgrep -f "multi_thread_sync" > /dev/null; then
    echo "✅ Sync processes are running"
    ./scripts/sync_status.sh
else
    echo "ℹ️  No sync processes currently running"
fi

# Check disk space
BACKUP_SIZE=$(du -sh data/backups/ 2>/dev/null | cut -f1)
AVAILABLE_SPACE=$(df . | tail -1 | awk '{print $4}')

echo "📁 Backup directory size: ${BACKUP_SIZE:-0}"
echo "💾 Available disk space: $((AVAILABLE_SPACE / 1024 / 1024))GB"

# Check recent errors
if [ -f "data/tmp/multi_thread_sync/error_log-"*.tmp ]; then
    RECENT_ERRORS=$(find data/tmp/*/error_log-*.tmp -mtime -1 2>/dev/null | wc -l)
    if [ $RECENT_ERRORS -gt 0 ]; then
        echo "⚠️  Recent errors found: $RECENT_ERRORS"
        echo "Run './scripts/view_errors.sh' for details"
    else
        echo "✅ No recent errors"
    fi
else
    echo "✅ No error logs found"
fi

# Check configuration
if [ -f "config/config.env" ]; then
    echo "✅ Configuration file exists"
    # Test local database connection
    if source config/config.env && mysql -u"$LOCAL_USER" -p"$LOCAL_PASS" -e "SELECT 1;" >/dev/null 2>&1; then
        echo "✅ Local database connection OK"
    else
        echo "❌ Local database connection failed"
    fi
else
    echo "❌ Configuration file missing"
fi
```

## Scheduled Operations

### 11. Cron Job Setup

Set up automated daily synchronization:

```bash
# Add to crontab: crontab -e

# Daily sync at 2 AM
0 2 * * * cd /path/to/database-migration-toolkit && ./scripts/multi_thread_sync.sh >> logs/cron_sync.log 2>&1

# Weekly full refresh on Sunday at 1 AM
0 1 * * 0 cd /path/to/database-migration-toolkit && ./scripts/run_with_monitor.sh >> logs/weekly_sync.log 2>&1

# Cleanup old backups weekly
0 3 * * 0 find /path/to/database-migration-toolkit/data/backups -name "*.sql" -mtime +7 -delete
```

### 12. Systemd Service

Create a systemd service for managed sync operations:

```ini
# /etc/systemd/system/db-migration.service
[Unit]
Description=Database Migration Toolkit
After=network.target

[Service]
Type=oneshot
User=dbmigration
Group=dbmigration
WorkingDirectory=/opt/database-migration-toolkit
ExecStart=/opt/database-migration-toolkit/scripts/multi_thread_sync.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
# Timer for regular execution
# /etc/systemd/system/db-migration.timer
[Unit]
Description=Run Database Migration Daily
Requires=db-migration.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

## Error Handling Examples

### 13. Robust Error Handling

Script with comprehensive error handling:

```bash
#!/bin/bash
# robust_sync.sh

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    echo "Error occurred in script at line $line_number: exit code $exit_code"
    
    # Stop any running sync processes
    ./scripts/stop_sync.sh
    
    # Send alert
    echo "Database sync failed at $(date)" | mail -s "DB Sync Error" admin@company.com
    
    exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Pre-sync validation
echo "Validating configuration..."
if ! source config/config.env; then
    echo "Configuration validation failed"
    exit 1
fi

# Test connections
echo "Testing database connections..."
if ! mysql -h"$REMOTE_HOST" -P"$REMOTE_PORT" -u"$REMOTE_USER" -p"$REMOTE_PASS" -e "SELECT 1;" >/dev/null; then
    echo "Remote database connection failed"
    exit 1
fi

if ! mysql -u"$LOCAL_USER" -p"$LOCAL_PASS" -e "SELECT 1;" >/dev/null; then
    echo "Local database connection failed"
    exit 1
fi

# Run sync with retries
MAX_ATTEMPTS=3
attempt=1

while [ $attempt -le $MAX_ATTEMPTS ]; do
    echo "Sync attempt $attempt/$MAX_ATTEMPTS"
    
    if ./scripts/multi_thread_sync.sh; then
        echo "Sync completed successfully on attempt $attempt"
        break
    else
        echo "Sync failed on attempt $attempt"
        if [ $attempt -eq $MAX_ATTEMPTS ]; then
            echo "All sync attempts failed"
            exit 1
        fi
        
        # Wait before retry
        sleep 300  # 5 minutes
        ((attempt++))
    fi
done

echo "Sync operation completed successfully"
```

## Performance Optimization Examples

### 14. High-Performance Configuration

Configuration optimized for large databases:

```bash
# High-performance config
export MAX_THREADS=16
export MAX_RETRY_ATTEMPTS=5
export RETRY_DELAY=60

# Optimize MySQL settings for large transfers
export MYSQL_CONNECT_TIMEOUT=300
export MYSQL_READ_TIMEOUT=1800

# Configure mysqldump for large datasets
export MYSQLDUMP_OPTS="--single-transaction --quick --lock-tables=false --routines --triggers"

# Use the configuration
./scripts/multi_thread_sync.sh
```

### 15. Resource-Constrained Environment

Configuration for limited resources:

```bash
# Resource-constrained config
export MAX_THREADS=1
export MAX_RETRY_ATTEMPTS=2
export RETRY_DELAY=30

# Sync one database at a time
DATABASES=("critical_db")

# Monitor resource usage
iostat -x 1 > io_stats.log &
IOSTAT_PID=$!

./scripts/sync_databases.sh

kill $IOSTAT_PID
```

These examples cover various real-world scenarios and can be adapted to specific requirements. Each example includes relevant configuration, error handling, and monitoring appropriate for the use case.

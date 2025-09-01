# Configuration Guide

The Database Migration Toolkit uses a comprehensive configuration system that allows you to externalize all database names, table specifications, and runtime settings. This guide explains how to configure the toolkit for your specific needs.

## Configuration File Structure

The main configuration file is `config/config.env`. All scripts read from this centralized configuration file, making it easy to manage your database migration settings.

### Basic Structure

```bash
# Remote database (source)
REMOTE_HOST="your-database-host.com"
REMOTE_USER="username"
REMOTE_PASS="password"

# Local database (target)
LOCAL_USER="root"
LOCAL_PASS="local-password"

# Database synchronization
SYNC_DATABASES="db1,db2,db3"

# Table synchronization
TABLE_SYNC_CONFIG="source_db:target_db:table1,table2|another_db:local_another:*"
```

## Configuration Categories

### 1. Database Connection Settings

#### Remote Database (Source)
```bash
REMOTE_HOST="your-remote-database-host.com"
REMOTE_PORT="3306"                    # Default: 3306
REMOTE_USER="your-remote-username"
REMOTE_PASS="your-remote-password"
```

#### Local Database (Target)
```bash
LOCAL_USER="root"
LOCAL_PASS="your-local-mysql-password"
LOCAL_HOST="localhost"                # Default: localhost
LOCAL_PORT="3306"                     # Default: 3306
```

### 2. Database Synchronization Settings

#### Simple Database List
```bash
# Comma-separated list of databases to sync
SYNC_DATABASES="database1,database2,database3"

# Examples:
SYNC_DATABASES="user_db,product_db,order_db"
SYNC_DATABASES="production_app"
SYNC_DATABASES="main_db,analytics_db,logs_db"
```

#### Database Naming
```bash
# Optional prefix for local databases
LOCAL_DB_PREFIX="dev_"               # Creates: dev_database1, dev_database2
LOCAL_DB_PREFIX="staging_"           # Creates: staging_database1, staging_database2
LOCAL_DB_PREFIX=""                   # Creates: database1, database2 (no prefix)
```

### 3. Table Synchronization Settings

#### Single Line Format
```bash
# Pipe-separated entries
TABLE_SYNC_CONFIG="source_db:target_db:tables|another_db:local_another:*"

# Examples:
TABLE_SYNC_CONFIG="user_db:local_users:*|product_db:local_products:products,categories"
TABLE_SYNC_CONFIG="main_db:dev_main:users,orders,products"
```

#### Multi-line Format (Recommended for Complex Configurations)
```bash
TABLE_SYNC_CONFIG_MULTILINE="
production_app:dev_app:users,orders,products
analytics_db:dev_analytics:*
billing_db:dev_billing:invoices,payments,subscriptions
logs_db:dev_logs:error_logs,access_logs
"
```

#### Table Sync Format Options

**1. Full Format with Target Database:**
```bash
"source_db:target_db:tables"
```
- `source_db` - Database on remote server
- `target_db` - Database name on local server
- `tables` - Comma-separated table list or "*" for all tables

**2. Legacy Format (Auto-generated Target):**
```bash
"source_db:tables"
```
- Target database name is auto-generated as `${LOCAL_DB_PREFIX}source_db`

**Examples:**
```bash
# Specific tables to specific target
"user_db:local_users:users,profiles,preferences"

# All tables to specific target
"analytics_db:local_analytics:*"

# Auto-generated target (creates: dev_auth_db)
LOCAL_DB_PREFIX="dev_"
"auth_db:users,sessions,tokens"
```

### 4. Performance and Threading Settings

```bash
# Performance tuning
MAX_THREADS=4                        # Concurrent operations (1-32)
MAX_RETRY_ATTEMPTS=3                 # Retry failed operations
RETRY_DELAY=10                       # Seconds between retries

# Monitoring
PROGRESS_REPORT_INTERVAL=5           # Progress update frequency
MONITOR_REFRESH_INTERVAL=2           # Monitor screen refresh rate

# MySQL timeouts
MYSQL_CONNECT_TIMEOUT=60             # Connection timeout (seconds)
MYSQL_READ_TIMEOUT=300               # Read timeout (seconds)
```

### 5. Backup and Storage Settings

```bash
# Backup management
BACKUP_RETENTION_DAYS=7              # Auto-cleanup old backups
BACKUP_DIR="data/backups"            # Backup storage location
DROP_EXISTING_TABLE="true"           # Drop tables before import

# Import settings
IMPORT_LOCAL_DB_PREFIX="imported_"   # Prefix for imported databases
IMPORT_BACKUP_DIR="./backups"        # Source for import operations
```

### 6. Advanced Database Settings

```bash
# Character sets and collation
CHARSET="utf8mb4"
COLLATION="utf8mb4_unicode_ci"

# SQL mode
SQL_MODE="TRADITIONAL"

# mysqldump customization
MYSQLDUMP_OPTIONS="--set-gtid-purged=OFF --skip-add-locks --skip-lock-tables --single-transaction --routines --triggers"
MYSQLDUMP_TABLE_OPTIONS="--set-gtid-purged=OFF --skip-add-locks --skip-lock-tables --skip-triggers --skip-opt --single-transaction --add-drop-table --create-options --extended-insert --quick --lock-tables=false"
```

### 7. Logging and Debug Settings

```bash
# Logging configuration
LOG_LEVEL="INFO"                     # DEBUG, INFO, WARN, ERROR
DEBUG_MODE="false"                   # Enable verbose debug output

# Validation
VALIDATE_CONFIG="true"               # Validate config on startup
TEST_CONNECTIONS="true"              # Test database connections
```

### 8. Notification Settings

```bash
# Email notifications
ENABLE_EMAIL_NOTIFICATIONS="true"
EMAIL_TO="admin@company.com"
EMAIL_FROM="dbsync@company.com"

# Webhook notifications (Slack, etc.)
ENABLE_WEBHOOK_NOTIFICATIONS="true"
WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

## Configuration Examples by Use Case

### Development Environment

```bash
# Basic development setup
REMOTE_HOST="prod-db.company.com"
REMOTE_USER="readonly_user"
REMOTE_PASS="readonly_password"

LOCAL_USER="root"
LOCAL_PASS="dev_password"

# Subset of databases for development
SYNC_DATABASES="app_db,user_db"

# Specific tables for feature development
TABLE_SYNC_CONFIG="app_db:dev_app:users,products,orders|user_db:dev_users:profiles"

# Conservative settings for dev machine
MAX_THREADS=2
DEBUG_MODE="true"
LOCAL_DB_PREFIX="dev_"
```

### Staging Environment

```bash
# Staging refresh configuration
REMOTE_HOST="prod-cluster.company.com"
REMOTE_PORT="25060"

# Full application databases
SYNC_DATABASES="main_app,user_management,product_catalog,analytics"

# Comprehensive table sync
TABLE_SYNC_CONFIG_MULTILINE="
main_app:staging_main:*
user_management:staging_users:*
product_catalog:staging_products:*
analytics:staging_analytics:user_metrics,sales_data
"

# Higher performance for staging server
MAX_THREADS=6
LOCAL_DB_PREFIX="staging_"
ENABLE_EMAIL_NOTIFICATIONS="true"
```

### Production Backup

```bash
# Production backup configuration
REMOTE_HOST="primary-prod.company.com"
LOCAL_HOST="backup-server.company.com"

# Critical databases
SYNC_DATABASES="customer_data,financial_records,transaction_logs"

# High-performance settings
MAX_THREADS=8
MAX_RETRY_ATTEMPTS=5
RETRY_DELAY=30

# Extended retention for compliance
BACKUP_RETENTION_DAYS=90
LOCAL_DB_PREFIX="backup_"
```

## Configuration Management

### Environment-Specific Configurations

Create separate configuration files for different environments:

```bash
config/
├── config.env.example          # Template
├── config.env                  # Your active config
└── examples/
    ├── development.env         # Development settings
    ├── staging.env            # Staging settings
    ├── production.env         # Production settings
    └── migration.env          # Data migration settings
```

### Using Configuration Examples

```bash
# Copy example to your config
cp config/examples/development.env config/config.env

# Edit for your environment
nano config/config.env

# Test configuration
./setup.sh --test
```

### Configuration Validation

The toolkit automatically validates your configuration:

```bash
# Manual validation
./setup.sh --test

# Automatic validation (enabled by default)
VALIDATE_CONFIG="true"
TEST_CONNECTIONS="true"
```

Common validation checks:
- Required variables are set
- Numeric values are within valid ranges
- Boolean values are true/false
- Port numbers are valid (1-65535)
- Database connections are working

## Security Best Practices

### 1. File Permissions
```bash
# Secure your configuration file
chmod 600 config/config.env

# The setup script does this automatically
./setup.sh
```

### 2. Environment Variables
For production, consider using environment variables:

```bash
# In config.env
REMOTE_PASS="${DB_REMOTE_PASSWORD}"
LOCAL_PASS="${DB_LOCAL_PASSWORD}"

# Set environment variables
export DB_REMOTE_PASSWORD="secure_remote_password"
export DB_LOCAL_PASSWORD="secure_local_password"
```

### 3. Version Control
Add to `.gitignore`:
```bash
# Configuration with sensitive data
config/config.env
```

Keep your actual configuration file out of version control.

## Troubleshooting Configuration

### Common Issues

**1. Configuration file not found:**
```bash
Error: config/config.env not found!
Solution: Copy config/config.env.example to config/config.env
```

**2. Database connection failed:**
```bash
Solution: Check REMOTE_HOST, REMOTE_USER, REMOTE_PASS
Test: mysql -h $REMOTE_HOST -u $REMOTE_USER -p
```

**3. Invalid configuration values:**
```bash
Error: MAX_THREADS must be a number between 1 and 32
Solution: Set MAX_THREADS=4 (or valid number)
```

**4. Permission denied:**
```bash
Solution: chmod 600 config/config.env
Solution: ./setup.sh (fixes permissions automatically)
```

### Debug Configuration

Enable debug mode to see detailed configuration information:

```bash
DEBUG_MODE="true"
LOG_LEVEL="DEBUG"

# Run any script to see config details
./scripts/sync_databases.sh
```

### Configuration Testing

Test your configuration before running sync:

```bash
# Test configuration only
./setup.sh --test

# Validate specific settings
source config/config.env
mysql -h $REMOTE_HOST -u $REMOTE_USER -p$REMOTE_PASS -e "SELECT VERSION();"
```

## Advanced Configuration Topics

### Dynamic Configuration

For complex setups, you can use shell scripting in your configuration:

```bash
# Dynamic database list based on environment
if [ "$ENVIRONMENT" = "production" ]; then
    SYNC_DATABASES="critical_db1,critical_db2,critical_db3"
else
    SYNC_DATABASES="test_db1,test_db2"
fi

# Dynamic threading based on system
AVAILABLE_CORES=$(nproc)
MAX_THREADS=$((AVAILABLE_CORES / 2))
```

### Configuration Inheritance

Create base configurations and extend them:

```bash
# base.env
REMOTE_HOST="shared-host.company.com"
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=10

# development.env
source ./base.env
LOCAL_DB_PREFIX="dev_"
MAX_THREADS=2
DEBUG_MODE="true"
```

This configuration system provides complete flexibility while maintaining simplicity for basic use cases. All scripts automatically use these centralized settings, ensuring consistency across your database migration operations.

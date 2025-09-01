# Quick Start Guide

Get up and running with the Database Migration Toolkit in 5 minutes!

## 🚀 Installation

### Option 1: Local Installation

```bash
# 1. Clone/download the project
cd /path/to/your/projects
git clone <repository-url> database-migration-toolkit
cd database-migration-toolkit

# 2. Run setup
./setup.sh

# 3. Configure your databases
nano config/config.env
# Update with your actual database credentials
```

### Option 2: Docker Installation

```bash
# 1. Clone the project
git clone <repository-url> database-migration-toolkit
cd database-migration-toolkit

# 2. Configure for Docker
cp docker.env.example .env
nano .env  # Update with your credentials

# 3. Build and run
docker-compose build
docker-compose up -d db-migration
docker-compose exec db-migration bash
```

## ⚡ Quick Sync

### Sync a Single Database

```bash
# Edit the configuration file
nano config/config.env

# Set your database:
SYNC_DATABASES="your_database_name"

# Run the sync
./scripts/sync_databases.sh
```

### Multi-Database Sync with Monitoring

```bash
# Edit the configuration file
nano config/config.env

# Set your databases:
SYNC_DATABASES="db1,db2,db3"

# Run with monitoring
./scripts/run_with_monitor.sh
```

### Specific Table Sync

```bash
# Edit the configuration file
nano config/config.env

# Configure specific tables:
TABLE_SYNC_CONFIG="source_db:target_db:table1,table2,table3"

# Run table sync
./scripts/multi_thread_table_sync.sh
```

## 📊 Monitor Progress

```bash
# Real-time monitoring dashboard
./scripts/monitor_sync.sh

# Quick status check
./scripts/sync_status.sh

# View any errors
./scripts/view_errors.sh

# Stop all processes
./scripts/stop_sync.sh
```

## 🛠️ Configuration

**Essential settings in `config/config.env`:**

```bash
# Remote database (source)
REMOTE_HOST="your-remote-host"
REMOTE_USER="your-username"
REMOTE_PASS="your-password"

# Local database (destination)
LOCAL_USER="root"
LOCAL_PASS="your-local-password"

# Performance settings
MAX_THREADS=4              # Concurrent operations
MAX_RETRY_ATTEMPTS=3       # Retry failed operations
RETRY_DELAY=10            # Seconds between retries
```

## 🎯 Common Use Cases

### Development Environment Setup
```bash
# In config/config.env
SYNC_DATABASES="app_db,user_db"
MAX_THREADS=2  # Lower for dev machine
LOCAL_DB_PREFIX="dev_"

./scripts/multi_thread_sync.sh
```

### Staging Refresh
```bash
# In config/config.env
SYNC_DATABASES="main_db,analytics_db,logs_db"
MAX_THREADS=6
LOCAL_DB_PREFIX="staging_"

./scripts/run_with_monitor.sh
```

### Selective Data Migration
```bash
# In config/config.env
TABLE_SYNC_CONFIG="prod_db:feature_db:users,orders,products|analytics_db:feature_db:user_events,metrics"

./scripts/multi_thread_table_sync.sh
```

## 🔧 Troubleshooting

**Connection issues:**
```bash
# Test connections manually
mysql -h REMOTE_HOST -P REMOTE_PORT -u REMOTE_USER -p
mysql -u LOCAL_USER -p
```

**Permission errors:**
```bash
# Fix directory permissions
chmod -R 755 data/
./setup.sh  # Re-run setup
```

**Large database timeouts:**
```bash
# Reduce thread count for large databases
export MAX_THREADS=1
export RETRY_DELAY=60
./scripts/multi_thread_sync.sh
```

## 📚 Next Steps

- **Read the full documentation**: `README.md`
- **Check examples**: `docs/EXAMPLES.md`
- **Docker deployment**: `docs/DOCKER.md`
- **Contributing**: `CONTRIBUTING.md`

## 💡 Pro Tips

1. **Start small**: Test with one small database first
2. **Monitor resources**: Use `htop` or similar during large syncs
3. **Schedule wisely**: Run heavy syncs during off-peak hours
4. **Backup first**: Always backup your local databases before syncing
5. **Use monitoring**: The monitoring tools help track progress and catch issues early

## 🆘 Getting Help

- **Check logs**: `./scripts/view_errors.sh`
- **Configuration test**: `./setup.sh --test`
- **GitHub Issues**: Report bugs and request features
- **Documentation**: `docs/` directory has detailed guides

Happy syncing! 🎉

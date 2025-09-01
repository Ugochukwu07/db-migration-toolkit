# Database Migration Toolkit

A comprehensive, multi-threaded database synchronization toolkit for migrating databases from remote sources (like DigitalOcean) to local MySQL instances. This toolkit provides both full database synchronization and granular table-level synchronization with robust error handling, monitoring, and retry mechanisms.

## Features

### 🚀 Core Capabilities
- **Multi-threaded Processing**: Parallel database/table synchronization for optimal performance
- **Robust Error Handling**: Automatic retry mechanisms with configurable attempts and delays
- **Real-time Monitoring**: Live progress tracking with dedicated monitoring dashboard
- **Flexible Synchronization**: Full database sync or selective table-level synchronization
- **Comprehensive Logging**: Thread-safe logging with detailed error reporting
- **Backup Management**: Automatic backup creation with timestamped files

### 🛠️ Advanced Features
- **Auto-discovery**: Automatically discover tables in source databases
- **Selective Sync**: Sync specific tables or entire databases
- **Local Database Management**: Automatic local database creation and cleanup
- **Progress Monitoring**: Real-time progress tracking with monitoring tools
- **Resource Management**: Configurable thread limits and retry policies
- **Security**: Password handling via environment variables

## Quick Start

### 1. Prerequisites

```bash
# MySQL client tools
sudo apt-get install mysql-client

# Required for monitoring (optional)
sudo apt-get install gnome-terminal  # or xterm, konsole
```

### 2. Setup

```bash
# Clone or download the toolkit
git clone <repository-url>
cd database-migration-toolkit

# Make scripts executable
chmod +x scripts/*.sh

# Setup configuration
cp config/config.env.example config/config.env
# Edit config/config.env with your database credentials
```

### 3. Configuration

Edit `config/config.env`:

```bash
# Remote Database (source)
REMOTE_HOST="your-remote-database-host"
REMOTE_PORT="3306"
REMOTE_USER="your-username"
REMOTE_PASS="your-password"

# Local Database (target)
LOCAL_USER="root"
LOCAL_PASS="your-local-password"

# Databases to sync (comma-separated)
SYNC_DATABASES="database1,database2,database3"

# Table sync configuration (pipe-separated)
TABLE_SYNC_CONFIG="source_db:target_db:table1,table2|another_db:local_another:*"

# Performance settings
MAX_THREADS=4
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=10
```

### 4. Run Synchronization

```bash
# Full database synchronization with monitoring
./scripts/run_with_monitor.sh

# Or run individual components
./scripts/sync_databases.sh          # Simple sync
./scripts/multi_thread_sync.sh       # Multi-threaded full sync
./scripts/multi_thread_table_sync.sh # Table-level sync
```

## Usage Guide

### Full Database Synchronization

The `multi_thread_sync.sh` script synchronizes entire databases in parallel:

```bash
# Configure databases in config/config.env
SYNC_DATABASES="database1,database2,database3"

# Run synchronization
./scripts/multi_thread_sync.sh
```

**Features:**
- Parallel database processing
- Automatic retry on failures
- Comprehensive error logging
- Progress monitoring
- Backup file creation

### Table-Level Synchronization

The `multi_thread_table_sync.sh` script provides granular table synchronization:

```bash
# Configure in config/config.env
TABLE_SYNC_CONFIG="source_db:target_db:table1,table2,table3|another_db:local_another:*"

# Or use multi-line format for complex configurations
TABLE_SYNC_CONFIG_MULTILINE="
source_db:target_db:table1,table2,table3
another_db:local_another:*
legacy_db:modern_db:users,orders,products
"

# Run table sync
./scripts/multi_thread_table_sync.sh
```

**Configuration Options:**
- `source_db:target_db:table1,table2` - Specific tables to specific target
- `source_db:target_db:*` - All tables to specific target
- `source_db:table1,table2` - Tables to auto-generated target database

### Monitoring and Management

**Start with monitoring:**
```bash
./scripts/run_with_monitor.sh
```

**Monitor existing sync:**
```bash
./scripts/monitor_sync.sh
```

**Check status:**
```bash
./scripts/sync_status.sh
```

**Stop synchronization:**
```bash
./scripts/stop_sync.sh
```

**View errors:**
```bash
./scripts/view_errors.sh
```

## Directory Structure

```
database-migration-toolkit/
├── README.md                       # This file
├── LICENSE                         # Open source license
├── config/
│   ├── config.env.example         # Example configuration
│   └── config.env                 # Your configuration (create from example)
├── scripts/
│   ├── sync_databases.sh          # Simple database sync
│   ├── multi_thread_sync.sh       # Multi-threaded database sync
│   ├── multi_thread_table_sync.sh # Multi-threaded table sync
│   ├── run_with_monitor.sh        # Start sync with monitoring
│   ├── monitor_sync.sh            # Real-time monitoring dashboard
│   ├── sync_status.sh             # Quick status check
│   ├── stop_sync.sh               # Stop all sync processes
│   ├── view_errors.sh             # Error log viewer
│   └── import_from_backups.sh     # Import from existing backups
├── data/
│   ├── backups/                   # Database backup files
│   ├── logs/                      # Log files
│   └── tmp/                       # Temporary files
├── config/
│   ├── config.env.example         # Example configuration
│   ├── config.env                 # Your configuration (create from example)
│   └── examples/                  # Environment-specific examples
│       ├── development.env        # Development environment
│       ├── staging.env           # Staging environment
│       ├── production.env        # Production environment
│       └── migration.env         # Data migration project
└── docs/
    ├── CONFIGURATION.md           # Detailed configuration guide
    ├── DOCKER.md                  # Docker deployment guide
    └── EXAMPLES.md                # Usage examples
```

## Configuration Details

> 📖 **For comprehensive configuration documentation, see [docs/CONFIGURATION.md](docs/CONFIGURATION.md)**

### Core Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `REMOTE_HOST` | Remote database hostname | - | Yes |
| `REMOTE_PORT` | Remote database port | 3306 | Yes |
| `REMOTE_USER` | Remote database username | - | Yes |
| `REMOTE_PASS` | Remote database password | - | Yes |
| `LOCAL_USER` | Local MySQL username | root | Yes |
| `LOCAL_PASS` | Local MySQL password | - | Yes |
| `MAX_THREADS` | Maximum concurrent threads | 4 | No |
| `MAX_RETRY_ATTEMPTS` | Retry attempts on failure | 3 | No |
| `RETRY_DELAY` | Delay between retries (seconds) | 10 | No |

### Database Configuration

All configuration is now centralized in `config/config.env`:

**Multi-threaded Database Sync**:
```bash
# In config/config.env
SYNC_DATABASES="database1,database2,database3"
```

**Table-level Sync**:
```bash
# In config/config.env
TABLE_SYNC_CONFIG="source_db:target_db:table1,table2|source_db:target_db:*"

# Or multi-line format
TABLE_SYNC_CONFIG_MULTILINE="
source_db:target_db:table1,table2
source_db:target_db:*
source_db:table1,table2
"
```

## Monitoring Features

### Real-time Dashboard
The monitoring dashboard (`monitor_sync.sh`) provides:
- 🚀 Active process tracking
- 📊 Progress statistics
- 📁 Backup file status
- 🚨 Error details
- 🔄 Retry activity
- 💻 System resource usage

### Status Checking
Quick status check (`sync_status.sh`) shows:
- Current running processes
- Recent backup files
- Success/failure counts
- Quick action commands

## Error Handling

### Automatic Retry
- Configurable retry attempts per database/table
- Exponential backoff between retries
- Detailed error logging for troubleshooting

### Error Types
- **DUMP_ERROR**: Issues dumping from remote database
- **PREP_ERROR**: Local database preparation problems
- **IMPORT_ERROR**: Issues importing data locally

### Error Viewing
```bash
./scripts/view_errors.sh  # Comprehensive error analysis
```

## Performance Tuning

### Thread Configuration
```bash
# High-performance systems
MAX_THREADS=8

# Limited resources
MAX_THREADS=2
```

### Memory Optimization
- Large tables processed with `--single-transaction` and `--quick` flags
- Minimal memory footprint per thread
- Automatic cleanup of temporary files

## Security Considerations

1. **Password Security**: Passwords passed via environment variables
2. **Network Security**: Uses encrypted connections to remote database
3. **File Permissions**: Automatic cleanup of temporary files
4. **Local Access**: Local database access restricted to configured user

## Troubleshooting

### Common Issues

**Connection errors:**
- Check `config.env` credentials
- Verify network connectivity to remote database

**Permission errors:**
- Ensure local MySQL user has CREATE/DROP privileges
- Check file system permissions on backup directories

**Large table timeouts:**
- Increase MySQL timeout settings
- Consider syncing large tables separately
- Reduce thread count for resource-limited systems

### Debug Commands

```bash
# Check processes
ps aux | grep multi_thread_sync

# Monitor logs
tail -f data/logs/sync_progress.log

# Check MySQL connections
mysql -h REMOTE_HOST -P REMOTE_PORT -u REMOTE_USER -p

# Verify local database
mysql -u LOCAL_USER -p -e "SHOW DATABASES;"
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- 📖 Documentation: Check the `docs/` directory for detailed guides
- 🐛 Issues: Report bugs via GitHub issues
- 💬 Discussion: Start a discussion for questions and ideas

## Changelog

### Version 1.0.0
- Initial release with multi-threaded database synchronization
- Real-time monitoring and error handling
- Table-level synchronization support
- Comprehensive logging and retry mechanisms

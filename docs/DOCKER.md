# Docker Deployment Guide

This guide explains how to run the Database Migration Toolkit using Docker containers.

## Quick Start with Docker

### Prerequisites
- Docker Engine 20.10+
- Docker Compose 2.0+

### Basic Setup

1. **Clone and prepare the project:**
   ```bash
   git clone <repository-url>
   cd database-migration-toolkit
   ```

2. **Create configuration:**
   ```bash
   # Copy and edit configuration
   cp config/config.env.example config/config.env
   cp docker.env.example .env
   
   # Edit both files with your database credentials
   nano config/config.env
   nano .env
   ```

3. **Build and run:**
   ```bash
   # Build the container
   docker-compose build
   
   # Start the toolkit
   docker-compose up -d db-migration
   
   # Access the container
   docker-compose exec db-migration bash
   ```

## Container Usage

### Running Scripts Inside Container

Once inside the container, you can run any of the migration scripts:

```bash
# Inside the container
./scripts/sync_databases.sh
./scripts/multi_thread_sync.sh
./scripts/multi_thread_table_sync.sh
```

### One-shot Execution

Run a script without entering the container:

```bash
# Run specific script
docker-compose exec db-migration ./scripts/sync_databases.sh

# Run with custom parameters
docker-compose exec db-migration bash -c "cd /app && ./scripts/multi_thread_sync.sh"
```

## Configuration Options

### Environment Variables

Set these in your `.env` file:

```bash
# Required
REMOTE_HOST=your-remote-db-host.com
REMOTE_USER=your-username
REMOTE_PASS=your-password
LOCAL_USER=root
LOCAL_PASS=your-local-password

# Optional
MAX_THREADS=4
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY=10
```

### Volume Mounts

The docker-compose setup includes these volume mounts:

- `./config:/app/config` - Configuration files
- `./data:/app/data` - Backup files, logs, and temporary data
- `./scripts:/app/scripts` - Custom scripts (optional)

## Complete Setup with Local MySQL

### Start Everything

```bash
# Start both migration toolkit and local MySQL
docker-compose up -d

# Check status
docker-compose ps
```

### Configure Local MySQL Connection

Update your `config/config.env` to use the containerized MySQL:

```bash
# For connecting to the local MySQL container
LOCAL_HOST=mysql-local  # Container name
LOCAL_USER=root
LOCAL_PASS=rootpassword  # From MYSQL_ROOT_PASSWORD
```

### Access Local MySQL

```bash
# Connect to MySQL container
docker-compose exec mysql-local mysql -uroot -prootpassword

# Or from migration container
docker-compose exec db-migration mysql -hmysql-local -uroot -prootpassword
```

## Advanced Usage

### Custom Dockerfile

If you need to customize the container, modify the `Dockerfile`:

```dockerfile
# Add custom packages
RUN apt-get update && apt-get install -y \
    your-custom-package \
    && rm -rf /var/lib/apt/lists/*

# Add custom scripts
COPY your-scripts/ ./custom-scripts/
```

### Development Setup

For development, use volume mounts to edit files on the host:

```yaml
services:
  db-migration:
    build: .
    volumes:
      - .:/app  # Mount entire project
    working_dir: /app
```

### Production Deployment

For production, consider:

1. **Security:**
   ```yaml
   services:
     db-migration:
       build: .
       user: "1000:1000"  # Non-root user
       read_only: true    # Read-only filesystem
       tmpfs:
         - /tmp
         - /app/data/tmp
   ```

2. **Resource Limits:**
   ```yaml
   services:
     db-migration:
       deploy:
         resources:
           limits:
             cpus: '2.0'
             memory: 2G
           reservations:
             cpus: '1.0'
             memory: 1G
   ```

3. **Monitoring:**
   ```yaml
   services:
     db-migration:
       healthcheck:
         test: ["CMD", "bash", "-c", "ps aux | grep -q '[m]ulti_thread_sync' || exit 0"]
         interval: 30s
         timeout: 10s
         retries: 3
   ```

## Troubleshooting

### Common Issues

**Permission denied errors:**
```bash
# Fix ownership
sudo chown -R $USER:$USER ./data
chmod -R 755 ./data
```

**Connection refused:**
```bash
# Check network connectivity
docker-compose exec db-migration ping mysql-local
docker-compose exec db-migration nc -zv your-remote-host 3306
```

**Container won't start:**
```bash
# Check logs
docker-compose logs db-migration
docker-compose logs mysql-local

# Rebuild without cache
docker-compose build --no-cache
```

### Debugging

**Enter container for debugging:**
```bash
# Start bash shell
docker-compose exec db-migration bash

# Check environment
docker-compose exec db-migration env | grep -E "(REMOTE_|LOCAL_)"

# Test database connections
docker-compose exec db-migration mysql -h${REMOTE_HOST} -P${REMOTE_PORT} -u${REMOTE_USER} -p${REMOTE_PASS} -e "SELECT VERSION();"
```

**Monitor container resources:**
```bash
# Resource usage
docker stats

# Container processes
docker-compose exec db-migration ps aux
```

## Cleanup

### Stop and Remove

```bash
# Stop services
docker-compose down

# Remove volumes (⚠️ deletes data)
docker-compose down -v

# Remove images
docker-compose down --rmi all
```

### Backup Before Cleanup

```bash
# Backup data
tar -czf migration-backup-$(date +%Y%m%d).tar.gz data/

# Export MySQL data
docker-compose exec mysql-local mysqldump -uroot -prootpassword --all-databases > mysql-backup.sql
```

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Database Migration
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  migrate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup environment
        run: |
          echo "REMOTE_HOST=${{ secrets.REMOTE_HOST }}" > .env
          echo "REMOTE_USER=${{ secrets.REMOTE_USER }}" >> .env
          echo "REMOTE_PASS=${{ secrets.REMOTE_PASS }}" >> .env
      - name: Run migration
        run: |
          docker-compose up --build -d
          docker-compose exec -T db-migration ./scripts/multi_thread_sync.sh
```

This Docker setup provides a consistent, portable environment for running database migrations across different systems and deployment scenarios.

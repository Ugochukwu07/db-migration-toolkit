#!/bin/bash

# ==============================================
# Database Migration Toolkit Setup Script
# ==============================================
# This script sets up the environment and dependencies
# for the Database Migration Toolkit

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project information
PROJECT_NAME="Database Migration Toolkit"
VERSION="1.0.0"

echo -e "${CYAN}=================================="
echo -e "🚀 $PROJECT_NAME Setup"
echo -e "Version: $VERSION"
echo -e "==================================${NC}"
echo ""

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "ERROR")
            echo -e "[$timestamp] ${RED}[ERROR]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "[$timestamp] ${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARN")
            echo -e "[$timestamp] ${YELLOW}[WARN]${NC} $message"
            ;;
        "INFO")
            echo -e "[$timestamp] ${BLUE}[INFO]${NC} $message"
            ;;
        *)
            echo -e "[$timestamp] [INFO] $message"
            ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check system requirements
check_system_requirements() {
    log "INFO" "Checking system requirements..."
    
    local requirements_met=true
    
    # Check for bash
    if ! command_exists bash; then
        log "ERROR" "Bash is required but not found"
        requirements_met=false
    else
        local bash_version=$(bash --version | head -n1 | cut -d' ' -f4 | cut -d'(' -f1)
        log "SUCCESS" "Bash found: $bash_version"
    fi
    
    # Check for MySQL client
    if ! command_exists mysql; then
        log "ERROR" "MySQL client is required but not found"
        log "INFO" "Install with: sudo apt-get install mysql-client (Ubuntu/Debian)"
        log "INFO" "Or: sudo yum install mysql (CentOS/RHEL)"
        log "INFO" "Or: brew install mysql-client (macOS)"
        requirements_met=false
    else
        local mysql_version=$(mysql --version | cut -d' ' -f6 | cut -d',' -f1)
        log "SUCCESS" "MySQL client found: $mysql_version"
    fi
    
    # Check for mysqldump
    if ! command_exists mysqldump; then
        log "ERROR" "mysqldump is required but not found"
        log "INFO" "Usually comes with mysql-client package"
        requirements_met=false
    else
        log "SUCCESS" "mysqldump found"
    fi
    
    # Check for basic utilities
    for cmd in grep sed awk cut tr wc find; do
        if ! command_exists "$cmd"; then
            log "ERROR" "$cmd is required but not found"
            requirements_met=false
        fi
    done
    
    if [ "$requirements_met" = true ]; then
        log "SUCCESS" "All system requirements met!"
        return 0
    else
        log "ERROR" "Some system requirements are missing"
        return 1
    fi
}

# Function to check optional dependencies
check_optional_dependencies() {
    log "INFO" "Checking optional dependencies..."
    
    # Terminal emulators for monitoring
    local terminal_found=false
    for terminal in gnome-terminal xterm konsole; do
        if command_exists "$terminal"; then
            log "SUCCESS" "Terminal emulator found: $terminal"
            terminal_found=true
            break
        fi
    done
    
    if [ "$terminal_found" = false ]; then
        log "WARN" "No supported terminal emulator found"
        log "INFO" "Install one of: gnome-terminal, xterm, or konsole for monitoring features"
    fi
    
    # Check for Docker (optional)
    if command_exists docker; then
        local docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        log "SUCCESS" "Docker found: $docker_version"
    else
        log "INFO" "Docker not found (optional for containerized deployment)"
    fi
}

# Function to setup directory structure
setup_directories() {
    log "INFO" "Setting up directory structure..."
    
    local dirs=("scripts" "config" "docs" "data" "data/backups" "data/logs" "data/tmp")
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log "SUCCESS" "Created directory: $dir"
        else
            log "INFO" "Directory exists: $dir"
        fi
    done
    
    # Set proper permissions
    chmod 755 scripts config docs
    chmod 750 data data/backups data/logs data/tmp
    
    log "SUCCESS" "Directory structure setup complete"
}

# Function to setup configuration
setup_configuration() {
    log "INFO" "Setting up configuration..."
    
    if [ ! -f "config/config.env" ]; then
        if [ -f "config/config.env.example" ]; then
            cp "config/config.env.example" "config/config.env"
            log "SUCCESS" "Created config/config.env from example"
            log "WARN" "Please edit config/config.env with your database credentials"
        else
            log "ERROR" "config/config.env.example not found"
            return 1
        fi
    else
        log "INFO" "Configuration file already exists: config/config.env"
    fi
    
    # Secure the config file
    chmod 600 "config/config.env"
    log "SUCCESS" "Set secure permissions on config file"
}

# Function to make scripts executable
setup_scripts() {
    log "INFO" "Setting up script permissions..."
    
    if [ -d "scripts" ]; then
        chmod +x scripts/*.sh 2>/dev/null || true
        chmod +x *.sh 2>/dev/null || true  # For any scripts in root
        log "SUCCESS" "Made scripts executable"
    else
        log "WARN" "Scripts directory not found"
    fi
}

# Function to create gitignore
setup_gitignore() {
    log "INFO" "Setting up .gitignore..."
    
    cat > .gitignore << 'EOF'
# Configuration with sensitive data
config/config.env

# Backup files
data/backups/
*.sql

# Log files
data/logs/
*.log
sync_progress.log

# Temporary files
data/tmp/
*.tmp
sync_pids.tmp

# OS specific files
.DS_Store
Thumbs.db

# Editor files
*.swp
*.swo
*~
.vscode/
.idea/

# Runtime files
*.pid
nohup.out
EOF
    
    log "SUCCESS" "Created .gitignore file"
}

# Function to test configuration
test_configuration() {
    log "INFO" "Testing configuration..."
    
    if [ ! -f "config/config.env" ]; then
        log "WARN" "Configuration file not found - skipping test"
        return 0
    fi
    
    # Source config with error handling
    if ! source "config/config.env" 2>/dev/null; then
        log "ERROR" "Failed to source configuration file"
        return 1
    fi
    
    # Check required variables
    local required_vars=("REMOTE_HOST" "REMOTE_USER" "REMOTE_PASS" "LOCAL_USER" "LOCAL_PASS")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -eq 0 ]; then
        log "SUCCESS" "All required configuration variables are set"
        
        # Test local MySQL connection (optional)
        if mysql -u"$LOCAL_USER" -p"$LOCAL_PASS" -e "SELECT VERSION();" >/dev/null 2>&1; then
            log "SUCCESS" "Local MySQL connection test passed"
        else
            log "WARN" "Local MySQL connection test failed - please verify credentials"
        fi
    else
        log "WARN" "Missing configuration variables: ${missing_vars[*]}"
        log "INFO" "Please edit config/config.env to set these variables"
    fi
}

# Function to display next steps
display_next_steps() {
    echo ""
    echo -e "${CYAN}=================================="
    echo -e "✅ Setup Complete!"
    echo -e "==================================${NC}"
    echo ""
    echo -e "${YELLOW}📋 NEXT STEPS:${NC}"
    echo ""
    echo -e "${BLUE}1. Configure Database Settings:${NC}"
    echo -e "   Edit config/config.env with your database credentials"
    echo -e "   ${CYAN}nano config/config.env${NC}"
    echo ""
    echo -e "${BLUE}2. Test Configuration:${NC}"
    echo -e "   ${CYAN}./setup.sh --test${NC}"
    echo ""
    echo -e "${BLUE}3. Start Synchronization:${NC}"
    echo -e "   ${CYAN}./scripts/run_with_monitor.sh${NC}     # Full sync with monitoring"
    echo -e "   ${CYAN}./scripts/sync_databases.sh${NC}       # Simple sync"
    echo -e "   ${CYAN}./scripts/multi_thread_sync.sh${NC}    # Multi-threaded sync"
    echo ""
    echo -e "${BLUE}4. Monitor Progress:${NC}"
    echo -e "   ${CYAN}./scripts/monitor_sync.sh${NC}         # Real-time monitoring"
    echo -e "   ${CYAN}./scripts/sync_status.sh${NC}          # Quick status check"
    echo ""
    echo -e "${BLUE}5. Manage Synchronization:${NC}"
    echo -e "   ${CYAN}./scripts/stop_sync.sh${NC}            # Stop all sync processes"
    echo -e "   ${CYAN}./scripts/view_errors.sh${NC}          # View error logs"
    echo ""
    echo -e "${YELLOW}📖 Documentation:${NC}"
    echo -e "   README.md - Complete usage guide"
    echo -e "   docs/ - Detailed documentation"
    echo ""
    echo -e "${GREEN}🎉 Ready to use! Happy syncing!${NC}"
}

# Main setup function
main() {
    # Parse command line arguments
    case "${1:-}" in
        --test|-t)
            log "INFO" "Running configuration test only..."
            test_configuration
            exit $?
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --test, -t     Test configuration only"
            echo "  --help, -h     Show this help message"
            echo "  (no args)      Run full setup"
            exit 0
            ;;
    esac
    
    # Run setup steps
    if ! check_system_requirements; then
        log "ERROR" "System requirements not met - aborting setup"
        exit 1
    fi
    
    check_optional_dependencies
    setup_directories
    setup_scripts
    setup_configuration
    setup_gitignore
    test_configuration
    
    display_next_steps
}

# Error handling
set -e
trap 'log "ERROR" "Setup failed at line $LINENO"' ERR

# Run main function
main "$@"

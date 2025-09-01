#!/bin/bash

# ==============================================
# Database Migration Toolkit Package Installer
# ==============================================
# This script helps install the toolkit from various package sources

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Project information
PACKAGE_NAME="@ugochukwu07/db-migration-toolkit"
REPO_URL="https://github.com/Ugochukwu07/db-migration-toolkit"
LATEST_RELEASE_URL="$REPO_URL/releases/latest"

echo -e "${CYAN}=================================="
echo -e "🚀 Database Migration Toolkit Installer"
echo -e "==================================${NC}"
echo ""

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install via npm/GitHub Packages
install_via_npm() {
    echo -e "${BLUE}📦 Installing via npm (GitHub Packages)...${NC}"
    
    if ! command_exists npm; then
        echo -e "${RED}❌ npm is not installed${NC}"
        echo -e "${YELLOW}Please install Node.js and npm first:${NC}"
        echo -e "  Linux: sudo apt-get install nodejs npm"
        echo -e "  macOS: brew install node"
        return 1
    fi
    
    echo -e "${YELLOW}Configuring npm for GitHub Packages...${NC}"
    echo "@ugochukwu07:registry=https://npm.pkg.github.com" >> ~/.npmrc
    
    echo -e "${YELLOW}Installing package globally...${NC}"
    npm install -g "$PACKAGE_NAME"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Package installed successfully via npm!${NC}"
        echo -e "${CYAN}Usage:${NC}"
        echo -e "  db-migrate-setup    # Run setup"
        echo -e "  db-migrate          # Simple sync"
        echo -e "  db-migrate-multi    # Multi-threaded sync"
        echo -e "  db-migrate-monitor  # Sync with monitoring"
        return 0
    else
        echo -e "${RED}❌ npm installation failed${NC}"
        return 1
    fi
}

# Function to install via Docker
install_via_docker() {
    echo -e "${BLUE}🐳 Installing via Docker...${NC}"
    
    if ! command_exists docker; then
        echo -e "${RED}❌ Docker is not installed${NC}"
        echo -e "${YELLOW}Please install Docker first:${NC}"
        echo -e "  https://docs.docker.com/get-docker/"
        return 1
    fi
    
    echo -e "${YELLOW}Pulling Docker image from GitHub Container Registry...${NC}"
    docker pull ghcr.io/ugochukwu07/db-migration-toolkit:latest
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Docker image pulled successfully!${NC}"
        echo -e "${CYAN}Usage:${NC}"
        echo -e "  docker run -it ghcr.io/ugochukwu07/db-migration-toolkit:latest"
        echo -e "  # Or with volume mounts for config:"
        echo -e "  docker run -it -v \$(pwd)/config:/app/config ghcr.io/ugochukwu07/db-migration-toolkit:latest"
        return 0
    else
        echo -e "${RED}❌ Docker installation failed${NC}"
        return 1
    fi
}

# Function to install via git clone
install_via_git() {
    echo -e "${BLUE}📂 Installing via Git...${NC}"
    
    if ! command_exists git; then
        echo -e "${RED}❌ git is not installed${NC}"
        echo -e "${YELLOW}Please install git first${NC}"
        return 1
    fi
    
    local install_dir="${1:-./db-migration-toolkit}"
    echo -e "${YELLOW}Cloning repository to $install_dir...${NC}"
    
    git clone "$REPO_URL.git" "$install_dir"
    
    if [ $? -eq 0 ]; then
        cd "$install_dir"
        chmod +x scripts/*.sh setup.sh
        echo -e "${GREEN}✅ Repository cloned successfully!${NC}"
        echo -e "${CYAN}Setup:${NC}"
        echo -e "  cd $install_dir"
        echo -e "  ./setup.sh"
        echo -e "  cp config/config.env.example config/config.env"
        echo -e "  # Edit config/config.env with your settings"
        return 0
    else
        echo -e "${RED}❌ Git clone failed${NC}"
        return 1
    fi
}

# Function to download latest release
install_via_release() {
    echo -e "${BLUE}📥 Installing latest release...${NC}"
    
    if ! command_exists curl && ! command_exists wget; then
        echo -e "${RED}❌ Neither curl nor wget is available${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Downloading latest release...${NC}"
    
    # Get latest release download URL
    if command_exists curl; then
        DOWNLOAD_URL=$(curl -s "$REPO_URL/releases/latest" | grep "tarball_url" | cut -d '"' -f 4)
    else
        DOWNLOAD_URL=$(wget -qO- "$REPO_URL/releases/latest" | grep "tarball_url" | cut -d '"' -f 4)
    fi
    
    if [ -z "$DOWNLOAD_URL" ]; then
        echo -e "${RED}❌ Could not find latest release${NC}"
        return 1
    fi
    
    local install_dir="${1:-./db-migration-toolkit}"
    mkdir -p "$install_dir"
    
    if command_exists curl; then
        curl -L "$DOWNLOAD_URL" | tar -xz -C "$install_dir" --strip-components=1
    else
        wget -O- "$DOWNLOAD_URL" | tar -xz -C "$install_dir" --strip-components=1
    fi
    
    if [ $? -eq 0 ]; then
        cd "$install_dir"
        chmod +x scripts/*.sh setup.sh
        echo -e "${GREEN}✅ Latest release downloaded successfully!${NC}"
        echo -e "${CYAN}Setup:${NC}"
        echo -e "  cd $install_dir"
        echo -e "  ./setup.sh"
        return 0
    else
        echo -e "${RED}❌ Release download failed${NC}"
        return 1
    fi
}

# Main installation menu
show_menu() {
    echo -e "${YELLOW}Choose installation method:${NC}"
    echo -e "  ${CYAN}1)${NC} npm (GitHub Packages) - Global installation"
    echo -e "  ${CYAN}2)${NC} Docker - Container-based"
    echo -e "  ${CYAN}3)${NC} Git Clone - Development setup"
    echo -e "  ${CYAN}4)${NC} Download Release - Stable version"
    echo -e "  ${CYAN}5)${NC} Show all options"
    echo -e "  ${CYAN}q)${NC} Quit"
    echo ""
}

# Show all installation options
show_all_options() {
    echo -e "${CYAN}🔗 All Installation Options:${NC}"
    echo ""
    echo -e "${YELLOW}1. GitHub Packages (npm):${NC}"
    echo -e "   npm install -g @ugochukwu07/db-migration-toolkit"
    echo ""
    echo -e "${YELLOW}2. Docker:${NC}"
    echo -e "   docker pull ghcr.io/ugochukwu07/db-migration-toolkit:latest"
    echo ""
    echo -e "${YELLOW}3. Git Clone:${NC}"
    echo -e "   git clone $REPO_URL.git"
    echo ""
    echo -e "${YELLOW}4. Download Release:${NC}"
    echo -e "   wget $REPO_URL/archive/refs/tags/v1.0.0.tar.gz"
    echo ""
    echo -e "${YELLOW}5. Manual Download:${NC}"
    echo -e "   Visit: $REPO_URL/releases"
    echo ""
}

# Main script
main() {
    # Check if specific method requested
    case "${1:-}" in
        "npm"|"--npm")
            install_via_npm
            exit $?
            ;;
        "docker"|"--docker")
            install_via_docker
            exit $?
            ;;
        "git"|"--git")
            install_via_git "${2:-}"
            exit $?
            ;;
        "release"|"--release")
            install_via_release "${2:-}"
            exit $?
            ;;
        "help"|"--help"|"-h")
            show_all_options
            exit 0
            ;;
    esac
    
    # Interactive menu
    while true; do
        show_menu
        read -p "Enter choice [1-5, q]: " choice
        
        case $choice in
            1)
                install_via_npm
                break
                ;;
            2)
                install_via_docker
                break
                ;;
            3)
                echo ""
                read -p "Installation directory (default: ./db-migration-toolkit): " install_dir
                install_via_git "${install_dir:-./db-migration-toolkit}"
                break
                ;;
            4)
                echo ""
                read -p "Installation directory (default: ./db-migration-toolkit): " install_dir
                install_via_release "${install_dir:-./db-migration-toolkit}"
                break
                ;;
            5)
                show_all_options
                ;;
            q|Q)
                echo -e "${CYAN}Installation cancelled${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please try again.${NC}"
                ;;
        esac
        echo ""
    done
}

# Run main function
main "$@"

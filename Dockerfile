# Database Migration Toolkit Docker Container
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    mysql-client \
    bash \
    curl \
    grep \
    sed \
    gawk \
    coreutils \
    findutils \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create application directory
WORKDIR /app

# Create non-root user for security
RUN groupadd -r dbmigration && useradd -r -g dbmigration dbmigration

# Copy application files
COPY scripts/ ./scripts/
COPY config/config.env.example ./config/
COPY docs/ ./docs/
COPY *.md ./
COPY LICENSE ./

# Create necessary directories
RUN mkdir -p data/backups data/logs data/tmp

# Set proper permissions
RUN chmod +x scripts/*.sh \
    && chown -R dbmigration:dbmigration /app \
    && chmod 750 data data/backups data/logs data/tmp

# Switch to non-root user
USER dbmigration

# Set default command
CMD ["bash", "-c", "echo 'Database Migration Toolkit Container Ready!' && echo 'Copy your config.env to /app/config/ and run the desired script.' && bash"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD bash -c "[ -f /app/scripts/sync_databases.sh ] || exit 1"

# Labels for metadata
LABEL maintainer="Database Migration Toolkit" \
      version="1.0.0" \
      description="Multi-threaded database synchronization toolkit" \
      org.opencontainers.image.title="Database Migration Toolkit" \
      org.opencontainers.image.description="A comprehensive toolkit for database synchronization" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.licenses="MIT"

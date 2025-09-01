# Contributing to Database Migration Toolkit

Thank you for your interest in contributing to the Database Migration Toolkit! This document provides guidelines and instructions for contributors.

## 🤝 How to Contribute

### Reporting Issues

1. **Check existing issues** to avoid duplicates
2. **Use the issue template** when creating new issues
3. **Provide detailed information**:
   - Operating system and version
   - MySQL client version
   - Script version/commit hash
   - Complete error messages
   - Steps to reproduce

### Suggesting Features

1. **Open a discussion** first to gauge interest
2. **Explain the use case** and benefits
3. **Consider backward compatibility**
4. **Provide implementation ideas** if possible

### Code Contributions

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes**
4. **Test thoroughly**
5. **Submit a pull request**

## 📋 Development Guidelines

### Code Style

**Shell Script Standards:**
- Use `#!/bin/bash` shebang
- Follow Google Shell Style Guide
- Use meaningful variable names
- Add comments for complex logic
- Use proper error handling with `set -e`

**Function Naming:**
```bash
# Good
sync_database() { ... }
handle_error() { ... }

# Avoid
sync_db() { ... }
err() { ... }
```

**Variable Naming:**
```bash
# Good
REMOTE_HOST="example.com"
local table_name="users"

# Avoid  
HOST="example.com"
local t="users"
```

### Error Handling

**Always include error handling:**
```bash
# Good
if ! mysql -u"$USER" -p"$PASS" -e "SELECT 1;" >/dev/null 2>&1; then
    log "ERROR" "Database connection failed"
    return 1
fi

# Avoid
mysql -u"$USER" -p"$PASS" -e "SELECT 1;"
```

**Use consistent logging:**
```bash
log "INFO" "Starting operation"
log "SUCCESS" "Operation completed"
log "WARN" "Non-critical issue occurred"
log "ERROR" "Critical error occurred"
```

### Testing

**Test your changes with:**
1. Different MySQL versions (5.7, 8.0+)
2. Various database sizes (small, medium, large)
3. Network interruptions and timeouts
4. Multiple concurrent connections
5. Different operating systems (Ubuntu, CentOS, macOS)

**Create test scripts:**
```bash
#!/bin/bash
# test_your_feature.sh

# Setup test environment
create_test_databases() {
    # Implementation
}

# Run tests
run_tests() {
    # Implementation
}

# Cleanup
cleanup_tests() {
    # Implementation
}

# Main test execution
main() {
    create_test_databases
    run_tests
    cleanup_tests
}

main "$@"
```

### Documentation

**Update documentation when:**
- Adding new features
- Changing existing behavior
- Adding new configuration options
- Modifying script interfaces

**Documentation files to update:**
- `README.md` - Main documentation
- `docs/EXAMPLES.md` - Usage examples
- `docs/DOCKER.md` - Docker-specific info
- Inline comments in scripts

## 🔧 Development Setup

### Local Development Environment

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-org/database-migration-toolkit.git
   cd database-migration-toolkit
   ```

2. **Set up development environment:**
   ```bash
   # Install dependencies
   ./setup.sh
   
   # Create test configuration
   cp config/config.env.example config/config.env
   # Edit with test database credentials
   ```

3. **Set up test databases:**
   ```bash
   # Create test remote database (can be local)
   mysql -uroot -p -e "CREATE DATABASE test_source_db;"
   mysql -uroot -p test_source_db < test_data.sql
   
   # Ensure local MySQL is running
   sudo systemctl start mysql
   ```

### Development Workflow

1. **Create feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes and test:**
   ```bash
   # Test your changes
   ./scripts/your_modified_script.sh
   
   # Run setup to verify
   ./setup.sh --test
   ```

3. **Commit changes:**
   ```bash
   git add .
   git commit -m "Add feature: description of what you added"
   ```

4. **Push and create PR:**
   ```bash
   git push origin feature/your-feature-name
   # Create pull request on GitHub
   ```

## 🧪 Testing Guidelines

### Unit Testing

Create tests for individual functions:

```bash
#!/bin/bash
# tests/test_logging.sh

source scripts/multi_thread_sync.sh

# Test logging function
test_log_function() {
    local output=$(log "INFO" "Test message" 2>&1)
    if echo "$output" | grep -q "\[INFO\] Test message"; then
        echo "✅ Log function test passed"
        return 0
    else
        echo "❌ Log function test failed"
        return 1
    fi
}

test_log_function
```

### Integration Testing

Test script interactions:

```bash
#!/bin/bash
# tests/test_integration.sh

# Test full sync process with small database
test_full_sync() {
    # Setup
    mysql -uroot -p -e "CREATE DATABASE test_integration;"
    mysql -uroot -p test_integration -e "CREATE TABLE test_table (id INT PRIMARY KEY, name VARCHAR(50));"
    mysql -uroot -p test_integration -e "INSERT INTO test_table VALUES (1, 'test');"
    
    # Configure for test
    export DATABASES=("test_integration")
    
    # Run sync
    if ./scripts/sync_databases.sh; then
        echo "✅ Integration test passed"
        return 0
    else
        echo "❌ Integration test failed"
        return 1
    fi
}

test_full_sync
```

### Performance Testing

Test with larger datasets:

```bash
#!/bin/bash
# tests/test_performance.sh

# Create large test dataset
create_large_dataset() {
    mysql -uroot -p test_perf -e "
        CREATE TABLE large_table (
            id INT AUTO_INCREMENT PRIMARY KEY,
            data VARCHAR(1000),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        INSERT INTO large_table (data) 
        SELECT CONCAT('test_data_', seq) 
        FROM (SELECT 1 seq UNION SELECT 2 UNION SELECT 3) t1
        CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3) t2
        /* ... repeat to create desired size ... */
    "
}

# Test performance with different thread counts
test_performance() {
    for threads in 1 2 4 8; do
        export MAX_THREADS=$threads
        echo "Testing with $threads threads..."
        
        start_time=$(date +%s)
        ./scripts/multi_thread_sync.sh
        end_time=$(date +%s)
        
        duration=$((end_time - start_time))
        echo "Completed in ${duration}s with $threads threads"
    done
}
```

## 📝 Pull Request Guidelines

### PR Checklist

- [ ] **Code follows style guidelines**
- [ ] **All tests pass**
- [ ] **Documentation updated**
- [ ] **Backward compatibility maintained**
- [ ] **Error handling implemented**
- [ ] **Performance impact considered**
- [ ] **Security implications reviewed**

### PR Description Template

```markdown
## Description
Brief description of what this PR does.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing completed
- [ ] Performance impact assessed

## Screenshots/Logs
Include relevant screenshots or log outputs if applicable.

## Additional Notes
Any additional information that reviewers should know.
```

## 🚀 Release Process

### Version Numbering

We follow [Semantic Versioning](https://semver.org/):
- **MAJOR**: Incompatible API changes
- **MINOR**: Backward-compatible functionality additions
- **PATCH**: Backward-compatible bug fixes

### Release Steps

1. **Update version numbers** in scripts and documentation
2. **Update CHANGELOG.md** with new features and fixes
3. **Create release branch**: `git checkout -b release/v1.x.x`
4. **Test thoroughly** on multiple environments
5. **Create release tag**: `git tag v1.x.x`
6. **Publish release** with release notes

## ❓ Getting Help

### Community Support

- **GitHub Discussions**: For general questions and discussions
- **GitHub Issues**: For bug reports and feature requests
- **Documentation**: Check existing docs first

### Development Questions

- **Code Review**: Ask questions in PR comments
- **Architecture**: Open a discussion for design questions
- **Testing**: Ask about testing strategies in discussions

## 🎉 Recognition

Contributors will be:
- **Listed in CONTRIBUTORS.md**
- **Mentioned in release notes**
- **Acknowledged in documentation**

Thank you for contributing to make the Database Migration Toolkit better for everyone! 🚀

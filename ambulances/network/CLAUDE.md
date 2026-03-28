# CLAUDE.md

## Project Overview

**complete-linux-internet-repair** is a comprehensive toolkit for diagnosing and repairing internet connectivity issues on Linux systems. This tool helps users troubleshoot network problems ranging from DNS issues to network interface configuration.

## Project Purpose

This project aims to:
- Provide automated diagnostics for common Linux networking issues
- Offer guided repair procedures for internet connectivity problems
- Support multiple Linux distributions (Ubuntu, Debian, Fedora, Arch, etc.)
- Include both CLI and interactive modes for different user skill levels

## Architecture

### Expected Project Structure

```
complete-linux-internet-repair/
├── src/
│   ├── diagnostics/       # Network diagnostic modules
│   ├── repairs/           # Repair scripts and procedures
│   ├── utils/             # Utility functions
│   └── main.sh            # Main entry point
├── tests/                 # Test suite
├── docs/                  # Documentation
├── config/                # Configuration files
├── README.md              # User-facing documentation
├── CONTRIBUTING.md        # Contribution guidelines
└── LICENSE                # License file
```

### Core Components

1. **Diagnostic Engine**: Identifies network issues
   - DNS resolution problems
   - Network interface status
   - Routing table issues
   - Firewall configuration
   - Network manager conflicts
   - Hardware/driver issues

2. **Repair System**: Automated fix procedures
   - DNS server reset
   - Network interface restart
   - Network manager restart
   - Route table repair
   - Firewall rule fixes

3. **User Interface**: Interactive troubleshooting
   - CLI mode for advanced users
   - Interactive guided mode for beginners
   - Verbose logging option
   - Dry-run mode (show what would be done)

## Development Guidelines

### Code Style

- **Shell Scripts**: Follow Google Shell Style Guide
  - Use bash for main scripts
  - Include shebang: `#!/usr/bin/env bash`
  - Set strict mode: `set -euo pipefail`
  - Use meaningful variable names
  - Add comments for complex logic

- **Error Handling**: Always check command exit codes
  - Provide informative error messages
  - Log errors for debugging
  - Gracefully handle failures

### Security Considerations

- **Root Privileges**: Many network operations require sudo
  - Check for root/sudo at start
  - Request elevation only when needed
  - Warn users before making system changes

- **Input Validation**: Sanitize all user inputs
  - Prevent command injection
  - Validate file paths
  - Check network interface names

- **Backup**: Create backups before modifying configs
  - Backup `/etc/resolv.conf`
  - Backup `/etc/network/interfaces`
  - Backup NetworkManager configurations

### Testing

- **Unit Tests**: Test individual diagnostic functions
- **Integration Tests**: Test full repair workflows
- **System Tests**: Test on various distributions
  - Ubuntu 20.04, 22.04, 24.04
  - Debian 11, 12
  - Fedora 38, 39
  - Arch Linux

### Dependencies

- **Required**:
  - bash (4.0+)
  - ip (from iproute2)
  - systemctl (systemd)

- **Optional**:
  - nmcli (NetworkManager)
  - netplan (Ubuntu)
  - dig/nslookup (DNS testing)

## Common Tasks

### Adding a New Diagnostic Check

1. Create diagnostic function in `src/diagnostics/`
2. Return exit code 0 for pass, 1 for fail
3. Output diagnostic information to stdout
4. Add test in `tests/diagnostics/`
5. Register in main diagnostic flow

### Adding a Repair Procedure

1. Create repair function in `src/repairs/`
2. Check if repair is needed first
3. Backup any files before modification
4. Implement repair logic
5. Verify repair succeeded
6. Add rollback on failure
7. Test thoroughly

### Release Process

1. Update version in main script
2. Update CHANGELOG.md
3. Run full test suite
4. Create git tag: `git tag -a v1.0.0 -m "Release 1.0.0"`
5. Push tag: `git push origin v1.0.0`

## Troubleshooting Development Issues

### Common Problems

**Permission Errors**
- Many network commands require root/sudo
- Test with: `sudo ./script.sh` or request elevation in code

**Distribution Differences**
- Different distros use different network managers
- Detect distro and use appropriate commands
- Provide fallbacks for missing tools

**Testing Without Breaking Network**
- Use virtual machines for testing
- Implement dry-run mode
- Test on non-production systems

## AI Assistant Guidelines

When working on this project:

1. **Safety First**: Never run commands that could break network connectivity without user confirmation
2. **Compatibility**: Test across different Linux distributions
3. **Documentation**: Document all diagnostic checks and repair procedures
4. **Error Messages**: Provide clear, actionable error messages
5. **Logging**: Include verbose logging for debugging
6. **Idempotency**: Repairs should be safe to run multiple times
7. **Validation**: Always validate system state before and after repairs

## Resources

- Network configuration locations:
  - `/etc/network/interfaces` (Debian/Ubuntu ifupdown)
  - `/etc/netplan/` (Ubuntu with netplan)
  - `/etc/NetworkManager/` (NetworkManager)
  - `/etc/resolv.conf` (DNS configuration)
  - `/etc/sysconfig/network-scripts/` (RHEL/Fedora)

- Useful commands:
  - `ip link show` - Show network interfaces
  - `ip addr show` - Show IP addresses
  - `ip route show` - Show routing table
  - `systemctl status NetworkManager` - Check NetworkManager
  - `nmcli device status` - NetworkManager interface status
  - `resolvectl status` - DNS resolver status (systemd-resolved)
  - `ping -c 4 8.8.8.8` - Test connectivity
  - `dig google.com` - Test DNS resolution

## License

Specify license information here (e.g., MIT, GPL-3.0, Apache-2.0)

## Contributing

See CONTRIBUTING.md for guidelines on contributing to this project.

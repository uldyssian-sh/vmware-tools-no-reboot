# Security Policy

## Supported Versions

We provide security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** create a public GitHub issue
2. Email security concerns to the repository maintainer
3. Include detailed information about the vulnerability
4. Allow time for the issue to be addressed before public disclosure

## Security Considerations

### Credential Management
- Never hardcode credentials in scripts
- Use secure credential storage methods
- Implement least-privilege access

### Network Security
- Use encrypted connections (HTTPS/SSL)
- Validate SSL certificates in production
- Implement proper authentication

### Script Security
- Validate all input parameters
- Use proper error handling
- Avoid exposing sensitive information in logs

## Best Practices

- Run scripts with minimal required privileges
- Test in isolated environments first
- Keep PowerCLI and VMware Tools updated
- Monitor script execution and results
- Implement proper logging and auditing

## Updates

This security policy may be updated periodically. Check back regularly for changes.
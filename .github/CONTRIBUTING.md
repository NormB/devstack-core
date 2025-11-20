# Contributing to DevStack Core

Thank you for your interest in contributing to DevStack Core! This document provides guidelines and instructions for contributing to this project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [How to Contribute](#how-to-contribute)
- [Development Workflow](#development-workflow)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Documentation](#documentation)

## Code of Conduct

This project adheres to a Code of Conduct that all contributors are expected to follow. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/devstack-core.git
   cd devstack-core
   ```
3. **Set up the development environment**:
   ```bash
   cp .env.example .env
   # Edit .env with appropriate values
   ./devstack.sh start
   ```

### Setting Up SSH and GPG Keys for Forgejo

To enable authenticated Git operations and commit signing with the local Forgejo instance:

#### Add SSH Key (for git push/pull authentication)

1. **Display your public key:**
   ```bash
   cat ~/.ssh/id_ed25519.pub
   # Or: cat ~/.ssh/id_rsa.pub
   ```

2. **Add to Forgejo:**
   - Navigate to http://localhost:3000
   - Sign in to your account
   - Go to Settings → SSH / GPG Keys
   - Click "Add Key" under SSH Keys
   - Paste your public key
   - Give it a descriptive name (e.g., "Mac Development Key")
   - Click "Add Key"

#### Add GPG Key (for signed commits)

1. **List your GPG keys:**
   ```bash
   gpg --list-secret-keys --keyid-format LONG
   ```

2. **Export your public key:**
   ```bash
   # Replace KEY_ID with your key ID from the previous command
   gpg --armor --export KEY_ID
   ```

3. **Add to Forgejo:**
   - Navigate to Settings → SSH / GPG Keys
   - Click "Add Key" under GPG Keys
   - Paste the entire GPG public key block (including BEGIN/END lines)
   - Click "Add Key"

#### Configure Git for Signed Commits

```bash
# Set your GPG key for signing commits
git config --global user.signingkey YOUR_KEY_ID

# Enable automatic commit signing
git config --global commit.gpgsign true
```

#### Configure SSH for Forgejo

Add to your `~/.ssh/config`:
```
Host forgejo
  HostName localhost
  Port 2222
  User git
  IdentityFile ~/.ssh/id_ed25519
```

Then you can clone and push using:
```bash
git clone forgejo:username/repo.git
```

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce** the issue
- **Expected vs actual behavior**
- **Environment details**: OS version, Colima version, Docker version
- **Relevant logs** from `./devstack.sh logs` or Docker logs
- **Screenshots** if applicable

### Suggesting Enhancements

Enhancement suggestions are welcome! Please include:

- **Clear use case** - Why is this enhancement needed?
- **Proposed solution** - How should it work?
- **Alternatives considered** - What other approaches did you think about?
- **Impact** - Who benefits and how?

### Contributing Code

We welcome code contributions! Here are the types of contributions we're looking for:

- Bug fixes
- New service integrations
- Performance improvements
- Documentation improvements
- Test coverage improvements
- Security enhancements

## Development Workflow

1. **Create a branch** for your work:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-description
   ```

2. **Make your changes**:
   - Follow the coding standards below
   - Add tests if applicable
   - Update documentation as needed

3. **Test your changes**:
   ```bash
   # Start fresh environment
   ./devstack.sh stop
   ./devstack.sh clean
   ./devstack.sh start

   # Run tests
   ./scripts/run-tests.sh

   # Verify health
   ./devstack.sh health
   ```

4. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Type: Brief description

   More detailed explanation if needed.

   Fixes #issue_number"
   ```

   Commit message types:
   - `feat:` - New feature
   - `fix:` - Bug fix
   - `docs:` - Documentation changes
   - `refactor:` - Code refactoring
   - `test:` - Adding or updating tests
   - `chore:` - Maintenance tasks

5. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request** on GitHub

## Pull Request Process

1. **Update documentation** - Ensure README.md and relevant docs are updated
2. **Update CHANGELOG** - Add entry describing your changes (if applicable)
3. **Ensure tests pass** - All existing tests should pass
4. **Add tests** - For new functionality, add appropriate tests
5. **Clean commits** - Squash commits if needed for clarity
6. **Descriptive PR** - Include:
   - What changes were made
   - Why these changes were needed
   - How to test the changes
   - Screenshots/logs if applicable
   - Related issue numbers

7. **Review process**:
   - Maintainers will review your PR
   - Address any requested changes
   - Once approved, a maintainer will merge your PR

## Coding Standards

### Shell Scripts

- Use `bash` (not `sh`)
- Include shebang: `#!/bin/bash`
- Use 4-space indentation
- Quote variables: `"$VARIABLE"`
- Use `[[` instead of `[` for conditionals
- Add comments for complex logic
- Use functions for reusable code
- Check exit codes: `|| { error "Failed"; exit 1; }`

### Docker Compose

- Use version 3.8+ syntax
- Include health checks for all services
- Use explicit image tags (not `latest`)
- Document environment variables
- Use secrets for sensitive data
- Add resource limits when appropriate
- Include descriptive labels

### Configuration Files

- Use clear, descriptive names
- Include comments explaining purpose
- Document all options
- Provide sensible defaults
- Use environment variables for flexibility

### Documentation

- Use clear, concise language
- Include code examples
- Add screenshots for UI elements
- Keep line length under 100 characters
- Use proper markdown formatting
- Update table of contents when adding sections

## Testing

### Required Tests

Before submitting a PR, verify:

1. **Clean installation works**:
   ```bash
   ./devstack.sh clean
   ./devstack.sh start
   ```

2. **All services start healthy**:
   ```bash
   ./devstack.sh health
   ```

3. **Vault operations work**:
   ```bash
   ./devstack.sh vault-init
   ./devstack.sh vault-bootstrap
   ```

4. **Service-specific tests**:
   ```bash
   ./scripts/run-tests.sh
   ```

5. **No regressions**:
   - Test existing functionality still works
   - Check logs for errors: `./devstack.sh logs`

### Test Coverage

- Add tests for new features
- Update tests for modified functionality
- Include both positive and negative test cases
- Test error handling and edge cases

## Documentation

### What to Document

- **New features** - How to use them, why they're useful
- **Configuration changes** - New options, changed defaults
- **Breaking changes** - Migration guides, deprecation notices
- **Architecture changes** - Design decisions, tradeoffs
- **Troubleshooting** - Common issues and solutions

### Where to Document

- **README.md** - Main documentation, getting started, overview
- **Code comments** - Complex logic, non-obvious decisions
- **Commit messages** - What and why
- **PR descriptions** - Changes, testing, review notes
- **Issue tracker** - Bug reports, feature requests, discussions

## Questions?

- Open an issue with the `question` label
- Check existing issues and documentation
- Review closed issues for similar questions

## Recognition

Contributors will be recognized in:
- GitHub contributors list
- CHANGELOG.md for significant contributions
- Special thanks in release notes

Thank you for contributing to DevStack Core!

# Forgejo Setup

## Table of Contents

- [First-Time Setup](#first-time-setup)
- [Database Configuration](#database-configuration)
- [Admin Account Creation](#admin-account-creation)
- [SSH Keys Setup](#ssh-keys-setup)
- [GPG Keys for Signed Commits](#gpg-keys-for-signed-commits)
- [Git Operations](#git-operations)
- [Repository Management](#repository-management)

## First-Time Setup

**Access Forgejo:** `http://localhost:3000`

**Initial setup wizard:**
1. Database Type: PostgreSQL
2. Host: `postgres:5432`
3. Username: `forgejo`
4. Password: (from Vault)
5. Database Name: `forgejo`
6. Application Name: `Colima Dev Git`
7. Domain: `localhost`
8. SSH Port: `2222`
9. Base URL: `http://localhost:3000`

## Database Configuration

Database is automatically created during bootstrap:
```sql
CREATE DATABASE forgejo;
CREATE USER forgejo WITH PASSWORD 'password';
GRANT ALL PRIVILEGES ON DATABASE forgejo TO forgejo;
```

## Admin Account Creation

**During first setup:**
1. Administrator Account Settings
2. Username: `admin`
3. Password: (choose secure password)
4. Email: `admin@localhost`

## SSH Keys Setup

**Generate SSH key:**
```bash
ssh-keygen -t ed25519 -C "your@email.com"
```

**Add to Forgejo:**
1. Settings → SSH / GPG Keys
2. Add Key
3. Paste public key from `~/.ssh/id_ed25519.pub`

**Configure SSH:**
```bash
# ~/.ssh/config
Host localhost
  Port 2222
  User git
  IdentityFile ~/.ssh/id_ed25519
```

## GPG Keys for Signed Commits

**Generate GPG key:**
```bash
gpg --full-generate-key
```

**Add to Forgejo:**
```bash
gpg --armor --export YOUR_KEY_ID
# Copy output and add in Settings → SSH / GPG Keys
```

**Configure git:**
```bash
git config --global user.signingkey YOUR_KEY_ID
git config --global commit.gpgsign true
```

## Git Operations

**Clone repository:**
```bash
# HTTP
git clone http://localhost:3000/username/repo.git

# SSH
git clone ssh://git@localhost:2222/username/repo.git
```

**Add remote:**
```bash
git remote add origin http://localhost:3000/username/repo.git
git push -u origin main
```

## Repository Management

**Create repository:**
1. New Repository button
2. Repository Name
3. Description (optional)
4. Initialize with README (optional)
5. Create Repository

**Clone and push:**
```bash
git clone http://localhost:3000/username/repo.git
cd repo
echo "# My Project" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main
```

## Related Pages

- [Development-Workflow](Development-Workflow)
- [CLI-Reference](CLI-Reference)

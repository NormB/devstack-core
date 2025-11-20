# Wiki Setup Instructions

This directory contains wiki content for the DevStack Core GitHub repository.

## How to Upload to GitHub Wiki

GitHub wikis are **separate Git repositories**. Follow these steps to upload the wiki content:

### Method 1: Clone and Copy (Recommended)

```bash
# 1. Clone the wiki repository
git clone https://github.com/NormB/devstack-core.wiki.git

# 2. Copy wiki files
cp ~/devstack-core/wiki/*.md devstack-core.wiki/

# 3. Commit and push
cd devstack-core.wiki/
git add *.md
git commit -m "Add comprehensive wiki documentation"
git push origin master
```

### Method 2: Manual Upload via GitHub UI

1. Go to https://github.com/NormB/devstack-core/wiki
2. Click "New Page" for each wiki page
3. Copy content from each `.md` file
4. Use the exact filename (without `.md`) as the page title
5. Save each page

### Page Naming Convention

GitHub wiki converts filenames to page titles:
- `Home.md` → "Home"
- `Quick-Start-Guide.md` → "Quick Start Guide"
- `Common-Issues.md` → "Common Issues"

## Wiki Pages Included

### Essential Pages
1. **Home.md** - Wiki homepage with navigation
2. **Quick-Start-Guide.md** - 5-minute setup guide
3. **Architecture-Overview.md** - System architecture
4. **Common-Issues.md** - Troubleshooting guide
5. **Management-Commands.md** - Complete command reference
6. **Reference-Applications.md** - API implementation guide

### Additional Pages to Create

You can expand the wiki by creating these pages based on existing documentation:

7. **Installation.md** - From `docs/INSTALLATION.md`
8. **Vault-Integration.md** - From `docs/VAULT.md`
9. **Service-Configuration.md** - From `docs/SERVICES.md`
10. **Testing-Guide.md** - From `tests/README.md`
11. **Best-Practices.md** - From `docs/BEST_PRACTICES.md`
12. **Performance-Tuning.md** - From `docs/PERFORMANCE_TUNING.md`
13. **Security-Hardening.md** - From `docs/SECURITY_ASSESSMENT.md`
14. **Observability-Stack.md** - From `docs/OBSERVABILITY.md`
15. **Environment-Variables.md** - From `.env.example` with explanations

## Creating Additional Wiki Pages

To convert existing documentation to wiki pages:

```bash
# Example: Create Installation wiki page
cp docs/INSTALLATION.md wiki/Installation.md

# Edit to add wiki-style navigation links
# Then upload to wiki repository
```

## Wiki Navigation Best Practices

Each wiki page should include:
1. **Title** - Clear H1 heading
2. **Table of Contents** - For longer pages
3. **Internal Links** - Link to related wiki pages using: `[Page Title](Page-Title)`
4. **External Links** - Link to repository docs where appropriate
5. **"See Also" section** - Related pages at the bottom

## Maintaining the Wiki

### Keep Wiki in Sync

The wiki should be **supplementary** to the main repository documentation:

- **Wiki**: Quick reference, tutorials, FAQs
- **Repo docs/**: Comprehensive, detailed, version-controlled

### Update Process

1. Make changes to `wiki/*.md` files
2. Commit to main repository
3. Push to wiki repository

```bash
# Update wiki
cd devstack-core.wiki/
cp ~/devstack-core/wiki/*.md .
git add *.md
git commit -m "Update wiki documentation"
git push origin master
```

## Troubleshooting

### Wiki Not Showing Up

- Ensure wiki is enabled in repository settings
- Go to Settings → Features → Wikis (enable)

### Cannot Clone Wiki

```bash
# If wiki doesn't exist yet, create first page via UI
# Then clone will work
git clone https://github.com/NormB/devstack-core.wiki.git
```

### Links Not Working

- Use wiki-style links: `[Page Title](Page-Title)` not `[title](page-title.md)`
- GitHub auto-converts filenames to title case
- No `.md` extension in links

## Wiki vs Documentation

| Feature | Wiki | Repository Docs |
|---------|------|-----------------|
| **Purpose** | Quick reference, tutorials | Comprehensive documentation |
| **Version Control** | Separate repo | Main repository |
| **Editing** | Web UI or Git | Code editor |
| **Search** | GitHub search | Full-text search |
| **Best For** | FAQs, guides | API docs, architecture |

## Support

If you have questions about the wiki:
1. Check existing pages for formatting examples
2. See [GitHub Wiki Documentation](https://docs.github.com/en/communities/documenting-your-project-with-wikis)
3. Open an issue in the main repository

## Quick Commands

```bash
# Clone wiki
git clone https://github.com/NormB/devstack-core.wiki.git

# Update wiki content
cd devstack-core.wiki/
cp ~/devstack-core/wiki/*.md .
git add *.md
git commit -m "Update wiki"
git push

# View wiki
open https://github.com/NormB/devstack-core/wiki
```

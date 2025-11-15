FROM codeberg.org/forgejo/forgejo:1.21.11-0

# Install dependencies for Vault integration (needs root)
USER root
RUN apk add --no-cache wget jq

# Copy init and bootstrap scripts (AppRole version)
COPY scripts/init-approle.sh /usr/local/bin/forgejo-init.sh
COPY scripts/forgejo-bootstrap.sh /usr/local/bin/forgejo-bootstrap.sh
RUN chmod +x /usr/local/bin/forgejo-init.sh /usr/local/bin/forgejo-bootstrap.sh

# Note: We don't set USER here - the original entrypoint handles user switching via s6-overlay
# This allows s6-overlay to properly initialize as root before dropping privileges

# Use init script as entrypoint (AppRole authentication)
ENTRYPOINT ["/usr/local/bin/forgejo-init.sh"]
CMD ["/bin/s6-svscan", "/etc/s6"]

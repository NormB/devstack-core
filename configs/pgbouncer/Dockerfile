FROM edoburu/pgbouncer:latest

# Install dependencies for Vault integration
USER root
RUN apk add --no-cache bash wget jq postgresql-client

# Copy init script and config template
COPY scripts/init.sh /usr/local/bin/init.sh
COPY pgbouncer.ini.template /etc/pgbouncer/pgbouncer.ini.template
RUN chmod +x /usr/local/bin/init.sh

# Create .pgpass directory for pgbouncer user and give write access to config
RUN mkdir -p /var/lib/postgresql && \
    chown -R 70:70 /var/lib/postgresql && \
    chown 70:70 /etc/pgbouncer/pgbouncer.ini.template && \
    touch /etc/pgbouncer/pgbouncer.ini && \
    chown 70:70 /etc/pgbouncer/pgbouncer.ini

# Switch back to pgbouncer user (uid 70)
USER 70

# Don't override ENTRYPOINT - docker-compose will handle it
# The base image has its own entrypoint that we'll call from our init script

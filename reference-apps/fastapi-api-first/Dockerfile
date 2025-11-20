FROM python:3.11-slim

WORKDIR /app

# Install dependencies (add wget and jq for Vault integration)
RUN apt-get update && apt-get install -y wget jq && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY app/ ./app/

# Copy tests and pytest configuration
COPY tests/ ./tests/
COPY pytest.ini ./pytest.ini

# Copy startup scripts
COPY start.sh /app/start.sh
COPY init.sh /app/init.sh
RUN chmod +x /app/start.sh /app/init.sh

# Create non-root user and set ownership
RUN groupadd -r appuser && useradd -r -g appuser appuser && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose ports (HTTP and HTTPS)
EXPOSE 8001 8444

# Run initialization script (which calls start.sh)
CMD ["/app/init.sh"]

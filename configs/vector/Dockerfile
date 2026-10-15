FROM timberio/vector:0.59.0-debian

# Install dependencies required by init script
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        redis-tools && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG VECTOR_VERSION=0.50.0-debian
FROM timberio/vector:${VECTOR_VERSION}

# Install dependencies required by init script
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        redis-tools && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

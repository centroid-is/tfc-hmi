# Stage 1: Build Dart application (build hooks compile open62541 + mbedTLS automatically)
FROM dart:stable AS dart-builder

# Install build tools needed by open62541_dart build hook
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    build-essential \
    python3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy pubspec.yaml only (not lock file to avoid local path issues)
COPY pubspec.yaml ./

# Get dependencies fresh
RUN dart pub get

# Copy source code
COPY . .

# Build executables (dart build cli triggers build hooks for native assets)
RUN dart build cli -t bin/main.dart -o build/main && \
    dart build cli -t bin/generate_certs.dart -o build/generate_certs

# Stage 2: Runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy compiled backend bundle (executable + bundled native libraries)
COPY --from=dart-builder /app/build/main/bundle/ /app/

# Copy generate_certs tool
COPY --from=dart-builder /app/build/generate_certs/bundle/bin/generate_certs /usr/local/bin/

# Create non-root user
RUN useradd -m -s /bin/bash appuser
USER appuser

CMD ["/app/bin/main"]

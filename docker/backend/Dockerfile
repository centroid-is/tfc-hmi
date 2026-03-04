# Stage 1: Build tfc_dart (build hooks compile open62541 + mbedTLS automatically)
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
COPY packages/tfc_dart/pubspec.yaml ./

# Get dependencies fresh
RUN dart pub get

# Copy source code
COPY packages/tfc_dart/ .

# Build executables (dart build cli triggers build hooks for native assets)
RUN dart build cli -t bin/main.dart -o build/main && \
    dart build cli -t bin/generate_certs.dart -o build/generate_certs


# Stage 2: Build jbtm proxy (pure Dart, no native deps)
FROM dart:stable AS jbtm-builder

WORKDIR /app

COPY packages/jbtm/pubspec.yaml ./
RUN dart pub get
COPY packages/jbtm/ .

RUN dart build cli -t bin/m2400_proxy.dart -o build/m2400_proxy


# Stage 3: Runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy compiled backend bundle (executable + bundled native libraries)
COPY --from=dart-builder /app/build/main/bundle/ /app/

# Copy generate_certs tool
COPY --from=dart-builder /app/build/generate_certs/bundle/bin/generate_certs /usr/local/bin/

# Copy M2400 proxy
COPY --from=jbtm-builder /app/build/m2400_proxy/bundle/bin/m2400_proxy /usr/local/bin/

# Create non-root user
RUN useradd -m -s /bin/bash appuser
USER appuser

CMD ["/app/bin/main"]

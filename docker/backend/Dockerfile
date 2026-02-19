# Stage 1: Build open62541 shared library with mbedTLS
FROM debian:bookworm-slim AS open62541-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    build-essential \
    ca-certificates \
    python3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Download and build mbedTLS 3.6.3 from source
RUN curl -sL https://github.com/Mbed-TLS/mbedtls/archive/refs/tags/mbedtls-3.6.3.tar.gz | tar xz && \
    cd mbedtls-mbedtls-3.6.3 && \
    mkdir build && cd build && \
    cmake .. \
        -DENABLE_TESTING=OFF \
        -DENABLE_PROGRAMS=OFF \
        -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON && \
    make -j$(nproc)

# Download specific open62541 commit (known working version)
RUN curl -sL https://github.com/open62541/open62541/archive/79e47f89837bc5e8f710d501e2afcd8ad71b0a28.tar.gz | tar xz && \
    mv open62541-79e47f89837bc5e8f710d501e2afcd8ad71b0a28 open62541

# Build open62541 as shared library
WORKDIR /build/open62541_build
RUN cmake ../open62541 \
    -DBUILD_SHARED_LIBS=ON \
    -DUA_ENABLE_INLINABLE_EXPORT=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DUA_BUILD_EXAMPLES=OFF \
    -DUA_BUILD_UNIT_TESTS=OFF \
    -DUA_ENABLE_AMALGAMATION=ON \
    -DUA_MULTITHREADING=0 \
    -DUA_LOGLEVEL=100 \
    -DUA_ENABLE_DEBUG_SANITIZER=OFF \
    -DUA_ENABLE_ENCRYPTION=MBEDTLS \
    -DMBEDTLS_INCLUDE_DIRS=/build/mbedtls-mbedtls-3.6.3/include \
    -DMBEDTLS_LIBRARY=/build/mbedtls-mbedtls-3.6.3/build/library/libmbedtls.a \
    -DMBEDX509_LIBRARY=/build/mbedtls-mbedtls-3.6.3/build/library/libmbedx509.a \
    -DMBEDCRYPTO_LIBRARY=/build/mbedtls-mbedtls-3.6.3/build/library/libmbedcrypto.a \
    && make -j$(nproc)

# Stage 2: Build Dart application
FROM dart:stable AS dart-builder

# Install git for fetching git dependencies
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy pubspec.yaml only (not lock file to avoid local path issues)
COPY pubspec.yaml ./

# Get dependencies fresh
RUN dart pub get

# Copy source code
COPY . .

# Build executables
RUN dart compile exe bin/main.dart -o bin/centroidx-backend && \
    dart compile exe bin/generate_certs.dart -o bin/generate_certs

# Stage 3: Runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy open62541 shared library
COPY --from=open62541-builder /build/open62541_build/bin/libopen62541.so /usr/local/lib/
RUN ldconfig

# Copy compiled Dart executables
COPY --from=dart-builder /app/bin/centroidx-backend /app/
COPY --from=dart-builder /app/bin/generate_certs /usr/local/bin/

# Create non-root user
RUN useradd -m -s /bin/bash appuser
USER appuser

ENV LD_LIBRARY_PATH=/usr/local/lib

CMD ["/app/centroidx-backend"]
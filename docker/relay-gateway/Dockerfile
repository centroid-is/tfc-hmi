# The relay gateway, as one container.
#
# Modelled on docker/backend/Dockerfile, which already solved the hard part:
# open62541_dart's build hook compiles open62541 and mbedTLS as *native assets*
# during `dart build cli`, so the builder stage needs a C toolchain and CMake
# even though nothing here is written in C. The gateway needs exactly that —
# tfc_relay_local depends on open62541 for its OPC UA links.
#
# Two binaries come out:
#
#   /app/bin/relay_gateway    the gateway process (the CMD)
#   /usr/local/bin/relay_certs  the CA/leaf minting tool the TLS listener needs
#
# relay_certs is in the image rather than run from a laptop because the PKI it
# writes has to land on the volume the gateway reads, and because it needs no
# openssl on the host — the certificate bytes come out of
# tfc_relay_server/lib/src/tls/mint.dart.

# ---------------------------------------------------------------------------
# Stage 1: build both binaries.
#
# ONE builder stage, not two. The backend Dockerfile splits its jbtm proxy into
# its own stage because that package is a different pub root that needs its own
# resolution; relay_certs is the same situation, but the apt layer and the pub
# cache are worth more than the parallelism — a second dart:stable stage
# re-downloads the same ~400 MB of toolchain, and the rig this deploys to has
# 32 GB of disk.
# ---------------------------------------------------------------------------
FROM dart:stable AS builder

# The open62541_dart build hook shells out to git (submodule fetch), cmake and
# a C compiler. python3 is mbedTLS's generator scripts.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    cmake \
    build-essential \
    python3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Mirror the packages/ layout so the `{path: ../foo}` deps resolve. The build
# root is tfc_relay_local; everything else hangs off it by relative path.
WORKDIR /app/packages/tfc_relay_local

# Pubspecs first, in their own layer: they change far less often than source,
# so an edit to a .dart file does not re-resolve and does not re-download the
# pinned open62541/postgres git deps.
#
# The list is the transitive path closure of tfc_relay_local INCLUDING dev
# dependencies — `dart pub get` resolves those too, and a missing pubspec for
# one of them fails the resolution even though nothing in bin/ imports it:
#
#   tfc_relay_local -> tfc_relay_protocol, tfc_relay_server, tfc_dart, jbtm,
#                      modbus_client_tcp
#                   -> (dev) tfc_relay_client, tfc_stateman_contract
#   tfc_relay_server -> tfc_relay_protocol, (dev) tfc_stateman_contract
#   tfc_relay_client -> tfc_relay_protocol, tfc_relay_server,
#                       (dev) tfc_stateman_contract
#   tfc_dart         -> jbtm, modbus_client_tcp, tfc_access
#   modbus_client_tcp <-> modbus_client   (mutual; pub handles the cycle)
COPY packages/tfc_relay_local/pubspec.yaml ./
COPY packages/tfc_relay_protocol/pubspec.yaml ../tfc_relay_protocol/
COPY packages/tfc_relay_server/pubspec.yaml ../tfc_relay_server/
COPY packages/tfc_relay_client/pubspec.yaml ../tfc_relay_client/
COPY packages/tfc_stateman_contract/pubspec.yaml ../tfc_stateman_contract/
COPY packages/tfc_dart/pubspec.yaml ../tfc_dart/
COPY packages/tfc_access/pubspec.yaml ../tfc_access/
COPY packages/jbtm/pubspec.yaml ../jbtm/
COPY packages/modbus_client_tcp/pubspec.yaml ../modbus_client_tcp/
COPY packages/modbus_client/pubspec.yaml ../modbus_client/

RUN dart pub get

# Source. Same list, minus nothing: a path dependency with a pubspec and no
# lib/ resolves but does not compile, and which of these the compiler actually
# reaches depends on the import graph of the day.
COPY packages/tfc_relay_local/ ./
COPY packages/tfc_relay_protocol/ ../tfc_relay_protocol/
COPY packages/tfc_relay_server/ ../tfc_relay_server/
COPY packages/tfc_relay_client/ ../tfc_relay_client/
COPY packages/tfc_stateman_contract/ ../tfc_stateman_contract/
COPY packages/tfc_dart/ ../tfc_dart/
COPY packages/tfc_access/ ../tfc_access/
COPY packages/jbtm/ ../jbtm/
COPY packages/modbus_client_tcp/ ../modbus_client_tcp/
COPY packages/modbus_client/ ../modbus_client/

# The gateway. `dart build cli` is what fires the build hooks, so this is the
# step that spends ten minutes compiling mbedTLS.
RUN dart build cli -t bin/relay_gateway.dart -o build/relay_gateway

# The cert tool, out of its own package root and therefore its own resolution.
# tfc_relay_server has zero native dependencies by design (its pubspec says so
# and a test pins it), so this build is seconds, not minutes.
WORKDIR /app/packages/tfc_relay_server
RUN dart pub get && \
    dart build cli -t bin/relay_certs.dart -o build/relay_certs


# ---------------------------------------------------------------------------
# Stage 2: runtime.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

# ca-certificates is not decoration: the collection sink connects to Postgres
# with sslMode `require` or `verifyFull`, and the latter has nothing to verify
# against without a trust store.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# The bundle, not the bare executable: `dart build cli` puts the native assets
# (libopen62541, libmbedtls) beside the binary and it will not start without
# them.
COPY --from=builder /app/packages/tfc_relay_local/build/relay_gateway/bundle/ /app/
COPY --from=builder /app/packages/tfc_relay_server/build/relay_certs/bundle/bin/relay_certs /usr/local/bin/

# A FIXED uid, unlike the backend image's bare `useradd -m`.
#
# It is fixed because two files this process reads are checked for their mode:
# FileTokenValidator refuses a token file any group or other can read
# (file_token_validator.dart:270), and relay_certs writes the TLS private key
# 0600. Those files are bind-mounted from the host, so the host has to be able
# to `chown 1000:1000` them — which needs a uid the README can name.
RUN useradd --create-home --uid 1000 --shell /bin/bash gateway
USER gateway

# /config is the bind mount: gateway.json, the keymappings file, the PKI and
# the token file all live there. See docker-compose.yml.
CMD ["/app/bin/relay_gateway", "--config", "/config/gateway.json"]

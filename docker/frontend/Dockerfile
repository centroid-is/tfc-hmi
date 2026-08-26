# =============================================================================
# Stage: rebuild the Wayland embedder with force-numlock.patch
#
# The bundle ships a prebuilt libflutter_elinux_wayland.so whose xkb state is
# driven solely by the compositor's wl_keyboard.modifiers events. Weston's VNC
# seat never latches NumLock, so keypad keys resolve to navigation keysyms and
# produce no characters — a dead numpad over the VNC mirror. Rebuild the .so
# from the exact source tag matching the bundled engine, with the patch keeping
# NumLock always latched, and swap it into the bundle below.
# =============================================================================
FROM debian:trixie-slim AS embedder-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    clang build-essential cmake pkg-config git ca-certificates \
    libgles2-mesa-dev libegl1-mesa-dev libxkbcommon-dev libwayland-dev \
    libdrm-dev libgbm-dev libinput-dev libudev-dev libsystemd-dev \
    wayland-protocols libx11-dev \
    && rm -rf /var/lib/apt/lists/*

# The embedder repo tags releases by Flutter engine hash. This must match the
# engine of the Flutter version flutter-elinux builds with (bin/internal/
# engine.version — Flutter 3.47.0 since #350). Update alongside any
# flutter-elinux version bump; a mismatch fails loudly at link time, not
# silently.
ARG EMBEDDER_REF=5f77625673
RUN git clone https://github.com/flutter-elinux/flutter-embedded-linux.git /embedder \
    && git -C /embedder checkout ${EMBEDDER_REF}

COPY force-numlock.patch /tmp/force-numlock.patch
RUN git -C /embedder apply --stat --apply /tmp/force-numlock.patch

# The embedder links against the engine at build/libflutter_engine.so
# (hardcoded in its cmake). Use the one from the app bundle so the .so is
# built against exactly the engine it will run with.
ARG APP_BUNDLE
COPY ${APP_BUNDLE}/lib/libflutter_engine.so /embedder/build/

# Release regardless of the bundle's build mode: the wrapper ABI is identical,
# only optimization and embedder-internal assertions differ.
RUN cmake -S /embedder -B /embedder/build \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_ELINUX_SO=ON -DBACKEND_TYPE=WAYLAND \
    && cmake --build /embedder/build -j"$(nproc)" \
    && ls -la /embedder/build/libflutter_elinux_wayland.so

# =============================================================================
# Stage: runtime
# =============================================================================
FROM debian:trixie-slim

# Install only the required libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    libstdc++6 \
    libgcc-s1 \
    libc6 \
    libfontconfig1 \
    libpthread-stubs0-dev \
    libxkbcommon0 \
    libwayland-client0 \
    libwayland-cursor0 \
    libwayland-egl1 \
    libegl1 \
    libfreetype6 \
    libexpat1 \
    libffi8 \
    libgl1 \
    zlib1g \
    libpng16-16 \
    libglib2.0-0 \
    libsecret-1-0 \
    sqlite3 \
    curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Hacks for amplify secure storage
RUN ln -s /usr/lib/x86_64-linux-gnu/libgio-2.0.so.0 /usr/lib/x86_64-linux-gnu/libgio-2.0.so
RUN ln -s /usr/lib/x86_64-linux-gnu/libglib-2.0.so.0 /usr/lib/x86_64-linux-gnu/libglib-2.0.so
RUN ln -s /usr/lib/x86_64-linux-gnu/libsecret-1.so.0 /usr/lib/x86_64-linux-gnu/libsecret-1.so

RUN useradd -m centroid

# Copy in your Flutter libraries and executable
# These will be supplied at build time
ARG APP_DIR=/flutter-app
WORKDIR $APP_DIR

# You can use build args to specify the location of your app and libs
# Example: docker build --build-arg APP_BIN=flutter_elinux_wayland --build-arg FLUTTER_ENGINE=./bundle ...
ARG APP_BIN
ENV BINARY=${APP_BIN}
ARG APP_BUNDLE
ENV BUNDLE=${APP_BUNDLE}

COPY ${APP_BUNDLE} $APP_DIR/

# Swap in the numlock-patched Wayland embedder built above (see the
# embedder-builder stage and force-numlock.patch).
COPY --from=embedder-builder /embedder/build/libflutter_elinux_wayland.so $APP_DIR/lib/

# Download libpdfium.so (flutter-elinux skips the CMake FFI plugin pipeline)
ARG PDFIUM_RELEASE=chromium%2F7520
RUN curl -sL "https://github.com/bblanchon/pdfium-binaries/releases/download/${PDFIUM_RELEASE}/pdfium-linux-x64.tgz" \
      -o /tmp/pdfium.tgz \
    && mkdir -p /tmp/pdfium \
    && tar -xzf /tmp/pdfium.tgz -C /tmp/pdfium lib/libpdfium.so \
    && cp /tmp/pdfium/lib/libpdfium.so $APP_DIR/lib/ \
    && rm -rf /tmp/pdfium /tmp/pdfium.tgz

RUN chown -R centroid:centroid $APP_DIR \
    && chmod +x $APP_DIR/${BINARY}

USER centroid

CMD ["/bin/sh", "-c", "LD_LIBRARY_PATH=./lib ./${BINARY} --bundle=. --fullscreen --onscreen-keyboard"]

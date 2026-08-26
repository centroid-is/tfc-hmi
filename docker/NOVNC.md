# Browser access to the HMI: can a noVNC container work with our setup?

Research notes, 2026-08-26. Question: can we drop a noVNC container next to the
`weston` container in `docker-compose.yml` and reach the HMI from a browser,
instead of needing a native VNC client?

## TL;DR

- **Yes, but not against the VNC server we run today.** As currently configured,
  weston offers only security types noVNC cannot do, so the browser never gets
  past the handshake.
- **One flag fixes it**: add `--disable-transport-layer-security` to the
  `[screen-share] command=` line in the weston image's `weston.ini`. That swaps
  VeNCrypt/X509 for Apple-DH (ARD), which noVNC does support, and everything
  else — PAM login, Tight encoding, multiple viewers — works unchanged.
- The flag removes RFB-level encryption, so the VNC port must stop being
  published on the host and the TLS must move to the noVNC side (`wss://`).
- Verified end to end against the real `ghcr.io/centroid-is/weston:latest`
  image: authenticated as `centroid`, pulled a live framebuffer through
  websockify, ~41 KiB for a full 1280x800 frame.

## What we run today

`docker-compose.yml` starts `ghcr.io/centroid-is/weston:latest` and publishes
`5900:5900`. Inside, weston loads `screen-share.so`, which spawns a *nested*
weston with the VNC backend (see `weston.ini` in `centroid-is/dockers`):

```
[screen-share]
command=weston --backend=vnc-backend.so --vnc-tls-cert=…/tls.crt --vnc-tls-key=…/tls.key --shell=fullscreen-shell.so --no-config --debug
```

The image is Debian trixie: **weston 14.0.2** on **neatvnc 0.9.1**.
Clients authenticate over PAM as the `centroid` user (`echo 'centroid:foo' |
chpasswd` in the compose entrypoint).

## Why noVNC cannot connect today

noVNC only implements these RFB security types
(`_isSupportedSecurityType` in `core/rfb.js`):

| type | name |
|-----:|------|
| 1 | None |
| 2 | VNC Auth |
| 6 | RA2ne |
| 16 | Tight |
| 19 | VeNCrypt (Plain subtype 256 only) |
| 22 | XVP |
| 30 | ARD / Apple DH |
| 113 | MSLogonII |

Probing our own image with TLS certs configured, the server offers:

```
security types: [19, 129, 5]      # VeNCrypt, RSA-AES-256, RSA-AES
VeNCrypt version 0.2
  subtype 262: X509Plain          # the only subtype offered
```

So the overlap is empty in practice:

- **19 VeNCrypt** — neatvnc offers *only* `X509Plain`, which requires a real TLS
  handshake **inside** the RFB stream. A browser cannot do that: its TLS stack
  is not reachable from JS, and noVNC only implements the unencrypted `Plain`
  subtype (256). This is noVNC issue #1659, and it is not a bug that will be
  fixed — it is a structural limit of running in a browser.
- **129 / 5 RSA-AES-256 / RSA-AES** — noVNC implements only `RA2ne` (type 6),
  the 128-bit *unencrypted* variant. neatvnc never offers type 6.

There is also no proxy workaround: VeNCrypt negotiates TLS *after* the RFB
version exchange, so `stunnel`/`socat`/`websockify --ssl-target` cannot
terminate it. A VeNCrypt-aware translating proxy would have to be written.

## What makes it work

`weston --backend=vnc-backend.so --disable-transport-layer-security` keeps PAM
authentication but drops the encryption requirement. neatvnc then adds Apple DH
to the offered list (`init_security_types()` adds `APPLE_DH` when
`NVNC_AUTH_REQUIRE_ENCRYPTION` is not set):

```
security types: [129, 5, 30]      # 30 = ARD / Apple DH — noVNC supports this
```

Verified against `ghcr.io/centroid-is/weston:latest`, replaying noVNC's exact
ARD implementation (2048-bit DH → MD5 of the shared secret → AES-128-ECB over a
128-byte credential blob) **through a websockify/noVNC container**:

```
security types via websockify: [129, 5, 30]
auth result: OK
desktop: 1280x800 'Weston VNC backend' bpp=32
FramebufferUpdate: 260 rect(s)
  rect 64x64+0+0 encoding 7 = Tight
```

Other things measured on the way:

- **Bandwidth**: a full 1280x800 frame costs **~41 KiB** with noVNC's encoding
  list (Tight, JPEG via libturbojpeg server-side) against 4000 KiB raw. The HMI
  only repaints changed tiles, so steady-state is far below that.
- **Multiple viewers work.** `weston-vnc(7)` still says "if a second client
  connects to the backend, the first client will be disconnected" — that is
  stale for weston 14 / neatvnc 0.9. Two clients connected simultaneously and
  both stayed alive. They *share one seat*, though: every viewer drives the
  same pointer and keyboard, so two people clicking at once fight each other.
- **Numpad** already works — the force-NumLock embedder rebuild (PR #351) fixes
  it for any RFB client, noVNC included.
- **No new wl_seat.** noVNC connects to the same VNC backend seat, so it does
  not re-trigger the touchscreen multi-seat problem the ivi-homescreen fork
  works around.

## Changes required

**1. `centroid-is/dockers` → `weston/weston.ini`** (this is the change that
actually unblocks noVNC):

```diff
 [screen-share]
-command=weston --backend=vnc-backend.so --vnc-tls-cert=/home/centroid/vnc/certs/tls.crt --vnc-tls-key=/home/centroid/vnc/certs/tls.key --shell=fullscreen-shell.so --no-config --debug
+command=weston --backend=vnc-backend.so --disable-transport-layer-security --shell=fullscreen-shell.so --no-config --debug
 start-on-startup=true
```

The cert/key generation in that Dockerfile can go with it.

**2. `docker-compose.yml` here** — stop publishing the VNC port and add the
proxy:

```diff
   weston:
     …
-    ports:
-      - 5900:5900

+  novnc:
+    image: <novnc image>
+    container_name: novnc
+    ports:
+      - 6080:6080
+    command: websockify --web /opt/novnc --cert /certs/tls.crt --key /certs/tls.key 6080 weston:5900
+    depends_on:
+      - weston
+    restart: unless-stopped
```

Once 5900 is unpublished, the plaintext RFB hop stays inside the compose
network and only the TLS-wrapped WebSocket is reachable from the plant network.

## Security consequences — read before shipping

ARD/Apple DH encrypts *the credentials only*. Framebuffer contents and input
are plaintext on the wire. That is acceptable **only** if:

- port 5900 is no longer published on the host (see the diff above), and
- websockify serves `wss://` with a certificate, so the browser hop is
  encrypted.

Also note the compose entrypoint sets the VNC password to `foo` in plaintext.
Today that is protected by TLS-with-a-self-signed-cert; after this change it is
protected by the noVNC hop and the plant network only. Worth changing at the
same time.

## Footnote: `--no-config` on the nested compositor

The nested VNC weston is started with `--no-config`, so it ignores
`weston.ini` entirely. That means the `[vnc] refresh-rate=60` and
`[output] name=vnc / resizeable=false` sections in our `weston.ini` do **not**
apply to the VNC instance — they only ever affected the outer DRM compositor.
If those settings were meant to take effect, they have to move onto the
`[screen-share] command=` line as flags.

## Reproducing

```sh
docker network create novnctest
docker run -d --name weston --network novnctest -p 5901:5900 \
  -e XDG_RUNTIME_DIR=/tmp/xdg --user root ghcr.io/centroid-is/weston:latest \
  sh -c "echo 'centroid:foo' | chpasswd && mkdir -p /tmp/xdg && chown centroid /tmp/xdg && chmod 700 /tmp/xdg && \
         exec su -s /bin/bash -c 'XDG_RUNTIME_DIR=/tmp/xdg exec weston --backend=vnc-backend.so \
           --disable-transport-layer-security --shell=desktop-shell.so --no-config --width=1280 --height=800' centroid"
```

Then point any websockify + noVNC container at `weston:5900` and open
`vnc.html` in a browser; log in as `centroid` / `foo`.

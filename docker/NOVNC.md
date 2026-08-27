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
- The flag is misnamed: it drops the *requirement* for encryption, not the
  capability. Native clients still negotiate RSA-AES-256 for themselves
  (verified with TigerVNC 1.15) — only the browser session ends up plaintext at
  the RFB layer, so the VNC port must stop being published on the host and the
  TLS must move to the noVNC side (`wss://`). See "Two VNC servers, or one?".
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

## Two VNC servers, or one? (and where to put the encryption)

Two follow-up questions came up: could we run *two* VNC sessions — one local
and plaintext for noVNC, one exposed with TLS for native clients — and could we
encrypt only on the way out, leaving the inside plaintext?

**Short answer: two servers work, but you almost certainly don't want them,**
because the flag above does not do what its name suggests.

### `--disable-transport-layer-security` does not disable encryption

It removes the *requirement*. neatvnc keeps offering RSA-AES; only the
`REQUIRE_ENCRYPTION` flag goes away, which is what lets Apple DH onto the list.
Each client then picks the strongest type **it** supports. Verified with
TigerVNC 1.15 against our image with the flag on:

```
Server offers security type RA2_256(129)
Server offers security type RA2(5)
Server offers security type DH(30)
Choosing security type RA2_256(129)      <- RSA-AES-256, fully encrypted
```

For comparison, the same client against what we ship **today**:

```
Choosing security type VeNCrypt(19)
CVeNCrypt:   Choosing security type X509Plain (262)
TLS:         Server certificate errors: The certificate is NOT trusted. The
             certificate issuer is unknown.
TLS:         Server certificate doesn't match given server name
```

Our current "TLS" is a self-signed cert that every operator clicks past. RSA-AES
is trust-on-first-use with no certificate to generate, ship, or rotate — so for
native clients the flag is arguably an *upgrade*, not a downgrade.

What each client ends up with once the flag is on:

| client | picks | session encrypted? |
|---|---|---|
| TigerVNC ≥ 1.12, RealVNC | RA2_256 / RA2 | yes — verified with TigerVNC 1.15 |
| noVNC | ARD (30) | no — credentials only |
| gtk-vnc (Remmina, virt-viewer) | ARD (30) | no — credentials only [^gtkvnc] |
| macOS Screen Sharing | ARD (30) | no — credentials only |

[^gtkvnc]: read from gtk-vnc's `vncconnection.c`, which lists ARD but no
    RSA-AES. Not confirmed against a live client — a headless `gvncviewer` run
    never reached the server.

### So: encrypt at the edge, plaintext inside

This is the recommended shape, and it needs only **one** VNC server:

- **Native clients** encrypt themselves at the RFB layer (RSA-AES-256). No
  proxy, no certificates.
- **Browsers** get their encryption from `wss://` at websockify — the separate
  layer, terminated at the edge. That is the layer you were asking about, and
  noVNC needs it anyway.
- **Nothing plaintext leaves the host**, provided `5900:5900` is unpublished so
  the plaintext-capable port only exists on the compose network.

The residual risk is that the server still *permits* an unencrypted session, so
a misconfigured native client could pick ARD and get plaintext pixels. The
mitigation is the network boundary, not the flag: don't publish 5900.

### If you still want the two-port split

It does work — I ran it. weston's module loader dedups by path, but
`Module '…' already loaded` is only a log line: it still returns the entrypoint
and calls `wet_module_init` a second time. So listing screen-share twice gives
you two independent shares of the same output:

```ini
[core]
modules=screen-share.so,screen-share.so

[screen-share]
command=/usr/local/bin/share-vnc.sh
start-on-startup=true
```

Both shares run the *same* command string — there is one `[screen-share]`
section and a second one is ignored — so the command has to be a wrapper that
distinguishes its own invocations:

```sh
#!/bin/sh
if mkdir /tmp/vnc-primary 2>/dev/null; then     # first invocation wins
  exec weston --backend=vnc-backend.so --vnc-tls-cert=…/tls.crt \
    --vnc-tls-key=…/tls.key --port=5900 --shell=fullscreen-shell.so --no-config
else
  exec weston --backend=vnc-backend.so --disable-transport-layer-security \
    --port=5901 --shell=fullscreen-shell.so --no-config
fi
```

Both servers came up and both served real clients — 5900 offering
`{19, 129, 5}` to TigerVNC, 5901 offering `{129, 5, 30}` and completing a full
noVNC ARD handshake plus framebuffer.

The costs: a second full nested compositor (its own encode pipeline and
memory), a second `wl_seat`, and a load-order hack that weston does not
document and could tighten at any time. Against that, the single-server setup
already gives native clients RSA-AES-256. Not worth it.

> One caveat on stability: my rig used the **headless** backend as the parent,
> and there weston segfaults on VNC client disconnect
> (`wl_registry#2: error 0: invalid global wl_seat`) — but it does so
> **identically with a single share**, so it is an artifact of the headless
> parent, not of running two. Stability of two shares on the real DRM parent is
> untested from here.

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

## What about Apache Guacamole?

Guacamole looked like it might avoid the weston change entirely: `guacd` drives
VNC through libvncclient, which *does* implement VeNCrypt X509. It does not.

Driving `guacamole/guacd:1.6.0` directly over the Guacamole protocol (no Tomcat
needed for the test), against our **current, unmodified** TLS config:

```
guacd[15]: ERROR:  Unsupported credential type requested.
```

libvncclient asks guacd for X509 credentials to verify the server, and guacd
implements only username/password. Against the **no-TLS** server it connects
immediately and streams the screen (`img`, `blob`, `rect`, `copy`, `sync`).

So **Guacamole needs exactly the same weston change as noVNC** — it is a
heavier front-end for the same server config, not a way around it. And it lands
on the same security type: a sniffing relay in front of the server shows

```
server offered: 129 (RSA-AES-256), 5 (RSA-AES-128), 30 (ARD)
guacd     chose: 30  ARD          <- framebuffer plaintext, needs edge TLS
TigerVNC  chose: 129 RSA-AES-256  <- fully encrypted
```

### Where Guacamole does win

Four things it has that noVNC structurally cannot:

- **Server-side read-only.** guacd's `read-only` parameter is enforced in the
  proxy. noVNC's `view_only` is a URL parameter the viewer can simply delete.
  For a browser link onto a live processing line, that difference is a safety
  property, not a preference.
- **Per-user accounts, LDAP, TOTP.** Today every VNC user shares `centroid`.
- **Session recording** (`recording-path`) — who connected and what they did.
- **One gateway for every station** instead of one noVNC per station.

Costs: guacd + a Tomcat webapp + an auth config, against noVNC's single small
container; and an extra re-encode hop (browser → Tomcat → guacd → libvncclient
→ RFB) where noVNC gets neatvnc's Tight frames straight through.

## Recommendation

**Do the weston change and start with noVNC.** The blocking change is identical
for both front-ends, so nothing is wasted by starting small:

1. `--disable-transport-layer-security` on the `[screen-share] command=` line.
2. Unpublish `5900:5900`.
3. One noVNC/websockify container serving `wss://`.
4. Change `centroid:foo` while you are in there — it is the only thing standing
   between the plant network and the HMI, and after this change it is no longer
   behind a certificate.

Native clients come out *better* than today (RSA-AES-256, no cert warning), and
browser access arrives for the cost of one small container.

**Add a central Guacamole later if — and only if — you want read-only viewers,
per-user accounts, or session recording.** It talks to the same servers, and
multiple clients coexist fine (verified), so it can run alongside the per-station
noVNC rather than replacing it. If server-enforced read-only matters *now*, skip
noVNC and go straight to Guacamole; that is the one requirement noVNC cannot
meet.

## Is Apple DH actually secure?

No. It is password obfuscation against a passive sniffer, and nothing more.
From `src/auth/apple-dh.c` in neatvnc:

- Fresh **2048-bit DH per connection** (`APPLE_DH_SERVER_KEY_LENGTH 256`, g=2).
  The size is fine — much better than Apple's original ARD, which used a
  512-bit prime.
- **MD5** of the shared secret as the KDF, then **AES-128-ECB** over a 128-byte
  blob (64 bytes username, 64 password). Neither is directly breakable here,
  but neither would pass review today.
- **No server authentication whatsoever.** The client cannot verify the
  server's DH public key, so anyone who can intercept the connection
  substitutes their own key, reads the credentials, and relays. Textbook MITM
  against unauthenticated DH.
- **Nothing after the handshake is encrypted** — framebuffer and input are
  plaintext.

For comparison, RSA-AES-256 (what TigerVNC picks) encrypts the session *and*
pins the server's RSA key fingerprint on first use. And today's VeNCrypt X509
is TLS, but with a self-signed cert that TigerVNC reports as untrusted with a
name mismatch — if operators click through that every time, it is not buying
MITM protection either.

**So Apple DH is acceptable only as the inner hop of a tunnel that provides the
real security.** In the recommended design the browser gets `wss://` with a
verified certificate and the ARD hop never leaves the compose network, where
Apple DH is doing nothing and that is fine. Two consequences are therefore hard
requirements, not preferences:

1. **Never publish the ARD-capable port.** On the plant network, the shared
   `centroid` password is harvestable by anyone on-path.
2. **Use a real certificate on websockify** (or terminate at an nginx that has
   one). A self-signed cert there just moves the click-through to the browser.

### Does a newer neatvnc help? No.

neatvnc `master` adds exactly one security type over 0.9.1 — VNC Auth (2),
which noVNC does support — but it is gated behind
`NVNC_AUTH_ALLOW_BROKEN_CRYPTO` and a no-username mode, and the name is
deserved: DES challenge-response with an 8-character truncation. Weston never
sets that flag (`main`'s `vnc.c` passes `REQUIRE_AUTH` ± `REQUIRE_ENCRYPTION`
and nothing else), and weston authenticates a *user* through PAM. The full
enum in master is still `NONE 1, VNC_AUTH 2, RSA_AES 5, TIGHT 16, VENCRYPT 19,
APPLE_DH 30, RSA_AES256 129` — no RA2ne — and VeNCrypt still hard-rejects
anything but `X509_PLAIN`.

The gap is a deliberate design split, not a version lag: neatvnc implements
only the *encrypting* RSA-AES variants, noVNC only the non-encrypting one
(RA2ne), because AES over every framebuffer byte in JS is expensive and it
assumes `wss://` underneath. It will not converge on its own.

### The patch that would make this proper

Add RA2ne (type 6) to neatvnc. It is the same handshake as RSA-AES, which
neatvnc already implements — it just stops encrypting afterwards:

- `include/rfb-proto.h` — `RFB_SECURITY_TYPE_RSA_AES_NE = 6` (and `_NE_256 = 130`)
- `src/server.c` — offer them under the same `!REQUIRE_ENCRYPTION` guard as
  Apple DH; map 6 → SHA1/AES_EAX and 130 → SHA256/AES256_EAX in the
  `security_handshake()` switch, with a "session stays plaintext" flag
- `src/auth/rsa-aes.c` — downgrade the stream to plaintext after credentials
  are accepted, before SecurityResult
- `src/stream/rsa-aes.c` — the inverse of `stream_upgrade_to_rsa_eas()`. The
  switch point is clean: the client is blocked on SecurityResult, so nothing
  is buffered.

~60–100 lines, nearly all reusing existing reviewed code. It gives noVNC
something to verify: `ra2.js` fires a `serververification` event carrying the
server's public key, exposes `approveServer()`, and rejects keys outside
1024–8192 bits. Apple DH offers nothing to verify at all.

It is **not** SSH-style TOFU on its own, though — that needs a second, weston
patch. neatvnc generates the RSA key in memory on first use and persists it
only if the application calls `nvnc_set_rsa_creds()`, which weston never does:
not in 14.0.2, and not in `main` (16.x), whose `vnc.c` does not contain the
string "rsa" at all. Measured on the real image:

```
run 1:                      89-4d-a6-13-04-f1-99-30
run 1 again (same process): 89-4d-a6-13-04-f1-99-30
run 2 (after restart):      c2-2c-da-81-c6-ab-b4-91
```

So the fingerprint rotates every restart, and "check the fingerprint" decays
into "click approve" — the same click-through training the self-signed cert
already produces. The library has exposed the setter for years; weston just
needs a `--vnc-rsa-key=FILE` option to call it.

### `wss://` is load-bearing, not merely advisable

Browsers expose `window.crypto.subtle` only in a secure context. noVNC's RA2ne
path uses it, so on a plain `http://` origin the client dies outright:

```
TypeError: Cannot read properties of undefined (reading 'digest')
    at RFB.serverVerify (app/ui.js)
    at RSAAESAuthenticationState.negotiateRA2neAuthAsync (core/ra2.js)
```

That is a good property: the insecure deployment refuses to run rather than
quietly falling back to something weaker. (Apple DH would have worked over
plain http, since that path uses noVNC's own crypto shims.)

**File it upstream rather than carrying it.** Shipping a forked crypto library
on production line-control stations, to close a MITM hole on a hop that never
leaves the host, is a bad trade. Upstream it (published spec, TigerVNC already
implements the family) and it arrives via Debian with nothing to maintain. It
only becomes worth carrying locally if the VNC hop starts crossing the plant
network — and even then, transport (WireGuard, stunnel, a management VLAN)
beats a fork.

Meanwhile the cheaper and bigger win is `centroid:foo`: Apple DH's weakness
only bites on an untrusted path, but a shared weak password in a committed
compose file bites everywhere.

### Status

The patch exists and runs: `centroid-is/dockers` PR #3 builds neatvnc with
types 6 and 130 and ships it in the weston image. It has been exercised on the
`housecontrol-hmi` rig against the real DRM + `screen-share` configuration,
with a browser reaching the live HMI over `wss://` through noVNC. It is
deliberately **not** upstreamed pending review.

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

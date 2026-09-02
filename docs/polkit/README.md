# Station polkit rules

Rules the HMI needs on the host it manages over D-Bus. They are **not**
installed by this repo — the app ships in a container that mounts only
`/var/run/dbus/system_bus_socket`, so it cannot write to the host's `/etc`.
Install them through station provisioning (the `dockers` repo).

| File | Grants | Needed by |
|---|---|---|
| `49-centroid-clock.rules` | `timedate1.set-time`, `set-timezone`, `set-local-rtc`, `set-ntp`, `timesync1.set-runtime-servers` | Date & Time on the About Linux page |

NetworkManager needs no rule from us: Debian's `network-manager` package
already ships `org.freedesktop.NetworkManager.rules`, granting
`settings.modify.system` to `local && active` members of `sudo` or `netdev`.
That is why the IP settings page has always been able to write.

## Installing

```sh
sudo install -m 0644 49-centroid-clock.rules /etc/polkit-1/rules.d/
```

polkit picks rules up without a restart.

## Checking

As the user the HMI container runs as (`centroid`, uid 1000):

```sh
pkcheck --action-id org.freedesktop.timedate1.set-ntp --process $$
echo $?
```

`0` means granted. `2`, with `Authorization requires authentication and -u
wasn't passed`, means the rule is not in effect — which is the state every
station is in before these are installed.

## Why a rule rather than a polkit agent

The obvious alternative is to run an authentication agent so the operator can
type an administrator password. That does not work here: the HMI is a
fullscreen kiosk with no desktop session, and the container has no agent. The
D-Bus calls pass `allow_interactive_authorization`, so an agent would be used
if one ever existed, but the rule is what makes the feature work today.

## What this does not cover

`SetRuntimeNTPServers` is the only NTP server setter systemd exposes on the
bus, and it is runtime-only — timesyncd forgets the list when it restarts.
Persistent servers live in `/etc/systemd/timesyncd.conf`, which the container
cannot write. The HMI works around this by storing the operator's list in
device-local preferences and re-applying it on start; see
`ntpServersPrefsKey` in `lib/core/system_clock.dart`. If you would rather the
host own the list, set `NTP=` in `timesyncd.conf` through provisioning — the
page shows those as "From /etc/systemd/timesyncd.conf on the host".

## Checking a station's clock from a workstation

`tool/probe_clock.dart` reads the same properties the page does, over an SSH
D-Bus bridge, and prints them parsed:

```sh
dart run tool/probe_clock.dart 10.50.10.11 centroid ~/.ssh/id_ed25519
```

Useful for confirming a station's time source during commissioning without
walking to the panel, and for checking that a parsing change still agrees
with `timedatectl show-timesync` on real hardware.

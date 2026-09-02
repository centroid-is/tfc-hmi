# mpv client API headers

`client.h` and `render.h`, copied verbatim from
[mpv](https://github.com/mpv-player/mpv) at tag `v0.40.0` — the version Debian
trixie ships as `libmpv2`, which is what the station images install.

They are vendored rather than taken from `libmpv-dev` because this plugin
resolves libmpv at runtime (see `../../mpv_library.h`) and so must build in the
eLinux toolchain image, which has no mpv development package. Nothing here is
modified; the render API's parameter enum values are ABI, so re-copy rather
than hand-edit if this ever needs updating.

Both files are ISC licensed — see the notice at the top of each.

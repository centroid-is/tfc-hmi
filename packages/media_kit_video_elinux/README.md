# media_kit_video_elinux

Video output for `package:media_kit` on flutter-elinux stations.

`package:media_kit_video` splits into a Dart half (the `Video` widget and
`VideoController`) and a native half that renders frames into a Flutter
texture. The native half ships for GTK, Windows, macOS, iOS and Android —
flutter-elinux is none of those, so on an eLinux build `VideoController`
creation fails with

    MissingPluginException(No implementation found for method
    VideoOutputManager.Create on channel com.alexmercerind/media_kit_video)

This package answers that channel. The Dart half is untouched and unaware.

## How it works

* `VideoOutputManager.Create` builds an mpv render context in software mode
  (`MPV_RENDER_API_TYPE_SW`) for the `mpv_handle` Dart passes down, registers
  a pixel-buffer texture with the eLinux embedder, and reports the texture id
  back over `VideoOutput.Resize`.
* Frames are rendered on the thread that is about to upload them: mpv's update
  callback only marks the texture dirty.
* Hardware rendering is not offered. mpv's OpenGL render API needs the
  embedder's EGL context and flutter-elinux gives plugins no way to reach it.
  `enableHardwareAcceleration` is accepted and ignored.
* libmpv is resolved with `dlopen`/`dlsym` at first use rather than linked, so
  the eLinux toolchain image needs no `libmpv-dev`, and a station without
  libmpv fails the channel call with a message instead of failing to start.
  The runtime image must still ship libmpv (Debian: `libmpv2`) — see
  `docker/frontend/Dockerfile`.

## Tests

The parts that are neither Flutter nor mpv — dimension parsing, the render
budget, the symbol table — are unit tested and run in CI:

    cmake -S elinux/test -B build/test && cmake --build build/test
    ctest --test-dir build/test --output-on-failure

`elinux/third_party/mpv` holds mpv's `client.h` and `render.h` (ISC), copied
verbatim from mpv v0.40.0.

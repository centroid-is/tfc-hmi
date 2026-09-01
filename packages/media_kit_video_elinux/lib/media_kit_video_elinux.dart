/// eLinux implementation of package:media_kit_video's native video output.
///
/// This package has no Dart API. It exists to put a native implementation of
/// the `com.alexmercerind/media_kit_video` method channel into eLinux builds,
/// where upstream's GTK plugin cannot be registered. Depend on it from the
/// app; keep using `package:media_kit_video` in code.
library media_kit_video_elinux;

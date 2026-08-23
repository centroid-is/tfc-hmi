import 'dart:convert';

/// Decodes the bytes of one PLC source file lifted out of an uploaded archive.
///
/// Both zip readers used to do this with `String.fromCharCodes`, which is a
/// Latin-1 read of whatever bytes it is handed. The two UTF-8 bytes of `æ`
/// came back as `Ã¦`, so a Schneider or TwinCAT export naming a block
/// `FB_Færiband` was indexed as `FB_FÃ¦riband` — and that is the text the MCP
/// tools then serve. The unzipped Schneider branch already used `utf8.decode`,
/// so the same file parsed correctly or incorrectly depending on nothing but
/// whether it arrived inside a zip.
///
/// UTF-8 is tried first, because that is what current exports are, and
/// because `utf8.decode` also drops the leading byte-order mark that Windows
/// tooling writes. Keeping the BOM left three stray characters in front of
/// the XML declaration, which made `XmlDocument.parse` throw; that throw was
/// swallowed into a `skippedFiles` counter nothing surfaced, so the upload
/// reported success having indexed nothing at all.
///
/// Latin-1 is the fallback rather than `allowMalformed: true` because every
/// Icelandic letter — þ æ ö ð and the rest — lives inside Latin-1. An older
/// export genuinely encoded that way decodes exactly, where `allowMalformed`
/// would replace each accented character with U+FFFD and lose it for good.
/// Latin-1 maps all 256 byte values, so the fallback cannot itself throw: a
/// file that is neither encoding degrades to mojibake rather than being
/// dropped, which is the same bargain the old code struck but only for files
/// that were never UTF-8 to begin with.
String decodeSourceBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

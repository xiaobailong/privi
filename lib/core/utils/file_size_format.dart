/// Human-readable media file size, shared by every surface that shows sizes
/// (media list rows, details sheet, vault storage summary).
///
/// Boundaries match the previous `settings_screen._formatBytes`:
/// - `< 1024` bytes → whole bytes (`0 B`, `832 B`)
/// - KB / MB → one decimal (`12.4 KB`, `1.8 MB`)
/// - GB and up → two decimals (`1.25 GB`)
/// - `null` (unknown, e.g. a gallery asset whose size lookup failed) → `—`
String formatFileSize(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}

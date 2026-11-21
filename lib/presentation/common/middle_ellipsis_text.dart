import 'package:flutter/material.dart';

/// Single-line text that elides in the **middle**, so both the start and the
/// end of a file name stay readable (`IMG_20240101_…_0001.jpg` instead of
/// `IMG_20240101_123456_long_…`).
///
/// Measures with a [TextPainter] and caches the result keyed by text, style,
/// available width and text scale, so rebuild-heavy lists never re-measure
/// unless something actually changed.
class MiddleEllipsisText extends StatefulWidget {
  const MiddleEllipsisText(
    this.text, {
    super.key,
    this.style,
    this.ellipsis = '…',
    this.headRatio = 0.6,
  });

  final String text;
  final TextStyle? style;

  /// Separator inserted between the kept head and tail.
  final String ellipsis;

  /// Share of the kept characters reserved for the head; the tail takes the
  /// rest. Slightly head-heavy because the leading part of a name carries most
  /// of its identity.
  final double headRatio;

  @override
  State<MiddleEllipsisText> createState() => _MiddleEllipsisTextState();
}

class _MiddleEllipsisTextState extends State<MiddleEllipsisText> {
  String? _cacheKey;
  String? _cached;

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final text = _elide(context, style, maxWidth);
        return Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: style,
        );
      },
    );
  }

  String _elide(BuildContext context, TextStyle style, double maxWidth) {
    final text = widget.text;
    if (text.isEmpty || !maxWidth.isFinite || maxWidth <= 0) return text;

    final scaler = MediaQuery.textScalerOf(context);
    final key = '${text.length}|${text.hashCode}|${style.hashCode}|'
        '$maxWidth|${scaler.scale(10)}|${widget.ellipsis}|${widget.headRatio}';
    if (_cacheKey == key && _cached != null) return _cached!;

    final elided = _measure(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaler: scaler,
      textDirection: Directionality.of(context),
      ellipsis: widget.ellipsis,
      headRatio: widget.headRatio,
    );
    _cacheKey = key;
    _cached = elided;
    return elided;
  }
}

String _measure({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextScaler textScaler,
  required TextDirection textDirection,
  required String ellipsis,
  required double headRatio,
}) {
  final painter = TextPainter(
    maxLines: 1,
    textScaler: textScaler,
    textDirection: textDirection,
  );

  try {
    bool fits(String candidate) {
      painter.text = TextSpan(text: candidate, style: style);
      painter.layout();
      return painter.width <= maxWidth;
    }

    if (fits(text)) return text;

    // Not even the ellipsis fits: let the parent clip it.
    if (!fits(ellipsis)) return ellipsis;

    // Binary search the largest kept-character count that still fits.
    var low = 0;
    var high = text.length - 1;
    var best = ellipsis;
    while (low <= high) {
      final keep = (low + high) ~/ 2;
      final candidate = _slice(
        text,
        keep,
        ellipsis: ellipsis,
        headRatio: headRatio,
      );
      if (fits(candidate)) {
        best = candidate;
        low = keep + 1;
      } else {
        high = keep - 1;
      }
    }
    return best;
  } finally {
    painter.dispose();
  }
}

String _slice(
  String text,
  int keep, {
  required String ellipsis,
  required double headRatio,
}) {
  if (keep <= 0) return ellipsis;
  var headLen = (keep * headRatio).ceil();
  if (headLen > keep) headLen = keep;
  var tailLen = keep - headLen;

  var headEnd = headLen;
  // Never split a surrogate pair at the head boundary.
  if (headEnd > 0 &&
      headEnd < text.length &&
      _isHighSurrogate(text.codeUnitAt(headEnd - 1))) {
    headEnd -= 1;
  }

  var tailStart = text.length - tailLen;
  // A low surrogate at the boundary means its high half sits in the head, so
  // pull the boundary back one unit and keep the pair intact in the tail.
  if (tailLen > 0 &&
      tailStart > 0 &&
      _isLowSurrogate(text.codeUnitAt(tailStart))) {
    tailStart -= 1;
  }
  if (tailStart < headEnd) tailStart = headEnd;

  final head = text.substring(0, headEnd);
  final tail = text.substring(tailStart);
  return '$head$ellipsis$tail';
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

import 'package:flutter/material.dart';

/// Shared folder-cover memory cache so hide/refresh can drop stale thumbs.
abstract final class FolderCoverCache {
  static final Map<String, ImageProvider> _cache = {};

  static String key(String pathId) => pathId;

  static ImageProvider? get(String k) => _cache[k];

  static void put(String k, ImageProvider img) {
    _cache[k] = img;
    if (_cache.length > 80) _cache.remove(_cache.keys.first);
  }

  static void clear({String? pathId}) {
    if (pathId == null) {
      _cache.clear();
      return;
    }
    _cache.remove(pathId);
  }
}

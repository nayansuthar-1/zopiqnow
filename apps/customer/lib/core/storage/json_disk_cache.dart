import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:zopiqnow/core/observability/crash_reporter.dart';

/// Rows from PostgREST, kept on disk so the app opens with content.
///
/// **The rows and not the entities.** Every data source in this app already
/// maps `Map<String, dynamic>` → domain entity in one place
/// (`restaurantFromRow`, `menuItemFromRow`). Caching the mapped objects would
/// need a second serialiser per entity and a version to invalidate it when a
/// field is added; caching the rows PostgREST actually returned means the
/// existing mapper runs over cached rows exactly as it runs over fresh ones, and
/// there is only ever one mapping.
///
/// **Not `shared_preferences`.** That is documented in `pubspec.yaml` as "the
/// selected address id, recent searches" — small scalars read synchronously at
/// startup. A menu is tens of kilobytes of JSON and belongs in a file, not in
/// the map that has to be fully loaded before the first frame.
///
/// The directory is application *support*, not cache: this data exists to make
/// a dead connection survivable, and a store the OS may reclaim at the moment
/// storage runs low is not that. Contrast [ZopiqImageStore], which is in the
/// cache directory precisely because a re-download is the correct failure mode
/// there.
class JsonDiskCache {
  const JsonDiskCache._();

  static Future<Directory>? _directory;

  /// Reads [key], runs [fetch], and decides between them.
  ///
  /// The contract, in the order the cases are tried:
  ///
  /// 1. A cached copy younger than [freshFor] is returned **immediately** and a
  ///    refresh runs behind it. This is the case that makes a cold open on a
  ///    slow connection paint instantly instead of spinning.
  /// 2. Otherwise the network is awaited, bounded by [timeout] — on 2G a
  ///    PostgREST call can hang for half a minute, and a stale answer now beats
  ///    a fresh one after the customer has closed the app.
  /// 3. If that fails or times out, a **stale** cached copy is returned. Age is
  ///    not a reason to show nothing.
  /// 4. With no cache at all, the original error is rethrown. A first run with
  ///    no connection is a genuine failure and the screen must say so.
  static Future<List<Map<String, dynamic>>> rows({
    required String key,
    required Future<List<Map<String, dynamic>>> Function() fetch,
    Duration freshFor = const Duration(minutes: 5),
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final _Entry? cached = await _read(key);

    if (cached != null && cached.age < freshFor) {
      // Fire and forget. A refresh that fails changes nothing on screen — the
      // customer already has the answer this call was for.
      unawaited(_refresh(key, fetch, timeout));
      return cached.rows;
    }

    try {
      final List<Map<String, dynamic>> fresh = await fetch().timeout(timeout);
      await _write(key, fresh);
      return fresh;
    } catch (error, stack) {
      if (cached != null) {
        // Worth reporting even though it is handled: this is the shape of the
        // 29 July outage — a caught exception behind a screen that still looked
        // fine. Serving stale content indefinitely is a silent failure.
        CrashReporter.recordHandled(
          error,
          stack,
          reason: 'JsonDiskCache($key) served stale rows',
        );
        return cached.rows;
      }
      rethrow;
    }
  }

  /// Drops one key. For the caller that knows its data just changed — placing an
  /// order invalidates the order list — rather than waiting for [freshFor].
  static Future<void> invalidate(String key) async {
    try {
      final File file = await _fileFor(key);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A cache that cannot be dropped will age out on its own.
    }
  }

  static Future<void> _refresh(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetch,
    Duration timeout,
  ) async {
    try {
      await _write(key, await fetch().timeout(timeout));
    } catch (_) {
      // Background work behind a painted screen. The cached copy stands.
    }
  }

  static Future<_Entry?> _read(String key) async {
    try {
      final File file = await _fileFor(key);
      if (!file.existsSync()) return null;

      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;

      final int at = (decoded['at'] as num).toInt();
      final List<dynamic> raw = decoded['rows'] as List<dynamic>;

      return _Entry(
        rows: raw.cast<Map<String, dynamic>>(),
        age: DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(at),
        ),
      );
    } catch (_) {
      // Unreadable, truncated, or written by a build whose shape has since
      // changed. All three are a miss, and the next write repairs it.
      return null;
    }
  }

  static Future<void> _write(String key, List<Map<String, dynamic>> rows) async {
    try {
      final File file = await _fileFor(key);
      // `.part` then rename, for the reason `ZopiqImageStore` does it: a
      // half-written file that still parses is worse than no cache.
      final File part = File('${file.path}.part');
      await part.writeAsString(
        jsonEncode(<String, Object>{
          'at': DateTime.now().millisecondsSinceEpoch,
          'rows': rows,
        }),
        flush: true,
      );
      await part.rename(file.path);
    } catch (_) {
      // A full disk costs the cache, never the screen.
    }
  }

  static Future<File> _fileFor(String key) async {
    final Directory dir = await (_directory ??= _resolveDirectory());
    // The keys are ours and already safe, but a restaurant id reaches this from
    // the database, so anything that could climb a path is stripped rather than
    // trusted.
    final String safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.json');
  }

  static Future<Directory> _resolveDirectory() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory(
      '${base.path}${Platform.pathSeparator}row_cache',
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }
}

@immutable
class _Entry {
  const _Entry({required this.rows, required this.age});

  final List<Map<String, dynamic>> rows;
  final Duration age;
}

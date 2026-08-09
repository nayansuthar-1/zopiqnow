import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Encoded remote images, kept on disk between launches.
///
/// Flutter's [ImageCache] is memory only, so every food photo was downloaded
/// again on every cold start. On Indian mobile data that is a cost the customer
/// pays, and it is the part of ZOMATO_PARITY B8's perf item with real money in
/// it — a catalogue of fifty dish photos re-fetched daily, per install.
///
/// **Deliberately not `cached_network_image`.** That would be a new package and
/// therefore an approved Rule 3 request. Both packages this needs — `crypto` and
/// `path_provider` — were already resolved in the root lockfile as transitive
/// dependencies, so `zopiq_ui` declares them at the versions already frozen and
/// **no version moves**. The same transitive-to-direct move `url_launcher` made
/// in B5 and `http` made for the profile upload.
///
/// The directory is the OS *cache* directory, not documents: Android and iOS are
/// both free to delete it under storage pressure, which is exactly the contract
/// a cache should have.
class ZopiqImageStore {
  ZopiqImageStore._();

  static final ZopiqImageStore instance = ZopiqImageStore._();

  /// Entries older than this are swept. There is no LRU touch on read — a write
  /// on every image draw costs more than the occasional re-download of a photo
  /// that is genuinely still in use.
  static const Duration _maxAge = Duration(days: 30);

  /// Ceiling for the whole directory. Far above what this catalogue needs, and
  /// low enough to be a good guest on a 32 GB phone.
  static const int _maxBytes = 50 * 1024 * 1024;

  /// One client for every image: a new [HttpClient] per photo throws away
  /// connection reuse on the screen that opens the most connections at once.
  final HttpClient _client = HttpClient();

  /// Two providers for the same URL at different decode widths are two cache
  /// keys, so without this they would be two downloads racing to write one file.
  final Map<String, Future<Uint8List>> _inFlight = <String, Future<Uint8List>>{};

  Future<Directory>? _directory;

  /// The bytes for [url], from disk if they are there and from the network
  /// otherwise. [onProgress] receives download progress only — a disk hit
  /// reports nothing, because there is nothing to wait for.
  Future<Uint8List> bytesFor(
    String url,
    void Function(int loaded, int? total) onProgress,
  ) {
    final Future<Uint8List>? pending = _inFlight[url];
    if (pending != null) return pending;

    final Future<Uint8List> load = _read(url, onProgress).whenComplete(() {
      _inFlight.remove(url);
    });
    _inFlight[url] = load;
    return load;
  }

  /// Deletes what has aged out, then the oldest entries until the directory is
  /// back under [_maxBytes]. Call it once after the first frame; it never
  /// throws, because an unswept cache is still a working cache.
  Future<void> sweep() async {
    try {
      final Directory dir = await (_directory ??= _resolveDirectory());
      final DateTime cutoff = DateTime.now().subtract(_maxAge);
      final List<MapEntry<File, FileStat>> live = <MapEntry<File, FileStat>>[];
      int total = 0;

      await for (final FileSystemEntity entity in dir.list()) {
        if (entity is! File) continue;
        final FileStat stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
          continue;
        }
        live.add(MapEntry<File, FileStat>(entity, stat));
        total += stat.size;
      }

      if (total <= _maxBytes) return;

      live.sort(
        (MapEntry<File, FileStat> a, MapEntry<File, FileStat> b) =>
            a.value.modified.compareTo(b.value.modified),
      );

      for (final MapEntry<File, FileStat> entry in live) {
        if (total <= _maxBytes) break;
        await entry.key.delete();
        total -= entry.value.size;
      }
    } catch (_) {
      // Housekeeping, and it runs behind a painted screen. Nothing here is
      // worth surfacing to a customer looking at their food.
    }
  }

  Future<Uint8List> _read(
    String url,
    void Function(int loaded, int? total) onProgress,
  ) async {
    final File? file = await _fileFor(url);

    if (file != null && file.existsSync()) {
      try {
        final Uint8List cached = await file.readAsBytes();
        // An empty file is a write that was interrupted before `.part` was
        // renamed away, or a file the OS truncated. Treat it as a miss.
        if (cached.isNotEmpty) return cached;
      } on FileSystemException {
        // Unreadable is a miss too, not a failure.
      }
    }

    final Uint8List bytes = await _download(url, onProgress);
    if (file != null) {
      await _write(file, bytes);
    }
    return bytes;
  }

  Future<File?> _fileFor(String url) async {
    try {
      final Directory dir = await (_directory ??= _resolveDirectory());
      final Digest name = sha1.convert(utf8.encode(url));
      return File('${dir.path}${Platform.pathSeparator}$name');
    } catch (_) {
      // No cache directory — an OS refusal, or no plugin at all under a bare
      // test binding. Fall back to the network and let the memory cache do what
      // it can. Cleared so a later launch can try again.
      _directory = null;
      return null;
    }
  }

  Future<Directory> _resolveDirectory() async {
    final Directory base = await getApplicationCacheDirectory();
    final Directory dir = Directory(
      '${base.path}${Platform.pathSeparator}zopiq_images',
    );
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Written to `.part` and renamed, because a rename is atomic and a
  /// half-written file that is *readable* is worse than no cache at all — it
  /// would decode as a corrupt image on every launch from then on. Leftover
  /// `.part` files age out with everything else.
  Future<void> _write(File file, Uint8List bytes) async {
    try {
      final File part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
    } catch (_) {
      // A full disk costs a cache entry, not the picture on the screen.
    }
  }

  Future<Uint8List> _download(
    String url,
    void Function(int loaded, int? total) onProgress,
  ) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      throw ZopiqImageException('not a URL: $url');
    }

    final HttpClientRequest request = await _client.getUrl(uri);
    final HttpClientResponse response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      // Drained, or the socket is never returned to the pool.
      await response.drain<void>();
      throw ZopiqImageException('HTTP ${response.statusCode} for $url');
    }

    return consolidateHttpClientResponseBytes(
      response,
      onBytesReceived: onProgress,
    );
  }
}

/// Why an image could not be fetched. Reaches the caller's `errorBuilder`, and
/// carries the URL so a Crashlytics report says which one.
class ZopiqImageException implements Exception {
  const ZopiqImageException(this.message);

  final String message;

  @override
  String toString() => 'ZopiqImageException: $message';
}

/// [ImageProvider] over [ZopiqImageStore] — the disk-backed counterpart to
/// [NetworkImage], and a drop-in for it.
@immutable
class ZopiqDiskImage extends ImageProvider<ZopiqDiskImage> {
  const ZopiqDiskImage(this.url);

  final String url;

  @override
  Future<ZopiqDiskImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ZopiqDiskImage>(this);

  @override
  ImageStreamCompleter loadImage(
    ZopiqDiskImage key,
    ImageDecoderCallback decode,
  ) {
    final StreamController<ImageChunkEvent> chunkEvents =
        StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _decode(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: 1,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[ErrorDescription(key.url)],
    );
  }

  Future<ui.Codec> _decode(
    ZopiqDiskImage key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      final Uint8List bytes = await ZopiqImageStore.instance.bytesFor(key.url, (
        int loaded,
        int? total,
      ) {
        if (!chunkEvents.isClosed) {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: loaded,
              expectedTotalBytes: total,
            ),
          );
        }
      });
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // A failure must not sit in the memory cache: the next build has to be
      // free to try again rather than be handed the same error. This is what
      // [NetworkImage] does, for the same reason.
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      unawaited(chunkEvents.close());
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ZopiqDiskImage && other.url == url);

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'ZopiqDiskImage("$url")';
}

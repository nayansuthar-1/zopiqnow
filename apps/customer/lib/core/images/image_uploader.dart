import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:zopiqnow/app/env.dart';

/// Where a photo comes from. The customer picks this before the picker opens,
/// because the two are different system UIs and Android will not offer both.
enum PhotoSource { camera, gallery }

/// Takes a photo off the device and puts it on Cloudinary, returning the URL.
///
/// The interface exists for the seam: the real one talks to a camera and a CDN,
/// a test hands back a URL without either. Nothing above it knows there is an
/// upload at all — the profile screen asks for "a photo" and gets a URL.
///
/// Mirrors `apps/vendor/lib/core/images/image_uploader.dart` rather than sharing
/// with it: the two apps have no common package below the design system, and
/// hoisting eighty lines into one would be a package to justify, version and
/// build for both.
abstract interface class ImageUploader {
  /// Opens [source], uploads what the customer chose, and returns its Cloudinary
  /// delivery URL. Null when they backed out without choosing — that is a
  /// decision, not a failure. Throws [ImageUploadFailure] when the upload itself
  /// fails, so the caller can keep the old photo and say why.
  Future<String?> pickAndUpload(PhotoSource source);
}

class ImageUploadFailure implements Exception {
  const ImageUploadFailure([
    this.message = 'We couldn\'t upload that photo. Please try again.',
  ]);

  final String message;
}

class CloudinaryImageUploader implements ImageUploader {
  const CloudinaryImageUploader();

  @override
  Future<String?> pickAndUpload(PhotoSource source) async {
    // Downscaled and recompressed on the device before it ever leaves. An
    // avatar is drawn at 108px at the very largest, so 720 is already generous
    // — and an 8 MB camera original is a slow upload on a phone that is
    // probably on mobile data, for pixels nothing will ever show.
    final XFile? file = await ImagePicker().pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 720,
      maxHeight: 720,
      imageQuality: 80,
    );
    if (file == null) return null;

    final Uri endpoint = Uri.parse(
      'https://api.cloudinary.com/v1_1/${Env.cloudinaryCloudName}/image/upload',
    );

    try {
      final http.MultipartRequest request =
          http.MultipartRequest('POST', endpoint)
            ..fields['upload_preset'] = Env.cloudinaryUploadPreset
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                await file.readAsBytes(),
                filename: file.name,
              ),
            );

      final http.Response response = await http.Response.fromStream(
        await request.send(),
      );
      if (response.statusCode != 200) throw const ImageUploadFailure();

      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      final String? secureUrl = body['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw const ImageUploadFailure();
      }
      return secureUrl;
    } on ImageUploadFailure {
      rethrow;
    } on Object {
      // A dropped connection, a malformed response, a picker that threw, a
      // camera permission denied at the OS level — the customer gets one
      // sentence, not a stack trace.
      throw const ImageUploadFailure();
    }
  }
}

/// Overridden in tests, which have neither a camera nor a network.
final Provider<ImageUploader> imageUploaderProvider = Provider<ImageUploader>(
  (Ref ref) => const CloudinaryImageUploader(),
);

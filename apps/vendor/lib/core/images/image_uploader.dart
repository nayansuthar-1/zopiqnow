import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:zopiq_vendor/app/env.dart';

/// Picks a photo off the device and puts it on Cloudinary, returning the URL.
///
/// The whole point of the interface is the seam: the real one talks to a gallery
/// and a CDN, and a test hands back a URL without either. Nothing above it knows
/// there is an upload at all — a dish editor asks for "a photo" and gets a URL.
abstract interface class ImageUploader {
  /// Opens the gallery, uploads the chosen image, and returns its Cloudinary
  /// delivery URL. Null when the user closed the picker without choosing —
  /// backing out is not a failure. Throws [ImageUploadFailure] when the upload
  /// itself fails, so the caller can keep the old photo and say why.
  Future<String?> pickAndUpload();
}

class ImageUploadFailure implements Exception {
  const ImageUploadFailure([
    this.message = 'We couldn\'t upload that photo. Please try again.',
  ]);

  final String message;
}

/// Uploads through an **unsigned** preset, so the app carries no Cloudinary
/// secret — only the public cloud name and preset name (both in [Env]). The key
/// and secret never leave `.env`; they exist to create and lock down the preset,
/// not to ship in a decompilable binary.
class CloudinaryImageUploader implements ImageUploader {
  const CloudinaryImageUploader();

  @override
  Future<String?> pickAndUpload() async {
    // Downscaled and recompressed on the device before it ever leaves: a phone
    // camera's 8 MB original is a slow upload and a waste of a CDN, and the
    // preset only accepts images anyway.
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
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
      // A dropped connection, a malformed response, a picker that threw — the
      // vendor gets one sentence, not a stack trace.
      throw const ImageUploadFailure();
    }
  }
}

/// Overridden in tests, which have neither a gallery nor a network.
final Provider<ImageUploader> imageUploaderProvider = Provider<ImageUploader>(
  (Ref ref) => const CloudinaryImageUploader(),
);

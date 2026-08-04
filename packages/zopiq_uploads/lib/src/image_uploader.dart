import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Where a photo comes from.
///
/// Its own enum rather than image_picker's `ImageSource`, so callers depend on
/// this package's surface and not on the plugin underneath it.
enum PhotoSource {
  /// The camera, taken now. What a proof photo wants.
  camera,

  /// The device's library. What a dish photo wants — the good shot of the
  /// biryani was taken in better light on a quieter afternoon.
  gallery,
}

/// Picks a photo off the device and puts it on Cloudinary, returning the URL.
///
/// The whole point of the interface is the seam: the real one talks to a camera
/// and a CDN, and a test hands back a URL without either. Nothing above it knows
/// there is an upload at all — a dish editor asks for "a photo" and gets a URL.
abstract interface class ImageUploader {
  /// Opens [source], uploads the chosen image, and returns its Cloudinary
  /// delivery URL. Null when the user closed the picker without choosing —
  /// backing out is not a failure. Throws [ImageUploadFailure] when the upload
  /// itself fails, so the caller can keep the old photo and say why.
  Future<String?> pickAndUpload({PhotoSource source});
}

class ImageUploadFailure implements Exception {
  const ImageUploadFailure([
    this.message = 'We couldn\'t upload that photo. Please try again.',
  ]);

  final String message;
}

/// Uploads through an **unsigned** preset, so the app carries no Cloudinary
/// secret — only the public cloud name and preset name, both passed in by the
/// app. The key and secret never leave `.env`; they exist to create and lock
/// down the preset, not to ship in a decompilable binary.
class CloudinaryImageUploader implements ImageUploader {
  const CloudinaryImageUploader({
    required this.cloudName,
    required this.uploadPreset,
  });

  /// Public — it appears in every delivery URL.
  final String cloudName;

  /// The *unsigned* preset. Carries no secret by design.
  final String uploadPreset;

  @override
  Future<String?> pickAndUpload({
    PhotoSource source = PhotoSource.gallery,
  }) async {
    // Downscaled and recompressed on the device before it ever leaves: a phone
    // camera's 8 MB original is a slow upload and a waste of a CDN, and the
    // preset only accepts images anyway. It matters more for the proof photos
    // than it ever did for a dish — a kitchen mid-rush and a rider on mobile
    // data are the two worst places to send a full-resolution JPEG from.
    final XFile? file = await ImagePicker().pickImage(
      source: switch (source) {
        PhotoSource.camera => ImageSource.camera,
        PhotoSource.gallery => ImageSource.gallery,
      },
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;

    final Uri endpoint = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );

    try {
      final http.MultipartRequest request =
          http.MultipartRequest('POST', endpoint)
            ..fields['upload_preset'] = uploadPreset
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
      // user gets one sentence, not a stack trace.
      throw const ImageUploadFailure();
    }
  }
}

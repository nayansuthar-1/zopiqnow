import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zopiq_uploads/zopiq_uploads.dart';

import 'package:zopiq_rider/app/env.dart';

/// The upload lives in `zopiq_uploads`, shared with the vendor app so the
/// Cloudinary contract cannot drift between them. Re-exported so call sites in
/// this app import one thing.
export 'package:zopiq_uploads/zopiq_uploads.dart'
    show ImageUploadFailure, ImageUploader, PhotoSource, ProofPhotoField;

/// Overridden in tests, which have neither a camera nor a network.
///
/// The cloud name and preset come from this app's [Env] rather than from inside
/// the package: the package holds no configuration of its own, so it cannot
/// disagree with the app that uses it.
final Provider<ImageUploader> imageUploaderProvider = Provider<ImageUploader>(
  (Ref ref) => const CloudinaryImageUploader(
    cloudName: Env.cloudinaryCloudName,
    uploadPreset: Env.cloudinaryUploadPreset,
  ),
);

/// zopiq_uploads — picking a photo and putting it on Cloudinary.
///
/// One copy of the upload contract (cloud name, unsigned preset, multipart
/// fields, `secure_url`) for the two apps that need it: the vendor's dish and
/// storefront editors, and the proof photos the kitchen and the rider take.
library;

export 'src/image_uploader.dart';
export 'src/proof_photo_field.dart';

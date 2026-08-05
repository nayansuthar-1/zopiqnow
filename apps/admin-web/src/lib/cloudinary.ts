/// Reading and rewriting the delivery URLs we store in `image_url`.
///
/// **Why a crop is a URL and not a new file.** Cloudinary builds a derived image
/// the first time anybody asks for one, so a crop can be expressed as a
/// transformation on the asset we already uploaded. That has three consequences
/// worth stating, because they are the reason this file exists at all:
///
///   * the original is never destroyed, so an admin can re-open the adjuster
///     later and widen a crop they took too tight — a canvas export would have
///     thrown away everything outside the box the first time;
///   * nothing is re-uploaded, so adjusting is instant and costs no bandwidth;
///   * the phone downloads exactly the pixels it displays, because the crop and
///     the delivery width are applied server-side in one pass.
///
/// The whole feature is therefore string handling, and this is where it lives so
/// that no screen has to do URL surgery of its own.

/// The shape of a Cloudinary delivery URL:
///
///     https://res.cloudinary.com/<cloud>/image/upload/<transforms…>/v123/folder/id.jpg
///                                                     ^^^^^^^^^^^^  ^^^^^^^^^^^^^^^^^
///                                                     ours to replace   the asset itself
///
/// Everything between `/upload/` and the `v<digits>` segment is a transformation
/// somebody applied — possibly us, on a previous adjustment. It is dropped, which
/// is what makes adjusting idempotent: the second crop is measured against the
/// original image and not against the first crop of it.
const UPLOAD = '/image/upload/'

export type CloudinaryAsset = {
  /// Everything up to and including `/image/upload/`.
  prefix: string
  /// `v123/folder/id.jpg` — the asset, with its version.
  path: string
}

/// Splits a delivery URL into the two halves a transform sits between, or null
/// when this is not a Cloudinary image URL at all.
///
/// Null is an ordinary answer and not a failure: an `image_url` may predate this
/// console, or point at a host we do not control. The caller offers no adjuster
/// for one, which is honest — we cannot crop somebody else's server.
export function parseAsset(url: string): CloudinaryAsset | null {
  if (!url) return null
  const at = url.indexOf(UPLOAD)
  if (at === -1) return null

  const prefix = url.slice(0, at + UPLOAD.length)
  const rest = url.slice(at + UPLOAD.length)

  // Find the version segment. Everything before it is a transformation to be
  // discarded; everything from it on is the asset.
  const segments = rest.split('/')
  const version = segments.findIndex((s) => /^v\d+$/.test(s))
  if (version === -1) {
    // No version in the URL. Unusual but legal — Cloudinary omits it when the
    // asset was requested without one. Then the only safe reading is that there
    // are no transformations either, because we cannot tell where they end.
    return { prefix, path: rest }
  }

  return { prefix, path: segments.slice(version).join('/') }
}

/// A crop box in *source pixels*, which is the only frame of reference both the
/// adjuster and Cloudinary agree on. Percentages would drift the moment anything
/// resized.
export type CropBox = { x: number; y: number; width: number; height: number }

/// The width we deliver at.
///
/// A cover photo is drawn about 390pt wide on a phone and full-bleed on a
/// restaurant page, so 1280 covers a 3× screen with room to spare. It is a
/// ceiling and not a resize: `c_limit` only ever shrinks, so a small original is
/// delivered untouched rather than upscaled into softness.
const DELIVERY_WIDTH = 1280

/// **No `f_auto`, deliberately.** Flutter's `Image.network` sends no useful
/// `Accept` header, so format negotiation has nothing to negotiate with and
/// Cloudinary can answer with something the phone cannot decode. The same trap
/// migration 0054 hit with `f_auto:animated`. The format stays whatever the
/// admin uploaded.
const QUALITY = 'q_auto:good'

/// Builds the delivery URL for a crop of [asset].
///
/// Values are rounded because Cloudinary's `x_`/`w_` take integers, and clamped
/// to at least one pixel because a zero-width crop is a 400 from their API
/// rather than an empty image.
export function croppedUrl(asset: CloudinaryAsset, box: CropBox): string {
  const x = Math.max(0, Math.round(box.x))
  const y = Math.max(0, Math.round(box.y))
  const w = Math.max(1, Math.round(box.width))
  const h = Math.max(1, Math.round(box.height))

  const transform = `c_crop,x_${x},y_${y},w_${w},h_${h}/c_limit,w_${DELIVERY_WIDTH},${QUALITY}`
  return `${asset.prefix}${transform}/${asset.path}`
}

/// The untouched original, for the adjuster to measure and drag against.
///
/// It must be the *original*: opening the adjuster on an already-cropped URL and
/// dragging within it would crop a crop, and the admin would have no way back to
/// the parts of the photo they had trimmed off.
export function originalUrl(asset: CloudinaryAsset): string {
  return `${asset.prefix}${asset.path}`
}

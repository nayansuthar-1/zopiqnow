import { supabase } from './supabase'

/// Two upload paths, because the platform stores two kinds of file and they have
/// opposite requirements.
///
/// A cover photo is *meant* to be public: it is served to every customer browsing
/// the feed, and it goes to Cloudinary through the same unsigned preset the vendor
/// app uses (`apps/vendor/lib/core/images/image_uploader.dart`).
///
/// A licence scan is meant to be seen by an admin and nobody else. It goes to a
/// private Supabase bucket (0034), the database stores its *path*, and the console
/// renders it through a link that expires.

export class UploadFailure extends Error {
  constructor(message = "We couldn't upload that file. Please try again.") {
    super(message)
  }
}

const cloudName = import.meta.env.VITE_CLOUDINARY_CLOUD_NAME
const uploadPreset = import.meta.env.VITE_CLOUDINARY_UPLOAD_PRESET

/// Returns the Cloudinary delivery URL for a public image.
export async function uploadPhoto(file: File): Promise<string> {
  if (!file.type.startsWith('image/')) {
    throw new UploadFailure('That needs to be an image file.')
  }
  // The preset caps size server-side; this is so an admin who picks a 20 MB
  // camera original is told immediately rather than after a two-minute upload.
  if (file.size > 10 * 1024 * 1024) {
    throw new UploadFailure('That photo is over 10 MB. Please pick a smaller one.')
  }

  const form = new FormData()
  form.append('upload_preset', uploadPreset)
  form.append('file', file)

  let body: { secure_url?: string }
  try {
    const response = await fetch(
      `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`,
      { method: 'POST', body: form },
    )
    if (!response.ok) throw new UploadFailure()
    body = await response.json()
  } catch {
    // A dropped connection, a malformed response — one sentence, not a stack trace.
    throw new UploadFailure()
  }

  if (!body.secure_url) throw new UploadFailure()
  return body.secure_url
}

// ---------------------------------------------------------------------------
// Hero motion loops (P4, migration 0054).
// ---------------------------------------------------------------------------

/// What a loop should weigh, and what it may not exceed.
///
/// The target is a budget, not a limit: a slightly heavy loop that an admin has
/// looked at and wants anyway is their call, and the console says the number
/// rather than silently refusing. The hard cap is for the accident — the 40 MB
/// phone clip nobody transcoded — which is not a judgement call.
export const MOTION_TARGET_BYTES = 1.5 * 1024 * 1024
export const MOTION_MAX_BYTES = 4 * 1024 * 1024

/// The transformation that turns the uploaded MP4 into a looping animated WebP,
/// which is what lets the phone play this through `Image.network` with no
/// `video_player` dependency and no change to `pubspec.yaml`.
///
/// Every part of this earns its place, measured against `demo/video/upload/dog`
/// on 2026-07-27:
///
///   f_webp,fl_animated,fl_awebp,w_720,q_auto:eco,du_8,fps_12  → 1,137,876 B
///   f_webp,fl_animated,fl_awebp,w_800,q_auto:eco,du_6         → 2,458,744 B
///   f_webp,fl_animated,fl_awebp,w_800,q_auto:low,du_6         → 2,163,538 B
///   f_webp,fl_animated,w_400                                  →     7,000 B
///
/// Two things that reads as. **`fl_awebp` is load-bearing**: without it
/// Cloudinary answers 200 with `Content-Type: image/webp` and a *single still
/// frame* — a slide that looks correct and does not move. The database refuses a
/// URL without it (0054) for exactly that reason. And **frame rate is the lever,
/// not quality**: dropping to 12 fps more than halves the file where
/// `q_auto:low` shaves 12%. A decorative brand loop at 12 fps reads as film;
/// below about 10 it reads as a stutter.
///
/// `du_8` is the last one: eight seconds is the outer edge of a hero loop, and
/// it truncates rather than refusing so an admin who uploads a 30-second film
/// gets its opening rather than an error.
const MOTION_TRANSFORM =
  'f_webp,fl_animated,fl_awebp,w_720,q_auto:eco,du_8,fps_12'

export type MotionUpload = {
  /// The Cloudinary delivery URL for the animated WebP — the exact URL the
  /// phone will fetch, which is why [bytes] is a fact rather than an estimate.
  url: string
  /// What that URL actually returned, in bytes.
  bytes: number
}

/// Uploads a video and returns the looping WebP it becomes, with its real
/// delivered size.
///
/// The measuring step is not just for the number on screen. Cloudinary builds a
/// derived asset the first time anyone asks for it, so fetching it here is also
/// what stops the *first customer* paying that latency on the home screen.
export async function uploadMotion(file: File): Promise<MotionUpload> {
  if (!file.type.startsWith('video/')) {
    throw new UploadFailure('That needs to be a video file — an MP4 works best.')
  }
  // Generous, because this is the source and Cloudinary does the shrinking. It
  // exists so a wrong file picked by mistake fails now rather than after a
  // five-minute upload on an office connection.
  if (file.size > 100 * 1024 * 1024) {
    throw new UploadFailure('That video is over 100 MB. Trim it before uploading.')
  }

  const form = new FormData()
  form.append('upload_preset', uploadPreset)
  form.append('file', file)

  let body: { public_id?: string; version?: number }
  try {
    const response = await fetch(
      `https://api.cloudinary.com/v1_1/${cloudName}/video/upload`,
      { method: 'POST', body: form },
    )
    if (!response.ok) throw new UploadFailure()
    body = await response.json()
  } catch {
    throw new UploadFailure("We couldn't upload that video. Please try again.")
  }

  if (!body.public_id || !body.version) throw new UploadFailure()

  // Built from `public_id` rather than rewritten out of `secure_url`, so the
  // transformation lands in the one place a delivery URL has room for it and
  // there is no string surgery to get wrong.
  const url =
    `https://res.cloudinary.com/${cloudName}/video/upload/` +
    `${MOTION_TRANSFORM}/v${body.version}/${body.public_id}.webp`

  let bytes: number
  try {
    const delivered = await fetch(url)
    if (!delivered.ok) throw new UploadFailure()
    // The blob, not the `Content-Length` header: a cross-origin response does
    // not expose that header unless the server opts in, and Cloudinary does not.
    bytes = (await delivered.blob()).size
  } catch {
    throw new UploadFailure(
      "That video uploaded, but Cloudinary couldn't turn it into a loop. Try a standard MP4.",
    )
  }

  if (bytes > MOTION_MAX_BYTES) {
    throw new UploadFailure(
      `That loop comes to ${formatBytes(bytes)} — too heavy for a home screen on mobile data. ` +
        `Use a shorter or calmer clip; ${formatBytes(MOTION_TARGET_BYTES)} is the target.`,
    )
  }

  return { url, bytes }
}

export function formatBytes(bytes: number): string {
  return bytes >= 1024 * 1024
    ? `${(bytes / 1024 / 1024).toFixed(1)} MB`
    : `${Math.round(bytes / 1024)} KB`
}

/// Puts a document in the private bucket and returns its path. The path is what
/// goes in the database; it is not a URL and cannot be opened by anyone who finds it.
export async function uploadDocument(
  restaurantId: string,
  kind: 'fssai' | 'pan',
  file: File,
): Promise<string> {
  const ok = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
  if (!ok.includes(file.type)) {
    throw new UploadFailure('Upload a PDF or an image of the document.')
  }
  if (file.size > 10 * 1024 * 1024) {
    throw new UploadFailure('That file is over 10 MB.')
  }

  const extension = file.name.split('.').pop()?.toLowerCase() ?? 'bin'
  // Timestamped rather than a fixed name per kind, so re-uploading a renewed
  // licence never overwrites the one it replaces. Storage is cheap; a licence
  // scan silently replaced by a wrong file is not recoverable.
  const path = `${restaurantId}/${kind}-${Date.now()}.${extension}`

  const { error } = await supabase.storage
    .from('restaurant-docs')
    .upload(path, file, { contentType: file.type })

  if (error) throw new UploadFailure(error.message)
  return path
}

/// A link to a private document, good for five minutes. Deliberately short: this
/// is for an admin to open a scan they are looking at right now, not something to
/// paste into an email.
export async function signedDocumentUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage
    .from('restaurant-docs')
    .createSignedUrl(path, 300)
  if (error || !data) throw new UploadFailure('That document could not be opened.')
  return data.signedUrl
}

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

/// Takes a photo the admin has a *link* to, and makes it ours.
///
/// **It is fetched into Cloudinary rather than stored as the link.** Saving the
/// pasted URL straight into `image_url` would look identical in the console and
/// be three separate problems in production: the image is served by somebody
/// else's host and vanishes the day they move it, we would be hotlinking
/// bandwidth we do not pay for, and — because it is not a Cloudinary asset — it
/// could never be cropped, resized or delivered at the width a phone actually
/// needs.
///
/// Cloudinary's upload endpoint takes a URL in the same `file` field a browser
/// file goes in, and fetches it server-side. So one line of difference here buys
/// a linked photo everything an uploaded one has.
///
/// The fetch happens from Cloudinary's servers, which means a link that needs a
/// login, sits behind a hotlink blocker, or is a *page* rather than an image
/// fails there rather than here — and their sentence is passed through, because
/// "that link is a Google Images search result, not an image" is not something
/// this function can work out on its own.
export async function uploadPhotoByUrl(url: string): Promise<string> {
  const trimmed = url.trim()

  let parsed: URL
  try {
    parsed = new URL(trimmed)
  } catch {
    throw new UploadFailure('That does not look like a web address.')
  }
  // Cloudinary will refuse anything else anyway; this is so the admin is told
  // now, in a sentence about their link rather than about our API.
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new UploadFailure('Paste an http:// or https:// link to an image.')
  }

  const form = new FormData()
  form.append('upload_preset', uploadPreset)
  form.append('file', trimmed)

  let body: { secure_url?: string }
  try {
    const response = await fetch(
      `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`,
      { method: 'POST', body: form },
    )
    if (!response.ok) {
      const reason = await response
        .json()
        .then((e: { error?: { message?: string } }) => e.error?.message)
        .catch(() => undefined)
      throw new UploadFailure(
        reason
          ? `That link could not be fetched: ${reason}`
          : "We couldn't fetch an image from that link.",
      )
    }
    body = await response.json()
  } catch (e) {
    if (e instanceof UploadFailure) throw e
    throw new UploadFailure("We couldn't fetch an image from that link.")
  }

  if (!body.secure_url) throw new UploadFailure()
  return body.secure_url
}

// ---------------------------------------------------------------------------
// Hero motion loops (P4, migration 0054).
// ---------------------------------------------------------------------------

/// What a loop should weigh, and what it may not exceed.
///
/// The target is a budget, not a limit: a heavy loop that an admin has looked at
/// and wants anyway is their call, and the console says the number rather than
/// silently refusing. The hard cap is for the accident — the 4K holiday video
/// picked from the wrong folder — which is not a judgement call.
///
/// **Both were raised when the 8-second truncation was dropped** (1.5 MB / 4 MB
/// before). A whole clip costs what its length costs: measured at `q_auto:best`,
/// an 854×480 source runs about 84 KB per second and a busy 1080p60 one about
/// 360 KB, so a 30-second brand film lands somewhere between 4 and 11 MB. The old
/// 4 MB cap was sized for a guaranteed-8-second loop and would now refuse most
/// real clips — which is the feature failing, not the budget working.
///
/// The reason a bigger number is defensible at all is that `video_player`
/// **streams**: the phone starts playing from the first buffered chunk and only
/// pulls the tail if the customer is still looking at it. Under 0054 the whole
/// animated WebP had to arrive before a single frame appeared, so size was
/// latency; now it is mostly just data spent while somebody watches.
export const MOTION_TARGET_BYTES = 5 * 1024 * 1024
export const MOTION_MAX_BYTES = 25 * 1024 * 1024

/// The transformation that turns the admin's upload into the silent looping MP4
/// the phone plays with `video_player` (migration 0072).
///
/// Until 0072 this produced an **animated WebP** at `w_720,fps_12`, so the phone
/// could decode it through `Image.network` and nothing in `pubspec.yaml` had to
/// move. The resolution and the stutter were the whole price of that, and the
/// measurements say it bought nothing — animated WebP has no interframe
/// compression, so every frame is a separate still. Eight seconds of
/// `demo/video/upload/dog` (854×480, 29.97fps), measured 2026-07-30:
///
///   f_webp,fl_animated,fl_awebp,w_720,q_auto:eco,du_8,fps_12   → 1,137,876 B  (old)
///   f_webp,fl_animated,fl_awebp,q_auto:good,du_8,fps_24        → 3,252,700 B
///   f_webp,fl_animated,fl_awebp,q_90,du_8,fps_30               → 9,085,966 B
///   f_mp4,vc_h264,ac_none,w_1080,c_limit,q_auto:best,du_8      →   599,018 B  (video)
///
/// `du_8` on every row so the comparison is like-for-like. The live transform has
/// **no `du_`** — see below — and delivers that same 13.4-second source whole in
/// 1,128,474 B, still under even the old 1.5 MB target.
///
/// Full resolution and the source frame rate now cost **half** what the
/// downscaled twelve-frame version did. Each part:
///
/// **`q_auto:best`** — the least lossy of the automatic rungs. This is the one
/// deciding quality, and the point of the change, so it is not the place to
/// economise; `q_auto:good` on the same clip is 350,059 B and visibly softer on
/// gradients, which brand artwork is mostly made of.
///
/// **`w_1080,c_limit`** — a ceiling, not a resize. `c_limit` only ever shrinks,
/// so anything narrower than 1080px is delivered untouched at its own width
/// (confirmed above: an 854px source measures identically with and without it).
/// The ceiling exists for the decoder, not the bytes: the hero is 393pt wide, so
/// ~1180px covers a 3× phone, and handing a 4K stream to an entry-level Android 10
/// device asks its decoder for a level it may not support — which fails as a
/// blank loop, not as a slow one.
///
/// **`vc_h264`** — stated rather than left to `f_mp4`'s default, because
/// universal decodability is the requirement. An admin's HEVC or 10-bit phone
/// original would not play on the Android 10 floor.
///
/// **`ac_none`** — a hero loop is silent. Stripping the track is not a quality
/// decision; it removes bytes for something that must never be heard, and means
/// the app is not relying on a mute call to keep a home screen quiet.
///
/// **No `du_`, and that is a deliberate removal.** 0054 truncated to eight
/// seconds — the outer edge of a *decorative* loop, and the right call when every
/// frame was a separate WebP still and length was paid for linearly in bytes the
/// phone had to download before showing anything. Neither half of that holds now:
/// h.264 makes a longer clip far cheaper per second, and the phone streams it. So
/// the whole clip plays and loops, which is what a campaign film is for. The
/// delivered size is measured and shown either way, so length is a thing an admin
/// can see the cost of rather than a rule imposed on them.
const MOTION_TRANSFORM = 'f_mp4,vc_h264,ac_none,w_1080,c_limit,q_auto:best'

/// The poster frame, pulled out of the video the admin just uploaded.
///
/// **This is what lets a slide be "just a video".** `image_url` is `not null` and
/// has been required of every slide since 0053, for reasons that are still all
/// true: the still is the poster, the reduce-motion fallback, what shows while the
/// video buffers, where every failure path lands, and the only thing a customer
/// build older than 0072 can render at all. A video-only slide does not need that
/// rule relaxed — it needs a still, and the video already contains one.
///
/// `so_0` is the **first** frame, deliberately not `so_auto` ("most interesting").
/// The video starts at zero, so frame zero is the one image guaranteed to be in
/// register with the moment playback begins; an interesting frame from the middle
/// would visibly jump the instant the loop started. The `w_1080,c_limit` half
/// matches [MOTION_TRANSFORM] exactly, so the poster and the video are the same
/// framing at the same width rather than two crops of one clip.
///
/// `.jpg` explicitly, not `f_auto`: Flutter's `Image.network` sends no useful
/// `Accept` header, so content negotiation has nothing to negotiate with — the
/// same trap 0054 hit with `f_auto:animated`.
const POSTER_TRANSFORM = 'so_0,w_1080,c_limit,q_auto:best'

export type MotionUpload = {
  /// The Cloudinary delivery URL for the derived MP4 — the exact URL the phone
  /// will fetch, which is why [bytes] is a fact rather than an estimate.
  url: string
  /// What that URL actually returned, in bytes.
  bytes: number
  /// The video's own first frame as a still, for a slide that has no artwork of
  /// its own. Around 25 KB. See [POSTER_TRANSFORM].
  posterUrl: string
}

/// Uploads a video and returns the looping MP4 it becomes, with its real
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
    // Cloudinary's own sentence, not ours. A rejected upload answers 400 with
    // `{"error":{"message":...}}` and that message is the only thing that says
    // *why* — "Image file format mp4 not allowed" (the unsigned preset's
    // `allowed_formats` had no video in it) is a five-minute fix if you can read
    // it and unfixable if all you are told is to try again.
    if (!response.ok) {
      const reason = await response
        .json()
        .then((e: { error?: { message?: string } }) => e.error?.message)
        .catch(() => undefined)
      throw new UploadFailure(
        reason
          ? `Cloudinary refused that video: ${reason}`
          : "We couldn't upload that video. Please try again.",
      )
    }
    body = await response.json()
  } catch (e) {
    // Rethrown so the sentence above survives. Only a dropped connection or a
    // malformed response reaches the generic one now.
    if (e instanceof UploadFailure) throw e
    throw new UploadFailure("We couldn't upload that video. Please try again.")
  }

  if (!body.public_id || !body.version) throw new UploadFailure()

  // Built from `public_id` rather than rewritten out of `secure_url`, so the
  // transformation lands in the one place a delivery URL has room for it and
  // there is no string surgery to get wrong.
  const delivery = `https://res.cloudinary.com/${cloudName}/video/upload`
  const url = `${delivery}/${MOTION_TRANSFORM}/v${body.version}/${body.public_id}.mp4`
  // Not measured, unlike the video. It is one frame — 25 KB on the clip this was
  // built against — and it is only ever fetched by a slide that would otherwise
  // have no artwork at all, so there is no budget question to answer.
  const posterUrl = `${delivery}/${POSTER_TRANSFORM}/v${body.version}/${body.public_id}.jpg`

  const bytes = await measureDelivered(url)

  if (bytes > MOTION_MAX_BYTES) {
    throw new UploadFailure(
      `That loop comes to ${formatBytes(bytes)} — too heavy for a home screen on mobile data. ` +
        `Use a shorter or calmer clip; ${formatBytes(MOTION_TARGET_BYTES)} is the target.`,
    )
  }

  return { url, bytes, posterUrl }
}

/// Fetches the derived MP4 and returns what it actually weighs.
///
/// Downloading the whole file to read a number is the point rather than the cost.
/// Cloudinary builds a derived asset the first time anybody asks for it, so this
/// is also what stops the *first customer* paying the transcode latency on the
/// home screen — and it is why the size an admin is shown is the size a customer
/// downloads rather than an estimate of it.
///
/// **The 423 loop is why this is a function.** While Cloudinary is still building
/// a derived video it answers `423 Locked` instead of the file, and that became
/// reachable the moment the 8-second truncation came off: a 13-second clip
/// transcodes inside the synchronous window (measured: 3.6s) and a minute-long one
/// need not. Treating 423 as a failure would have shown "couldn't transcode it" for
/// exactly the long clips this change exists to allow — and worse, it would have
/// been *intermittent*, since a second attempt on the warmed asset succeeds.
async function measureDelivered(url: string): Promise<number> {
  // Generous, because the alternative to waiting is a wrong error. Bounded,
  // because a genuinely stuck transcode must not hang the form for ever.
  const deadline = Date.now() + 120_000

  for (;;) {
    let response: Response
    try {
      response = await fetch(url)
    } catch {
      throw new UploadFailure(
        "That video uploaded, but the transcoded loop couldn't be fetched. Check your connection and try again.",
      )
    }

    if (response.ok) {
      // The blob, not the `Content-Length` header: a cross-origin response does
      // not expose that header unless the server opts in, and Cloudinary does not.
      return (await response.blob()).size
    }

    if (response.status !== 423) {
      throw new UploadFailure(
        "That video uploaded, but Cloudinary couldn't transcode it. Try a standard MP4.",
      )
    }

    if (Date.now() > deadline) {
      throw new UploadFailure(
        'Cloudinary is still transcoding that clip after two minutes. It is probably too long — try a shorter one, or save the slide again in a few minutes.',
      )
    }

    await new Promise((resolve) => setTimeout(resolve, 3000))
  }
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

/// The same two functions for a rider's papers, against `rider-docs` (0080).
///
/// A separate bucket rather than a folder in `restaurant-docs`, because the
/// storage policies are per bucket and these two sets of documents have no
/// reason to ever share a blast radius. Everything else — private, path in the
/// database, five-minute links — is 0034's argument unchanged.
export type RiderDocKind = 'licence' | 'insurance' | 'id' | 'rc'

export async function uploadRiderDocument(
  email: string,
  kind: RiderDocKind,
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
  // The email is the rider's primary key, and `@` and `.` are both legal in a
  // storage path — but a folder per rider only groups usefully if the name is
  // stable, so it is used as-is rather than sanitised into something that could
  // collide with another rider's.
  const path = `${email}/${kind}-${Date.now()}.${extension}`

  const { error } = await supabase.storage
    .from('rider-docs')
    .upload(path, file, { contentType: file.type })

  if (error) throw new UploadFailure(error.message)
  return path
}

export async function signedRiderDocumentUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage
    .from('rider-docs')
    .createSignedUrl(path, 300)
  if (error || !data) throw new UploadFailure('That document could not be opened.')
  return data.signedUrl
}

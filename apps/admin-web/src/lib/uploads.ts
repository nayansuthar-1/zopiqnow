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

import { useEffect, useRef, useState } from 'react'
import { Button, Modal } from './primitives'
import type { CloudinaryAsset, CropBox } from '../lib/cloudinary'
import { croppedUrl, originalUrl } from '../lib/cloudinary'

/// Drag to move, slide to zoom, and the frame is what gets saved.
///
/// **What this is really doing.** The admin is not editing pixels — they are
/// choosing a rectangle of the original, and the rectangle becomes a Cloudinary
/// transformation on the URL (see `lib/cloudinary.ts`). Nothing is re-uploaded
/// and nothing is destroyed, so a crop taken too tight can be re-opened and
/// widened later.
///
/// **Why a fixed frame rather than a free-hand box.** Every place these photos
/// are shown has a shape decided by the app, not by the photo: a cover fills a
/// card, a dish fills a square tile. A free crop would let an admin choose a
/// rectangle the app then crops *again* to fit, which means the careful framing
/// they just did is undone by a layout they cannot see. Choosing which part of
/// the photo lands inside the shape the app will use is the actual job.
///
/// The whole thing is geometry that a library would also do, and the geometry is
/// twenty lines. `react-easy-crop` is 40 KB and a dependency this project has a
/// standing rule against adding without an approved upgrade task.

export function ImageAdjuster({
  asset,
  /// Width ÷ height of the frame the app will draw this in.
  aspect,
  title,
  onCancel,
  onDone,
}: {
  asset: CloudinaryAsset
  aspect: number
  title: string
  onCancel: () => void
  onDone: (url: string) => void
}) {
  /// The natural size of the original, which is the frame of reference the crop
  /// box is expressed in. Null until the browser has actually decoded it — every
  /// number below is meaningless before that, so nothing is drawn until it lands.
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null)
  const [failed, setFailed] = useState(false)

  /// 1 means "just covers the frame". Above that, the admin is closing in.
  const [zoom, setZoom] = useState(1)
  /// The centre of the crop, as a fraction of the image. Starts dead centre,
  /// which is what every uncropped photo is showing today.
  const [centre, setCentre] = useState({ x: 0.5, y: 0.5 })

  const viewport = useRef<HTMLDivElement>(null)
  const dragging = useRef<{ px: number; py: number } | null>(null)

  const src = originalUrl(asset)

  useEffect(() => {
    const img = new Image()
    // The original may be on a different origin; nothing here reads its pixels,
    // so no CORS request is needed and asking for one would only add a way to
    // fail.
    img.onload = () => setNatural({ w: img.naturalWidth, h: img.naturalHeight })
    img.onerror = () => setFailed(true)
    img.src = src
    return () => {
      img.onload = null
      img.onerror = null
    }
  }, [src])

  /// The crop, in source pixels.
  ///
  /// The frame shows a window onto the image; at zoom 1 that window is the
  /// largest rectangle of [aspect] that fits inside the original. Zooming
  /// shrinks the window — a smaller piece of the photo filling the same frame,
  /// which is what "closer" means.
  function boxFor(n: { w: number; h: number }): CropBox {
    const widest = n.h * aspect
    const base =
      widest <= n.w
        ? { width: widest, height: n.h } // the image is wider than the frame
        : { width: n.w, height: n.w / aspect }

    const width = base.width / zoom
    const height = base.height / zoom

    // Clamped so the window can never leave the image: dragging to the edge
    // stops there rather than revealing a strip of nothing, which Cloudinary
    // would answer with a 400 anyway.
    const x = Math.min(Math.max(centre.x * n.w - width / 2, 0), n.w - width)
    const y = Math.min(Math.max(centre.y * n.h - height / 2, 0), n.h - height)

    return { x, y, width, height }
  }

  function onPointerDown(e: React.PointerEvent) {
    dragging.current = { px: e.clientX, py: e.clientY }
    e.currentTarget.setPointerCapture(e.pointerId)
  }

  function onPointerMove(e: React.PointerEvent) {
    const from = dragging.current
    const box = viewport.current
    if (!from || !box || !natural) return

    const rect = box.getBoundingClientRect()
    const crop = boxFor(natural)

    // A pixel dragged on screen should move the photo by a pixel. The frame
    // shows `crop.width` source pixels across `rect.width` screen pixels, so the
    // conversion is that ratio — and it is why zooming in makes dragging finer
    // rather than faster.
    const dx = ((e.clientX - from.px) * crop.width) / rect.width / natural.w
    const dy = ((e.clientY - from.py) * crop.height) / rect.height / natural.h

    setCentre((c) => ({
      // Dragging right moves the *photo* right, so the window moves left.
      x: Math.min(Math.max(c.x - dx, 0), 1),
      y: Math.min(Math.max(c.y - dy, 0), 1),
    }))
    dragging.current = { px: e.clientX, py: e.clientY }
  }

  function onPointerUp(e: React.PointerEvent) {
    dragging.current = null
    e.currentTarget.releasePointerCapture?.(e.pointerId)
  }

  /// What the frame shows, as CSS. The image is scaled so the crop window fills
  /// the viewport, then shifted so the window's top-left sits at the frame's.
  function imageStyle(): React.CSSProperties {
    if (!natural) return {}
    const crop = boxFor(natural)
    const scale = 100 / (crop.width / natural.w)
    return {
      width: `${scale}%`,
      maxWidth: 'none',
      marginLeft: `${(-crop.x / natural.w) * scale}%`,
      marginTop: `${(-crop.y / natural.h) * scale}%`,
    }
  }

  return (
    <Modal
      title={title}
      size="lg"
      onClose={onCancel}
      footer={
        <>
          <Button variant="secondary" onClick={onCancel}>
            Cancel
          </Button>
          <Button
            disabled={!natural}
            onClick={() => natural && onDone(croppedUrl(asset, boxFor(natural)))}
          >
            Use this crop
          </Button>
        </>
      }
    >
      {failed ? (
        <p className="text-sm text-ink-muted">
          That photo could not be loaded, so there is nothing to adjust. It may have
          been removed since it was uploaded.
        </p>
      ) : (
        <div className="space-y-4">
          <div
            ref={viewport}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerUp}
            className="relative w-full cursor-grab select-none overflow-hidden rounded-[8px] border border-line bg-canvas active:cursor-grabbing"
            style={{ aspectRatio: String(aspect) }}
          >
            {natural ? (
              <img
                src={src}
                alt=""
                draggable={false}
                style={imageStyle()}
                className="block"
              />
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-ink-muted">
                Loading the photo…
              </div>
            )}
          </div>

          <label className="block">
            <span className="mb-1.5 block text-sm font-medium text-ink">Zoom</span>
            <input
              type="range"
              min={1}
              max={4}
              step={0.01}
              value={zoom}
              disabled={!natural}
              onChange={(e) => setZoom(Number(e.target.value))}
              className="w-full accent-brand"
            />
          </label>

          <p className="text-sm text-ink-muted">
            Drag the photo to choose what sits inside the frame. The frame is the
            shape the app draws this in, so what you see here is what a customer
            sees. The original is kept — you can come back and change this later.
          </p>
        </div>
      )}
    </Modal>
  )
}

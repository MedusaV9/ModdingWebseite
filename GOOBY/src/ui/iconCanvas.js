// V6/D3 (PLAN6 Wave D): SVG → canvas rasterizer.
//
// Canvas surfaces (THREE.CanvasTexture painters in roomManager/gardenInteractions
// and any minigame that draws pictographs into a 2d context) must never
// font-render raw emoji: glyph coverage varies per platform and the result
// clashes with the authored icons.js / foodIcons.js art everywhere else.
//
// The pattern: SVG decode is async (Image.decode), but texture creation sites
// are synchronous. So `iconCanvas()` hands back a canvas immediately — blank on
// the very first request, already painted when the markup+size pair is cached —
// and fires `onReady` once pixels land so the caller can flip
// `texture.needsUpdate = true`. Rasterized results are cached forever (the
// catalogs are small and static), so steady-state calls are synchronous.
//
//   const canvas = iconCanvas(icon('musicNote', 48), 64, () => {
//     radioNoteTexture.needsUpdate = true;
//   });
//   radioNoteTexture = new THREE.CanvasTexture(canvas);
//
// For pure 2d-context composition (e.g. drawing an icon INTO a bigger sign
// canvas), use `drawIcon(ctx, svg, x, y, size, onReady)` — same contract: draws
// now when cached, else repaints via onReady.

/** @type {Map<string, { canvas: HTMLCanvasElement, ready: boolean, waiters: Array<() => void> }>} */
const cache = new Map();

function entryFor(svgMarkup, size) {
  const key = `${size}|${svgMarkup}`;
  let entry = cache.get(key);
  if (entry) return entry;

  const canvas = document.createElement('canvas');
  canvas.width = size;
  canvas.height = size;
  entry = { canvas, ready: false, waiters: [] };
  cache.set(key, entry);

  const img = new Image();
  img.onload = () => {
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, size, size);
    ctx.drawImage(img, 0, 0, size, size);
    entry.ready = true;
    const waiters = entry.waiters.splice(0);
    for (const fn of waiters) {
      try { fn(); } catch { /* one bad waiter must not starve the rest */ }
    }
  };
  // utf8 data URI (not base64): keeps multi-byte glyph-free SVG source readable
  // in devtools and avoids btoa() unicode pitfalls.
  img.src = `data:image/svg+xml;utf8,${encodeURIComponent(svgMarkup)}`;
  return entry;
}

/**
 * Rasterize `svgMarkup` at `size`×`size` px. Returns a canvas synchronously;
 * if the pixels are not in yet, `onReady` fires exactly once when they are.
 * The returned canvas is shared per (markup, size) — treat it as read-only.
 */
export function iconCanvas(svgMarkup, size, onReady) {
  const entry = entryFor(svgMarkup, size);
  if (!entry.ready && typeof onReady === 'function') entry.waiters.push(onReady);
  else if (entry.ready && typeof onReady === 'function') onReady();
  return entry.canvas;
}

/**
 * Draw `svgMarkup` into an existing 2d context at (x, y), `size`×`size` px.
 * When the rasterization is still pending, the draw is deferred until decode
 * (using the ctx's then-current transform — intended for one-shot texture
 * painting) and `onReady` fires afterwards so the caller can flip
 * texture.needsUpdate. Returns true when the icon was drawn synchronously.
 */
export function drawIcon(ctx, svgMarkup, x, y, size, onReady) {
  const entry = entryFor(svgMarkup, size);
  if (entry.ready) {
    ctx.drawImage(entry.canvas, x, y, size, size);
    return true;
  }
  entry.waiters.push(() => {
    ctx.drawImage(entry.canvas, x, y, size, size);
    if (typeof onReady === 'function') onReady();
  });
  return false;
}

/** Preload a batch of icons (fire-and-forget warm-up, e.g. on screen open). */
export function preloadIcons(svgMarkups, size) {
  for (const svg of svgMarkups) entryFor(svg, size);
}

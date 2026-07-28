// ola-static — a real map behind the route, without the key leaving the server.
//
// **Why this exists at all.** Ola's tile and static-map APIs are the map we pay
// for, and the key that opens them is referer-restricted: a request without
// `Origin: https://zopiqnow.app` is answered with a 403. That restriction is a
// browser control and nothing more — a native app can send any Origin it likes
// — so shipping the key inside an APK would not be protected by it in any
// meaningful sense. It would simply be a live key sitting in a file anyone can
// unzip. 0046 put the key in Vault for exactly that reason and the phone has
// never held it.
//
// So the phone asks this function for a picture instead. It builds the Ola URL,
// adds the key and the Origin, and streams the PNG back. The key stays here.
//
// **Why a picture and not tiles.** Ola serves vector tiles (`.pbf`), which need
// a vector renderer on the device — a large new dependency, which the version
// freeze does not allow without an approved upgrade task. The static-map API
// returns a finished PNG with our route and our pins already drawn on it, which
// is the same map, needs no dependency at all, and cannot drift out of
// alignment with an overlay because there is no overlay.
//
// **Deliberately not an open proxy.** Nothing here forwards a caller-supplied
// URL. The style is chosen from a list of two, the size is clamped, and the
// overlays are re-serialised from parsed numbers — a caller cannot reach any
// Ola endpoint but this one, in any shape but this one. It is also behind the
// platform's JWT check (deployed *without* `--no-verify-jwt`), so the quota is
// spent only on signed-in customers and riders.
//
// Secret: OLA_MAPS_API_KEY, set as a function secret. The same key 0057 keeps
// in Vault for the routing calls pg_net makes.

const OLA_HOST = "https://api.olamaps.io/tiles/v1/styles";

// The Origin the key is restricted to. Not configurable from the request.
const ORIGIN = "https://zopiqnow.app";

// Two styles, named by what the app is showing rather than by Ola's slug, so a
// restyle is a change here and not a release of three apps.
const STYLES: Record<string, string> = {
  light: "default-light-standard",
  dark: "eclipse-dark-standard",
};

// Ola renders up to 1024 square comfortably. The ceiling is here so a caller
// cannot ask for a poster and spend the quota on it.
const MAX_DIMENSION = 1024;
const MIN_DIMENSION = 64;

// An encoded polyline for a city delivery runs a few hundred characters; ten
// thousand is far past any real route and short of anything that would make the
// upstream URL unreasonable.
const MAX_PATH_CHARS = 10_000;

const MAX_MARKERS = 4;

function clampDimension(raw: string | null, fallback: number): number {
  const n = Number.parseInt(raw ?? "", 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(MAX_DIMENSION, Math.max(MIN_DIMENSION, n));
}

/** `#rrggbb`, `rrggbb` or a bare colour word — normalised to six hex digits. */
function hexColour(raw: string | undefined, fallback: string): string {
  const cleaned = (raw ?? "").replace(/^#/, "");
  return /^[0-9a-fA-F]{6}$/.test(cleaned) ? cleaned : fallback;
}

function isFiniteNumber(n: number): boolean {
  return Number.isFinite(n);
}

Deno.serve(async (req) => {
  const key = Deno.env.get("OLA_MAPS_API_KEY");
  if (!key) {
    return new Response("Map key not configured", { status: 503 });
  }

  const q = new URL(req.url).searchParams;

  const style = STYLES[q.get("style") ?? "light"] ?? STYLES.light;
  const width = clampDimension(q.get("w"), 600);
  const height = clampDimension(q.get("h"), 400);

  // `auto` frames the picture around everything drawn on it — the road and every
  // marker, which is why a rider who has wandered off the quoted route is still
  // in the frame rather than off the edge of it. It is also why nothing on the
  // device needs to know how Web Mercator works.
  const upstream = new URL(
    `${OLA_HOST}/${style}/static/auto/${width}x${height}.png`,
  );

  // The road. `enc:` last, because it is the one value that may itself contain
  // the separator characters Ola parses the options with.
  const encoded = q.get("path");
  if (encoded) {
    if (encoded.length > MAX_PATH_CHARS) {
      return new Response("Route too long", { status: 400 });
    }
    const stroke = hexColour(q.get("stroke") ?? undefined, "FC8019");
    const weight = Math.min(12, Math.max(1, Number.parseInt(q.get("width") ?? "5", 10) || 5));
    upstream.searchParams.append(
      "path",
      `stroke:${stroke}|width:${weight}|enc:${encoded}`,
    );
  }

  // The pins, as `lng,lat,colour` triples. Re-serialised from parsed numbers
  // rather than passed through, so nothing a caller writes reaches Ola verbatim.
  const markers = q.getAll("m").slice(0, MAX_MARKERS);
  for (const marker of markers) {
    const [lngRaw, latRaw, colourRaw] = marker.split(",");
    const lng = Number.parseFloat(lngRaw);
    const lat = Number.parseFloat(latRaw);
    if (!isFiniteNumber(lng) || !isFiniteNumber(lat)) continue;
    if (Math.abs(lat) > 90 || Math.abs(lng) > 180) continue;
    upstream.searchParams.append(
      "marker",
      `${lng},${lat}|${hexColour(colourRaw, "FC8019")}`,
    );
  }

  if (!encoded && markers.length === 0) {
    return new Response("Nothing to draw", { status: 400 });
  }

  upstream.searchParams.set("api_key", key);

  let res: Response;
  try {
    res = await fetch(upstream, { headers: { Origin: ORIGIN } });
  } catch (e) {
    console.error("Ola static fetch failed:", e);
    return new Response("Map unavailable", { status: 502 });
  }

  if (!res.ok) {
    // Ola's own message, logged but not forwarded — it names the upstream host
    // and the shape of our request, and neither is the device's business.
    console.error(`Ola static ${res.status}:`, await res.text());
    return new Response("Map unavailable", { status: 502 });
  }

  // A route's picture is the same picture until the route changes, and the
  // request URL changes whenever anything drawn on it does — including the
  // rider's pin. So it is safe to let the device and any CDN in between hold on
  // to it for a good while.
  return new Response(res.body, {
    status: 200,
    headers: {
      "Content-Type": "image/png",
      "Cache-Control": "public, max-age=86400",
    },
  });
});

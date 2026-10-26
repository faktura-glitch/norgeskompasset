// Turkalender: henter kommende arrangementer fra Wix Events på
// norgeskompasset.no og gir dem til appen i et lite, stabilt format.
// API-nøkkelen ligger som Firebase-secret (WIX_API_KEY) og forlater
// aldri serveren. Svaret caches i Firestore (config/events) i én time
// så Wix ikke kalles for hver app-åpning.

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

setGlobalOptions({ region: "europe-west1", maxInstances: 5 });
admin.initializeApp();

const WIX_API_KEY = defineSecret("WIX_API_KEY");
// Meta-site-id for norgeskompasset.no (synlig i sidens kildekode).
const WIX_SITE_ID = defineString("WIX_SITE_ID", {
  default: "b4f923aa-4267-44ba-a55b-e9454d93420f",
});

const CACHE_DOC = "config/events";
const CACHE_TTL_MS = 60 * 60 * 1000;
const SITE_URL = "https://www.norgeskompasset.no";

/** Henter kommende arrangementer fra Wix Events v1 query-API. */
async function fetchFromWix(apiKey, siteId) {
  const res = await fetch("https://www.wixapis.com/events/v1/events/query", {
    method: "POST",
    headers: {
      Authorization: apiKey,
      "wix-site-id": siteId,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: {
        filter: { status: { $in: ["SCHEDULED", "STARTED"] } },
        sort: [{ fieldName: "scheduling.config.startDate", order: "ASC" }],
        paging: { limit: 100, offset: 0 },
      },
      fieldset: ["FULL"],
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Wix svarte ${res.status}: ${text.slice(0, 300)}`);
  }
  const json = await res.json();
  return (json.events || []).map(normalize).filter((e) => e.start);
}

/** Wix-bilde-id → offentlig URL. */
function imageUrl(img) {
  if (!img) return null;
  if (img.url && img.url.startsWith("http")) return img.url;
  const id = img.id || img.uri;
  return id ? `https://static.wixstatic.com/media/${id}` : null;
}

function geo(addr) {
  const g = addr.geocode || addr.location || null;
  return g ? { lat: g.latitude ?? null, lon: g.longitude ?? null } : { lat: null, lon: null };
}

/** Plukker ut det appen trenger – robust mot små endringer hos Wix. */
function normalize(e) {
  const sched = e.scheduling || {};
  const cfg = sched.config || {};
  const loc = e.location || {};
  const addr = loc.address || {};
  const reg = e.registration || {};
  const ticketing = reg.ticketing || {};
  const lowest = ticketing.lowestTicketPrice || ticketing.lowestPrice || null;
  const slug = e.slug || null;
  const { lat, lon } = geo(addr);
  return {
    id: e.id,
    title: (e.title || "").trim(),
    description: (e.description || e.about || "").trim(),
    start: cfg.startDate || sched.startDate || null,
    end: cfg.endDate || sched.endDate || null,
    formatted: sched.formatted || null,
    timeZone: cfg.timeZoneId || "Europe/Oslo",
    locationName: loc.name || null,
    address: addr.formatted || addr.formattedAddress || null,
    lat,
    lon,
    online: loc.type === "ONLINE",
    image: imageUrl(e.mainImage),
    url: slug ? `${SITE_URL}/event-details/${slug}` : `${SITE_URL}/turer`,
    registrationType: reg.type || null,
    registrationOpen: reg.status ? reg.status === "OPEN_TICKETS" || reg.status === "OPEN_RSVP" : null,
    price: lowest ? Number(lowest.amount ?? lowest.value ?? 0) : null,
    currency: lowest ? lowest.currency || "NOK" : null,
    soldOut: ticketing.soldOut === true,
  };
}

async function readCache(ref) {
  const snap = await ref.get().catch(() => null);
  return snap && snap.data();
}

exports.events = onRequest(
  { secrets: [WIX_API_KEY], cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    res.set("Cache-Control", "public, max-age=300");
    const force = req.query.refresh === "1";
    const ref = admin.firestore().doc(CACHE_DOC);
    try {
      if (!force) {
        const data = await readCache(ref);
        if (data && data.fetchedAt && Date.now() - data.fetchedAt.toMillis() < CACHE_TTL_MS) {
          res.json({ events: data.events, fetchedAt: data.fetchedAt.toDate().toISOString(), cached: true });
          return;
        }
      }
      const events = await fetchFromWix(WIX_API_KEY.value(), WIX_SITE_ID.value());
      const fetchedAt = admin.firestore.Timestamp.now();
      await ref.set({ events, fetchedAt });
      res.json({ events, fetchedAt: fetchedAt.toDate().toISOString(), cached: false });
    } catch (err) {
      console.error("events:", err);
      // Gammel cache er bedre enn ingenting når Wix feiler.
      const data = await readCache(ref);
      if (data && data.events) {
        res.json({ events: data.events, fetchedAt: data.fetchedAt.toDate().toISOString(), cached: true, stale: true });
        return;
      }
      res.status(502).json({ error: "Kunne ikke hente turkalenderen." });
    }
  },
);

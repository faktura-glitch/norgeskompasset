// Turkalender: henter kommende arrangementer fra Wix Events paa
// norgeskompasset.no hver time og skriver dem til Firestore
// (config/events), som appen leser direkte. API-noekkelen ligger som
// Firebase-secret (WIX_API_KEY) og forlater aldri serveren. Ingen
// offentlig HTTP-funksjon trengs, saa org-regelen om "allUsers" er
// uten betydning.

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret, defineString } = require("firebase-functions/params");
const { setGlobalOptions } = require("firebase-functions/v2");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

setGlobalOptions({ region: "europe-west1", maxInstances: 2 });
admin.initializeApp();

const WIX_API_KEY = defineSecret("WIX_API_KEY");
// Meta-site-id for norgeskompasset.no (synlig i sidens kildekode).
const WIX_SITE_ID = defineString("WIX_SITE_ID", {
  default: "b4f923aa-4267-44ba-a55b-e9454d93420f",
});

const EVENTS_DOC = "config/events";
const SITE_URL = "https://www.norgeskompasset.no";
const MAX_DESCRIPTION = 4000;

/** Henter kommende arrangementer fra Wix Events v3 query-API.
 *  (v1 svarer med tom liste for denne siden, v3 gir alle.) */
async function fetchFromWix(apiKey, siteId) {
  const res = await fetch("https://www.wixapis.com/events/v3/events/query", {
    method: "POST",
    headers: {
      Authorization: apiKey,
      "wix-site-id": siteId,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: {
        filter: { status: { $in: ["UPCOMING", "STARTED"] } },
        sort: [{ fieldName: "dateAndTimeSettings.startDate", order: "ASC" }],
        paging: { limit: 100, offset: 0 },
      },
      fields: ["DETAILS", "TEXTS", "REGISTRATION", "URLS"],
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Wix svarte ${res.status}: ${text.slice(0, 300)}`);
  }
  const json = await res.json();
  return (json.events || []).map(normalize).filter((e) => e.start);
}

/** Wix-bilde-id -> offentlig URL. */
function imageUrl(img) {
  if (!img) return null;
  if (img.url && img.url.startsWith("http")) return img.url;
  const id = img.id || img.uri;
  return id ? `https://static.wixstatic.com/media/${id}` : null;
}

function geo(addr) {
  const g = addr.geocode || addr.location || null;
  return g
    ? { lat: g.latitude ?? null, lon: g.longitude ?? null }
    : { lat: null, lon: null };
}

/** Plukker ut det appen trenger - robust mot smaa endringer hos Wix. */
function normalize(e) {
  const dts = e.dateAndTimeSettings || {};
  const loc = e.location || {};
  const addr = loc.address || {};
  const reg = e.registration || {};
  const ticketing = reg.tickets || {};
  const lowest = ticketing.lowestPrice || null;
  const slug = e.slug || null;
  const { lat, lon } = geo(addr);
  return {
    id: e.id,
    title: (e.title || "").trim(),
    description: (e.description || e.shortDescription || "")
      .trim()
      .slice(0, MAX_DESCRIPTION),
    start: dts.startDate || null,
    end: dts.endDate || null,
    formatted: (dts.formatted && dts.formatted.dateAndTime) || null,
    timeZone: dts.timeZoneId || "Europe/Oslo",
    locationName: loc.name || null,
    address: addr.formatted || addr.formattedAddress || null,
    lat,
    lon,
    online: loc.type === "ONLINE",
    image: imageUrl(e.mainImage),
    url:
      e.eventPageUrl ||
      (slug ? `${SITE_URL}/event-details/${slug}` : `${SITE_URL}/turer`),
    registrationType: reg.type || null,
    registrationOpen: reg.status
      ? reg.status === "OPEN_TICKETS" || reg.status === "OPEN_RSVP"
      : null,
    price: lowest ? Number(lowest.amount ?? lowest.value ?? 0) : null,
    currency: lowest ? lowest.currency || "NOK" : null,
    soldOut: ticketing.soldOut === true,
  };
}

/** Henter fra Wix og skriver til config/events. Feiler Wix, beholdes
 *  forrige innhold, og kun `lastError` oppdateres. */
async function refresh() {
  const ref = admin.firestore().doc(EVENTS_DOC);
  try {
    const events = await fetchFromWix(WIX_API_KEY.value(), WIX_SITE_ID.value());
    await ref.set({
      events,
      fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
      fetchedAtIso: new Date().toISOString(),
      lastError: null,
    });
    logger.info(`Turkalender oppdatert: ${events.length} arrangementer`);
    return events.length;
  } catch (err) {
    logger.error("Kunne ikke hente turkalenderen fra Wix", err);
    await ref.set(
      { lastError: String(err && err.message ? err.message : err) },
      { merge: true },
    );
    throw err;
  }
}

exports.refreshEvents = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Europe/Oslo",
    secrets: [WIX_API_KEY],
    timeoutSeconds: 60,
    memory: "256MiB",
    retryCount: 1,
  },
  async () => {
    await refresh();
  },
);

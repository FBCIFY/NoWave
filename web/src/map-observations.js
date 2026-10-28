export const observationPageSize = 50;
const categories = new Set(["obstruction", "marine_animal", "pollution"]);
// The public feed is global and newest first; moving the map never filters it.
export function observationsUrl({ category, query, cursor } = {}) {
  const params = new URLSearchParams();
  if (categories.has(category)) params.set("category", category);
  if (query?.trim()) params.set("q", query.trim().slice(0, 120));
  params.set("limit", String(observationPageSize));
  if (cursor) params.set("cursor", cursor);
  return `/api/v1/map/observations?${params}`;
}

export function normalizeObservation(item, now = Date.now()) {
  if (
    !item ||
    !["string", "number"].includes(typeof item.id) ||
    !categories.has(item.category) ||
    !Number.isFinite(item.longitude) ||
    Math.abs(item.longitude) > 180 ||
    !Number.isFinite(item.latitude) ||
    Math.abs(item.latitude) > 90 ||
    !Number.isFinite(Date.parse(item.observed_at)) ||
    !(Date.parse(item.expires_at) > now)
  )
    return null;
  return {
    id: String(item.id),
    category: item.category,
    location: [item.longitude, item.latitude],
    observedAt: item.observed_at,
    expiresAt: Date.parse(item.expires_at),
    description: typeof item.description === "string" ? item.description : "",
    author:
      typeof item.author_username === "string" ? item.author_username : "",
  };
}

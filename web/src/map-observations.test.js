import test from "node:test";
import assert from "node:assert/strict";
import { normalizeObservation, observationsUrl } from "./map-observations.js";

test("public feed stays global and requests only one bounded page", () => {
  const url = new URL(observationsUrl(), "https://nowave.test");
  assert.equal(url.searchParams.get("limit"), "50");
  for (const edge of ["west", "south", "east", "north"])
    assert.equal(url.searchParams.has(edge), false);
});
test("observation query encodes bounded filters and opaque pagination", () => {
  const url = new URL(
    observationsUrl({
      category: "pollution",
      query: " Léa & mer ",
      cursor: "a+b/c=",
    }),
    "https://nowave.test",
  );
  assert.equal(url.pathname, "/api/v1/map/observations");
  assert.equal(url.searchParams.get("q"), "Léa & mer");
  assert.equal(url.searchParams.get("category"), "pollution");
  assert.equal(url.searchParams.get("cursor"), "a+b/c=");
  assert.equal(url.searchParams.get("limit"), "50");
  const limited = new URL(
    observationsUrl({ query: "x".repeat(300), category: "private" }),
    "https://nowave.test",
  );
  assert.equal(limited.searchParams.get("q").length, 120);
  assert.equal(limited.searchParams.has("category"), false);
});
test("only valid, unexpired observations enter public markers without private fields", () => {
  const now = Date.parse("2026-10-26T12:00:00Z");
  const item = {
    id: 12,
    category: "marine_animal",
    longitude: -28.7,
    latitude: 38.33,
    observed_at: "2026-10-26T11:00:00Z",
    expires_at: "2026-10-26T13:00:00Z",
    author_username: "Léa",
    email: "private@example.test",
    description: "Baleine au large",
  };
  const report = normalizeObservation(item, now);
  assert.equal(report.id, "12");
  assert.deepEqual(report.location, [-28.7, 38.33]);
  assert.equal(report.author, "Léa");
  assert.equal("email" in report, false);
  assert.equal(
    normalizeObservation({ ...item, expires_at: "2026-10-26T12:00:00Z" }, now),
    null,
  );
  assert.equal(normalizeObservation({ ...item, latitude: 100 }, now), null);
  assert.equal(
    normalizeObservation({ ...item, category: "private" }, now),
    null,
  );
  const optional = normalizeObservation(
    { ...item, author_username: undefined, description: undefined },
    now,
  );
  assert.equal(optional.author, "");
  assert.equal(optional.description, "");
});

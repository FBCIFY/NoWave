import test from "node:test";
import assert from "node:assert/strict";
import viteConfig from "../vite.config.js";

const config = viteConfig({ mode: "test" });
const match = (url) =>
  Object.keys(config.server.proxy).find((context) =>
    context.startsWith("^")
      ? new RegExp(context).test(url)
      : url.startsWith(context),
  );

test("administration URLs with selection and return parameters reach the backend", () => {
  for (const url of [
    "/admin",
    "/admin?report=00000000-0000-0000-0000-000000000064",
    "/admin?return_to=%2Fadmin%2Freports%3Fpage%3D2",
    "/admin/users?page=2",
    "/admin/reports/123?history_page=2",
  ]) {
    assert.ok(match(url)?.startsWith("^/admin"), url);
  }
});
test("admin assets and the source entry do not become administration pages", () => {
  assert.equal(match("/admin-static/admin.css"), "/admin-static");
  assert.equal(match("/admin-map.js"), undefined);
  assert.equal(match("/administrator"), undefined);
});

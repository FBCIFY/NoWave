const test = require("node:test");
const assert = require("node:assert/strict");
const {
  safePath,
  parentPath,
  childPath,
} = require("../../app/web/static/admin-navigation.js");
const origin = "https://nowave.test";
test("returns unwind action, selected report and paginated moderation list one level at a time", () => {
  const list = "/admin/reports?page=3&limit=20";
  const report = childPath(
    "/admin/reports/11111111-1111-1111-1111-111111111111",
    list,
    origin,
  );
  const action = childPath(
    "/admin/actions/reports/11111111-1111-1111-1111-111111111111/remove",
    report,
    origin,
  );
  assert.equal(parentPath(action, origin), report);
  assert.equal(parentPath(parentPath(action, origin), origin), list);
});
test("a selected map point remains the return destination through report history and cancellation", () => {
  const map = "/admin?report=11111111-1111-1111-1111-111111111111";
  const detail = childPath(
    "/admin/reports/11111111-1111-1111-1111-111111111111#report-history",
    map,
    origin,
  );
  const next = childPath(
    "/admin/reports/11111111-1111-1111-1111-111111111111?history_page=2#report-history",
    detail,
    origin,
    true,
  );
  assert.equal(parentPath(next, origin), map);
  const action = childPath(
    "/admin/actions/reports/11111111-1111-1111-1111-111111111111/remove",
    next,
    origin,
  );
  assert.equal(parentPath(action, origin), next);
});
test("pagination does not add artificial levels to the return stack", () => {
  const users = childPath("/admin/users", "/admin", origin);
  const page2 = childPath("/admin/users?page=2&limit=20", users, origin, true);
  const page3 = childPath("/admin/users?page=3&limit=20", page2, origin, true);
  assert.equal(parentPath(page3, origin), "/admin");
});
test("return links reject external URLs, credentials, scripts and authentication endpoints", () => {
  for (const path of [
    "https://evil.test/admin",
    "//evil.test/admin",
    "javascript:alert(1)",
    "https://user:pass@nowave.test/admin",
    "/admin/login",
    "/admin/logout",
    "/admin/data/users",
    "/administrator",
    "/admin/../login",
  ])
    assert.equal(safePath(path, origin), null, path);
  assert.equal(
    parentPath(
      "/admin/reports?return_to=https%3A%2F%2Fevil.test%2Fadmin",
      origin,
    ),
    null,
  );
  assert.equal(parentPath("/admin/reports", origin), null);
});

test("main menus reset the navigation context while detail links preserve it", () => {
  const vm = require("node:vm");
  const fs = require("node:fs");
  const handlers = {};
  const current = "/admin/users?return_to=%2Fadmin%2Freports%3Fpage%3D3";
  const context = {
    URL,
    location: { origin, href: origin + current },
    document: {
      addEventListener: (name, handler) => { handlers[name] = handler; },
      querySelectorAll: () => [],
    },
    window: { addEventListener() {} },
  };
  vm.runInNewContext(fs.readFileSync(require.resolve("../../app/web/static/admin-navigation.js"), "utf8"), context);
  function click(href, header) {
    const link = {
      href,
      hasAttribute: () => false,
      classList: { contains: () => false },
      closest: (selector) => selector === ".admin-header" && header ? {} : null,
    };
    handlers.click({ button: 0, target: { closest: () => link } });
    return link.href;
  }
  assert.equal(click("/admin/reports", true), "/admin/reports");
  assert.equal(click("/admin", true), "/admin");
  const action = click("/admin/actions/users/123/suspend", false);
  assert.equal(parentPath(action, origin), current);
});

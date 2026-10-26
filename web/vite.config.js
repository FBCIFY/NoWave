import { defineConfig, loadEnv } from "vite";
import { fileURLToPath } from "node:url";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "NOWAVE_");
  const target = env.NOWAVE_API_URL || "http://127.0.0.1:8000";
  const proxy = Object.fromEntries(
    ["/api", "/admin-static", "/admin"].map((path) => [
      path === "/admin" ? "^/admin(?:/|$)" : path,
      { target, changeOrigin: true, headers: { "x-nowave-web-dev": "1" } },
    ]),
  );
  return {
    build: {
      cssCodeSplit: false,
      rollupOptions: {
        input: {
          index: fileURLToPath(new URL("./index.html", import.meta.url)),
          "admin-map": fileURLToPath(
            new URL("./admin-map.js", import.meta.url),
          ),
        },
        output: {
          entryFileNames: (chunk) =>
            chunk.name === "admin-map"
              ? "assets/admin-map.js"
              : "assets/[name]-[hash].js",
          assetFileNames: (asset) =>
            asset.name?.endsWith(".css")
              ? "assets/nowave.css"
              : "assets/[name]-[hash][extname]",
        },
      },
    },
    server: { proxy },
    preview: { proxy },
  };
});

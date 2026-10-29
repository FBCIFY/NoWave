import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const port = Number(process.env.NOWAVE_LOCAL_PORT || 4173);
if (!Number.isInteger(port) || port < 1024 || port > 65535) {
  throw new Error("NOWAVE_LOCAL_PORT doit être un port entre 1024 et 65535.");
}
const url = `http://127.0.0.1:${port}/`;
let running = false;
try {
  const response = await fetch(url, { signal: AbortSignal.timeout(1200) });
  running = (await response.text()).includes(
    "<title>NoWave — Le large, autrement.</title>",
  );
  if (!running)
    throw new Error(
      `Le port ${port} est utilisé par un autre service. Choisissez NOWAVE_LOCAL_PORT.`,
    );
} catch (error) {
  if (error.message.includes("autre service")) throw error;
}
if (running) {
  console.log(`NoWave est déjà lancé : ${url}`);
  if (process.env.BROWSER !== "none" && process.platform === "darwin") {
    const browser = spawn("open", [url], { stdio: "ignore" });
    browser.on("error", () =>
      console.log(`Ouvrez ${url} dans votre navigateur.`),
    );
  }
} else {
  const cli = fileURLToPath(
    new URL("../node_modules/vite/bin/vite.js", import.meta.url),
  );
  const server = spawn(
    process.execPath,
    [
      cli,
      "preview",
      "--host",
      "127.0.0.1",
      "--port",
      String(port),
      "--strictPort",
      "--open",
    ],
    { stdio: "inherit" },
  );
  for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"])
    process.on(signal, () => server.kill(signal));
  server.on("error", (error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
  server.on("exit", (code, signal) => process.exit(code ?? (signal ? 130 : 0)));
}

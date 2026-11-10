import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const port = 5173;
const rendererUrl = `http://127.0.0.1:${port}`;

async function rendererReady() {
  try {
    const response = await fetch(rendererUrl, { redirect: "manual" });
    return response.status < 500;
  } catch {
    return false;
  }
}

function wait(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

let viteProcess = null;

if (!(await rendererReady())) {
  const npmCommand = process.platform === "win32" ? "npm.cmd" : "npm";
  viteProcess = spawn(
    npmCommand,
    ["run", "dev", "--", "--host", "127.0.0.1", "--port", String(port), "--strictPort"],
    { cwd: root, stdio: "inherit" },
  );

  const startedAt = Date.now();
  while (!(await rendererReady())) {
    if (viteProcess.exitCode !== null) {
      console.error("Vite 启动失败，桌面应用未能打开。");
      process.exit(viteProcess.exitCode || 1);
    }
    if (Date.now() - startedAt > 30000) {
      console.error("等待 Vite 超时，桌面应用未能打开。");
      viteProcess.kill();
      process.exit(1);
    }
    await wait(300);
  }
}

const electronBinary = require("electron");
const desktopProcess = spawn(electronBinary, ["."], {
  cwd: root,
  stdio: "inherit",
  env: {
    ...process.env,
    ELECTRON_DEV: "1",
    ELECTRON_RENDERER_URL: rendererUrl,
  },
});

function stop(code = 0) {
  if (viteProcess && viteProcess.exitCode === null) viteProcess.kill();
  if (desktopProcess.exitCode === null) desktopProcess.kill();
  process.exit(code);
}

desktopProcess.on("exit", (code) => stop(code ?? 0));
process.on("SIGINT", () => stop(0));
process.on("SIGTERM", () => stop(0));

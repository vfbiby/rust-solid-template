import { defineConfig } from "@playwright/test";
import fs from "node:fs";
import { fileURLToPath } from "node:url";

// baseURL 解析链：E2E_BASE_URL 显式指定 → 仓库根 .dev/env.sh（dev.sh 落盘）→
// undefined（spec 的 beforeAll 探活会以可见 skip 收场，绝不静默变绿）。
function resolveBaseUrl(): string | undefined {
  const explicit = process.env.E2E_BASE_URL;
  if (explicit) return explicit;
  const envFile = fileURLToPath(new URL("../../.dev/env.sh", import.meta.url));
  if (!fs.existsSync(envFile)) return undefined;
  const line = fs
    .readFileSync(envFile, "utf8")
    .split("\n")
    .find((l) => l.startsWith("export E2E_BASE_URL="));
  if (!line) return undefined;
  return line.slice("export E2E_BASE_URL=".length).trim();
}

export default defineConfig({
  testDir: ".",
  outputDir: "../test-results",
  timeout: 30_000,
  workers: 1,
  retries: 0,
  use: {
    baseURL: resolveBaseUrl(),
    viewport: { width: 1280, height: 800 },
    // Playwright 的 apiRequestContext 不读 shell 代理；显式给了 E2E_PROXY 时
    // bypass 必须带 .localhost，否则本地 e2e 全线挂且症状与「服务没起」一样。
    proxy: process.env.E2E_PROXY
      ? {
          server: process.env.E2E_PROXY,
          bypass: "127.0.0.1,localhost,::1,.localhost",
        }
      : undefined,
    trace: "retain-on-failure",
  },
  reporter: [["list"]],
});

import { defineConfig } from "vitest/config";
import solid from "vite-plugin-solid";

// 端口单一来源是 dev.sh（写进 .dev/env.sh）；这里给同款缺省是为了脱离脚本直接
// `bun run dev` 也能起。strictPort：被占就报错退出，绝不静默漂移。
// /api 代理直连后端回环端口（changeOrigin 改写 Host）——绝不 target .localhost，
// 那会经 portless 绕回自己（路由环 508）。
export default defineConfig({
  plugins: [solid()],
  server: {
    host: "127.0.0.1",
    port: parseInt(process.env.UI_DEV_PORT ?? "5173", 10),
    strictPort: true,
    proxy: {
      "/api": {
        target: `http://127.0.0.1:${process.env.BACKEND_PORT ?? "3000"}`,
        changeOrigin: true,
      },
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["tests/setup.ts"],
    include: ["src/**/*.test.{ts,tsx}"],
  },
});

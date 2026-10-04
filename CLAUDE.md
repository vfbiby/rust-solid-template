# rsts

## 常用命令

- 本地整栈：`./dev.sh start`（幂等）／`./dev.sh stop`／`./dev.sh status`／`./dev.sh logs [backend|frontend]`
- URL 一律取 `.dev/env.sh`（`DEV_URL` / `API_URL` / `E2E_BASE_URL`），不要自己拼端口
- 后端测试：`scripts/cargo-test.sh [cargo test args]`（会清 pid 已死的遗留测试库）
- 全量验收：`scripts/acceptance.sh`（fmt / clippy / 后端测试 / 前端 typecheck+vitest / e2e 可选门）
- e2e：dev 栈起后 `cd web && bun run test:e2e`

## 硬规矩

- **禁按端口/进程名杀进程**（`lsof -ti :port`、`pkill -f vite`）：多 worktree 并行时是事故源。只按 `.dev/*.pid` 杀，杀前校验进程名。
- **禁写死端口**：端口是 dev.sh 动态分配的实现细节；测试与脚本认 env 接缝（`RSTS_TEST_PG_URL`、`E2E_BASE_URL`）。
- 起名只有两处：`scripts/lib.sh` 的 `APP_NAME`、`crates/server/tests/common/mod.rs` 的 `const APP`。改名清单见 README。

# rust-solid-template

Rust(axum + sqlx + Postgres) 后端 + SolidJS(Vite + bun) 前端的通用起步模板。
端口是动态分配的实现细节，域名/env 接缝是接口；多个 git worktree 可同时各跑一套完整栈。

## 前置依赖

- rustup stable、[bun](https://bun.sh)
- 本机 Postgres（`brew install postgresql@16 && brew services start postgresql@16`），
  默认连 `postgres://postgres@127.0.0.1:5433/postgres`，角色需 CREATEDB
- `psql` 与 `python3` 在 PATH
- e2e 浏览器（首次）：`cd web && bunx playwright install`

## 快速开始

```sh
./dev.sh start        # 起后端 + 前端 + 开发库，打印访问 URL，落盘 .dev/env.sh
./dev.sh stop
./dev.sh status
./dev.sh logs backend # 或 frontend
PLAIN=1 ./dev.sh start  # 装了 portless 也按传统 http://127.0.0.1:<port> 起
```

后端测试与验收：

```sh
scripts/cargo-test.sh          # 后端测试（前后自动清 pid 已死的遗留测试库）
scripts/acceptance.sh          # fmt / clippy / 后端测试 / 前端 / e2e（栈没起则可见跳过）
```

## portless（可选）

装了 [portless](https://github.com/vercel-labs/portless) 就得到
`http://<app>.localhost:<proxy端口>` 命名域名（`./dev.sh start` 会自动拉起它的
代理守护并注册路由，URL 以 `portless get` 给的为准）；没装则自动回退
`http://127.0.0.1:<port>`，代码零改动。

```sh
npm i -g portless        # 或 bun add -g portless
portless proxy start --https   # 可选：HTTPS/2 模式（生成 CA，首次 portless trust 信任）
portless hosts sync      # Safari 还需要这个；Chrome/curl 直接受 .localhost
```

**无端口的干净 URL**（`http://<app>.localhost`，不带 `:1355`）：用管理员单独把代理
起在默认端口即可，dev.sh 会自动适配并省略端口号：

```sh
sudo portless proxy start -p 80        # 或 sudo portless proxy start --https -p 443
```

注意：管理员身份只用于这一次代理启动；`./dev.sh` 本身永远不要用 root 跑
（会拒绝执行——进程和 pid 文件归 root 后，非 root 的 stop 收不掉）。

**已知坑：走 portless 域名的每个请求多 10–50ms**（实测直连 vite ~2ms，走域名
10–55ms 波动）——portless 的代理 socket 没关 Nagle（源码零处 `setNoDelay`），
是它自己的实现问题，生产 nginx 不受影响。交互调试嫌慢就用 `.dev/env.sh` 里的
`DEV_URL_DIRECT` / `API_URL_DIRECT`（回环直连，绕过代理）。

## worktree 并行

```sh
git worktree add ../rsts-wt-1 -b feature-x
cd ../rsts-wt-1 && ./dev.sh start
```

每个 worktree 有独立域名（`<分支名>.<app>.localhost`）、独立端口、独立开发库
（`<app>_<分支slug>`）；`./dev.sh stop` 只杀自己 pid 文件里的进程。分支名经
sanitize（小写、非法字符折 `-`、截 20 字符）后可能撞名——撞了 `--force` 会顶掉
对方的域名注册，起分支名时避开即可。

## 起名

默认名叫 `rsts`，改成你的项目名只有两处（外加可选的展示名）：

1. `scripts/lib.sh` 的 `APP_NAME` —— 域名、库名、env 变量前缀（`RSTS_*`）都从它派生
2. `crates/server/tests/common/mod.rs` 的 `const APP` —— Rust 侧测试库名前缀
3. 可选展示名：`web/package.json` 的 `name`、`web/index.html` 的 `<title>`

改完 `grep -ri rsts --exclude-dir=target --exclude-dir=node_modules` 应只剩 README/CLAUDE.md。

## CI

CI 不起整栈，只跑门 1–4；Postgres 用 service container，把 `<APP>_TEST_PG_URL` 指过去即可：

```yaml
services:
  postgres:
    image: postgres:16
    env: { POSTGRES_USER: postgres, POSTGRES_HOST_AUTH_METHOD: trust }
    ports: ["5433:5432"]
    options: >-
      --health-cmd pg_isready --health-interval 5s --health-timeout 5s --health-retries 10
steps:
  - run: scripts/cargo-test.sh --workspace
    env: { RSTS_TEST_PG_URL: "postgres://postgres@127.0.0.1:5433/postgres" }
  - run: cargo fmt --all --check
  - run: cargo clippy --workspace --all-targets -- -D warnings
  - run: bun install && bun run typecheck && bun run test
    working-directory: web
```

## 技术备注

- SQL 用非宏 API（`sqlx::query`）：clone 即编过，不需要 sqlx-cli / `cargo sqlx prepare`。
  想上 `query!` 编译期校验，需要 CI 先起 Postgres 或提交 `.sqlx` 缓存。
- vite / vite-plugin-solid / vitest 大版本联动紧，锁在 bun.lock 里，别单独升级。
- 前端 API 一律相对路径 `/api/...`（同源，vite proxy 直连后端回环端口）。开发期零 CORS。
- 每个 worktree 有独立 `target/`（重复编译换隔离）；要省磁盘可自设 `CARGO_TARGET_DIR`。

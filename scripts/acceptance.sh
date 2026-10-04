#!/usr/bin/env bash
# 本地全量验收门。任一门失败不中断，最后统一裁决。
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "不在仓库里"; exit 1; }
cd "$ROOT"

fail=0
gate() {
  local name="$1"
  shift
  echo "=== 门：$name ==="
  if "$@"; then
    echo "--- $name 通过"
  else
    echo "--- $name 失败"
    fail=1
  fi
}

# workspace 清单在 web/ 下（后端 crate 是 web/api），cargo 系列都在 web/ 里跑。
gate fmt bash -c 'cd web && cargo fmt --all --check'
gate clippy bash -c 'cd web && cargo clippy --workspace --all-targets -- -D warnings'
gate 后端测试 "$ROOT/scripts/cargo-test.sh" --no-fail-fast
gate 前端 bash -c 'cd web && bun run typecheck && bun run test'

echo "=== 门：e2e（可选） ==="
if [ -f .dev/env.sh ] \
  && source .dev/env.sh \
  && curl -sf "http://127.0.0.1:$BACKEND_PORT/health" >/dev/null 2>&1; then
  if (cd web && bun run test:e2e); then
    echo "--- e2e 通过"
  else
    echo "--- e2e 失败"
    fail=1
  fi
else
  echo "--- 跳过：dev 栈未起（./dev.sh start 后重跑本脚本可覆盖此门）"
fi

if [ "$fail" = 0 ]; then
  echo "✅ 全部通过"
else
  echo "❌ 有门失败"
fi
exit "$fail"

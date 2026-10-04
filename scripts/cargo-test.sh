#!/usr/bin/env bash
# 跑后端测试，并在前后清掉「库名里的 pid 已退出」的遗留测试库。
# 测试基座运行期只建库不删库（DROP DATABASE 会触发强制检查点，让所有并行测试
# 互等），删库集中在这里；按 pid 存活判定，多 worktree/多会话并发跑测试互不误删。
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "不在仓库里"; exit 1; }
cd "$ROOT"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

APP_UC="$(app_uc)"
TEST_PG_URL_VAR="${APP_UC}_TEST_PG_URL"
PG_URL="${!TEST_PG_URL_VAR:-$DEFAULT_PG_URL}"

command -v psql >/dev/null 2>&1 || { echo "找不到 psql（brew install libpq 或 postgresql@16）"; exit 1; }

cleanup() {
  local rows name pid
  rows="$(psql -X -At -v ON_ERROR_STOP=1 -d "$PG_URL" \
    -c "select datname from pg_database where datname like '${APP_NAME}_test_%' or datname like '${APP_NAME}_template_%'")" \
    || { echo "连不上测试 Postgres（${PG_URL}），无法清库"; return 1; }
  local dead=()
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    [[ "$name" =~ ^${APP_NAME}_(test|template)_([0-9]+)_ ]] || continue
    pid="${BASH_REMATCH[2]}"
    ps -p "$pid" >/dev/null 2>&1 || dead+=("$name")
  done <<< "$rows"
  [ "${#dead[@]}" -eq 0 ] && return 0
  echo "清理遗留测试库（pid 已退出）：${dead[*]}"
  for name in "${dead[@]}"; do
    psql -X -q -v ON_ERROR_STOP=1 -d "$PG_URL" -c "drop database if exists \"$name\" with (force)"
  done
}

cleanup || exit 1
trap cleanup EXIT

# workspace 清单在 web/ 下（后端 crate 是 web/api）。
cd "$ROOT/web"
cargo test "$@"

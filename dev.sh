#!/usr/bin/env bash
# dev.sh —— 本地整栈（后端 + 前端 + 开发库）的启停。端口是动态分配的实现细节，
# 所有消费者只认 .dev/env.sh 里的 URL。多个 git worktree 可同时各跑一套，互不干扰：
# 进程只按 pid 文件杀，绝不按端口/进程名杀；域名与库名带 worktree slug。
#
# 用法：./dev.sh start | stop | status | logs [backend|frontend]
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "不在仓库里"; exit 1; }
cd "$ROOT"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

DEV_DIR="$ROOT/.dev"
LOG_DIR="$ROOT/logs"
BACKEND_PID_FILE="$DEV_DIR/backend.pid"
FRONTEND_PID_FILE="$DEV_DIR/frontend.pid"

slug="$(compute_slug)"
host="$APP_NAME"
[ -n "$slug" ] && host="${slug}.${APP_NAME}"
api_host="api.${host}"

# 探活一律走数字回环：.localhost 可能被系统代理截走，NO_PROXY 对后缀匹配各实现不一。
export NO_PROXY="127.0.0.1,localhost,::1,.localhost"
export no_proxy="$NO_PROXY"

pid_alive() {
  [ -f "$1" ] && kill -0 "$(cat "$1" 2>/dev/null)" 2>/dev/null
}

expect_process_name() {
  # 防陈旧 pid 复用：pid 文件里的号换了个不相干进程时不许杀。
  local comm
  comm="$(ps -p "$1" -o comm= 2>/dev/null | xargs basename 2>/dev/null)"
  case "$comm" in
    server|node|bun|vite*) return 0 ;;
    *) echo "警告：$2 里的 pid $1 现在是 ${comm}，不像我们的进程，不杀"; return 1 ;;
  esac
}

stop_stack() {
  local name file pid
  for name in backend frontend; do
    if [ "$name" = backend ]; then file="$BACKEND_PID_FILE"; else file="$FRONTEND_PID_FILE"; fi
    [ -f "$file" ] || continue
    pid="$(cat "$file" 2>/dev/null)"
    if [ -n "$pid" ] && expect_process_name "$pid" "$file"; then
      pkill -P "$pid" 2>/dev/null
      kill "$pid" 2>/dev/null
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
      done
      kill -0 "$pid" 2>/dev/null && { echo "强杀 $name ($pid)"; kill -9 "$pid" 2>/dev/null; }
    fi
    rm -f "$file"
  done
  if command -v portless >/dev/null 2>&1; then
    portless alias --remove "$host" >/dev/null 2>&1
    portless alias --remove "$api_host" >/dev/null 2>&1
  fi
  rm -f "$DEV_DIR/env.sh"
}

do_start() {
  if [ "$(id -u)" = 0 ]; then
    echo "别用 root 跑 dev.sh：进程和 pid 文件会归 root，之后非 root 的 stop 收不掉。"
    echo "要无端口 URL，管理员只需单独起一次代理：sudo portless proxy start -p 80（或 --https -p 443）"
    exit 1
  fi
  mkdir -p "$DEV_DIR" "$LOG_DIR"

  if pid_alive "$BACKEND_PID_FILE" && pid_alive "$FRONTEND_PID_FILE" && [ -f "$DEV_DIR/env.sh" ]; then
    echo "栈已在跑："; cat "$DEV_DIR/env.sh" | sed 's/^export //'
    exit 0
  fi
  stop_stack >/dev/null 2>&1

  if ! command -v psql >/dev/null 2>&1; then
    echo "找不到 psql（brew install libpq 或 postgresql@16）"; exit 1
  fi

  local i ok=0
  for i in $(seq 1 20); do
    psql -X -At -v ON_ERROR_STOP=1 -d "$DEFAULT_PG_URL" -c 'select 1' >/dev/null 2>&1 && { ok=1; break; }
    sleep 0.5
  done
  [ "$ok" = 1 ] || { echo "Postgres 未就绪（$DEFAULT_PG_URL 连不上）"; exit 1; }

  local db_name
  db_name="$(dev_db_name "$slug")"
  printf '%s' "$db_name" | grep -Eq '^[a-z0-9_]+$' || { echo "库名不合法：$db_name"; exit 1; }
  if ! psql -X -At -d "$DEFAULT_PG_URL" -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'" | grep -q 1; then
    psql -X -q -v ON_ERROR_STOP=1 -d "$DEFAULT_PG_URL" -c "create database \"$db_name\"" || exit 1
  fi
  local admin_url dev_db_url
  admin_url="${DEFAULT_PG_URL%/*}"
  dev_db_url="$admin_url/$db_name"

  local backend_port ui_port
  backend_port="$(free_port)"
  ui_port="$(free_port)"

  local dev_url api_url via="loopback（portless 不可用）"
  if command -v portless >/dev/null 2>&1; then
    # 判活只认 portless 的应答暗号（X-Portless 响应头）——root 起的管理员守护，
    # 非特权 lsof 根本看不见。管理员态（80/443 有暗号）绝不能再 proxy start，
    # 还必须停掉用户态 1355 残活：portless 是单活守护假设 + 双存储（<1024 端口
    # 走系统级 /tmp/portless，否则 ~/.portless），discoverState 永远用户存储优先，
    # 1355 残活会把 alias 路由带去 80 守护看不见的地方。
    local admin_port=""
    if curl -sI --max-time 2 http://127.0.0.1:80/ 2>/dev/null | grep -qi '^x-portless: *1'; then
      admin_port=80
    elif curl -sI -k --max-time 2 https://127.0.0.1:443/ 2>/dev/null | grep -qi '^x-portless: *1'; then
      admin_port=443
    fi
    if [ -n "$admin_port" ]; then
      portless proxy stop >/dev/null 2>&1
    else
      portless proxy start >/dev/null 2>&1
      sleep 1
    fi
    if portless alias "$host" "$ui_port" --force >/dev/null 2>&1 \
      && portless alias "$api_host" "$backend_port" --force >/dev/null 2>&1; then
      local re_host="${host//./\\.}" re_api="${api_host//./\\.}"
      case "$admin_port" in
        80)
          dev_url="http://$host.localhost"
          api_url="http://$api_host.localhost" ;;
        443)
          dev_url="https://$host.localhost"
          api_url="https://$api_host.localhost" ;;
        *)
          dev_url="$(portless list 2>/dev/null | sed -E -n "s|^.*(https?)://(${re_host}\\.localhost)(:[0-9]+)?.*$|\1://\2\3|p" | head -1)"
          api_url="$(portless list 2>/dev/null | sed -E -n "s|^.*(https?)://(${re_api}\\.localhost)(:[0-9]+)?.*$|\1://\2\3|p" | head -1)" ;;
      esac
      # 路由真的落进 list（= 落对存储）才算 portless 接管成功。
      if [ -n "$dev_url" ] && [ -n "$api_url" ] \
        && portless list 2>/dev/null | grep -q "://${re_host}\.localhost"; then
        via="portless"
      fi
    fi
  fi
  if [ -z "${dev_url:-}" ]; then
    dev_url="http://127.0.0.1:$ui_port"
    api_url="http://127.0.0.1:$backend_port"
  fi

  cargo build --quiet || exit 1
  PORT="$backend_port" DATABASE_URL="$dev_db_url" \
    nohup "$ROOT/target/debug/server" >> "$LOG_DIR/backend.log" 2>&1 &
  echo $! > "$BACKEND_PID_FILE"

  if [ ! -d "$ROOT/web/node_modules" ]; then
    echo "前端依赖未装，bun install ..."
    (cd "$ROOT/web" && bun install) || exit 1
  fi
  # 直接调 vite.js 而非 bun run dev：pid 就是 vite server 自己，kill 不留孤儿。
  # 注意 & 必须只作用于 nohup 这一条简单命令——连着 cd 一起后台化的话，
  # $! 记下的是包一层的 bash 壳，stop 的进程名校验会拒杀、vite 泄漏。
  (
    cd "$ROOT/web" || exit 1
    UI_DEV_PORT="$ui_port" BACKEND_PORT="$backend_port" \
      nohup node node_modules/vite/bin/vite.js >> ../logs/frontend.log 2>&1 &
    echo $! > "$FRONTEND_PID_FILE"
  )

  ok=0
  for i in $(seq 1 40); do
    curl -sf "http://127.0.0.1:$backend_port/health" >/dev/null 2>&1 \
      && curl -sf "http://127.0.0.1:$ui_port/" >/dev/null 2>&1 && { ok=1; break; }
    sleep 0.5
  done
  if [ "$ok" != 1 ]; then
    echo "启动失败，日志尾部："
    tail -n 10 "$LOG_DIR/backend.log" "$LOG_DIR/frontend.log"
    stop_stack >/dev/null 2>&1
    exit 1
  fi

  cat > "$DEV_DIR/env.sh" <<EOF
export BACKEND_PORT=$backend_port
export UI_PORT=$ui_port
export DEV_DATABASE_URL=$dev_db_url
export DEV_URL=$dev_url
export API_URL=$api_url
export E2E_BASE_URL=$dev_url
EOF

  echo "✅ 就绪（${via}）"
  echo "   前端  $dev_url"
  echo "   API   $api_url"
  echo "   库    $dev_db_url"
  echo "   日志  logs/ ｜ 停止  ./dev.sh stop"
}

do_status() {
  local name file pid state
  for name in backend frontend; do
    if [ "$name" = backend ]; then file="$BACKEND_PID_FILE"; else file="$FRONTEND_PID_FILE"; fi
    if pid_alive "$file"; then
      state="活着 (pid $(cat "$file"))"
    elif [ -f "$file" ]; then
      state="pid 文件在但进程死了"
    else
      state="未启动"
    fi
    printf '%-10s %s\n' "$name" "$state"
  done
  if [ -f "$DEV_DIR/env.sh" ]; then
    grep -E 'DEV_URL|API_URL|DEV_DATABASE_URL' "$DEV_DIR/env.sh" | sed 's/^export //'
  fi
}

usage() {
  cat <<'EOF'
用法：./dev.sh <命令>

  start                    起整栈（后端 + 前端 + 开发库），幂等；URL 落盘 .dev/env.sh
  stop                     停整栈（只杀自己 pid 文件里的进程）
  status                   各进程活死 + 当前 URL
  logs [backend|frontend]  跟日志（缺省 backend）

URL 接缝（人和脚本都只认这些，别拼端口）：
  .dev/env.sh 里的 DEV_URL / API_URL / E2E_BASE_URL

portless（可选，命名域名）：
  不装 portless          → 自动回退 http://127.0.0.1:<port>，零改动
  portless proxy start   → 普通模式，URL 形如 http://<app>.localhost:1355
  无端口的干净 URL（http://<app>.localhost）需要管理员起一次代理（80/443 要特权）：
      sudo portless proxy stop           # 若之前有用户态守护，先停
      sudo portless proxy start -p 80    # 或 sudo portless proxy start --https -p 443
  之后 ./dev.sh start 自动适配；dev.sh 本身别用 root 跑（会被拒绝）。

开发库：默认连本机 5433 的 Postgres，主 checkout 用库名 <app>，worktree 用 <app>_<分支slug>。
EOF
}

if [ $# -eq 0 ]; then
  usage
  exit 0
fi

case "$1" in
  start) do_start ;;
  stop) stop_stack; echo "已停止。" ;;
  status) do_status ;;
  logs) tail -n 100 -f "$LOG_DIR/${2:-backend}.log" ;;
  *) usage; exit 1 ;;
esac

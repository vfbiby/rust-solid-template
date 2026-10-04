# 各脚本共用的起名与派生：APP_NAME 是全仓唯一起名点，域名、库名、env 变量前缀都从它派生。
# 改名清单见 README「起名」一节。
APP_NAME="rsts"

DEFAULT_PG_URL="postgres://postgres@127.0.0.1:5433/postgres"

app_uc() {
  printf '%s' "$APP_NAME" | tr 'a-z' 'A-Z'
}

# linked worktree 返回分支名（sanitize 后），主 checkout 返回空。
compute_slug() {
  local gitdir branch
  gitdir="$(git rev-parse --git-dir)" || return 1
  [ "$gitdir" = ".git" ] && return 0
  branch="$(git branch --show-current)"
  [ -z "$branch" ] && branch="$(git rev-parse --short HEAD)"
  printf '%s' "$branch" \
    | tr 'A-Z' 'a-z' \
    | sed 's/[^a-z0-9-]/-/g; s/-\{2,\}/-/g; s/^-\{1,\}//; s/-$//' \
    | cut -c1-20
}

free_port() {
  python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

# 本机 dev 库：主 checkout 用 <app>，worktree 用 <app>_<slug>。
# 库名把域名 slug 里的 - 折成 _（PG 标识符不带引号不容 -）。
dev_db_name() {
  local slug="$1"
  if [ -n "$slug" ]; then
    printf '%s_%s' "$APP_NAME" "${slug//-/_}"
  else
    printf '%s' "$APP_NAME"
  fi
}

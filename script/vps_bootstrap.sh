#!/bin/bash
# VPS 初期ブートストラップ（Phase 2）
#
# 実行方法（VPS 上で管理者が実行）:
#   sudo bash script/vps_bootstrap.sh
#
# 変更なしで手順だけ確認する場合:
#   sudo DRY_RUN=1 bash script/vps_bootstrap.sh
#
# 前提:
# - Ubuntu 26.04 LTS のさくら VPS（root 権限で実行すること）
# - 何度実行しても同じ状態になる（冪等）。既に済みの手順は skip と表示する
# - 既存の UFW ルールは削除しない。`ufw reset` / `ufw delete` / flush は使わない
# - SSH 締め出し防止を最優先にする（手順 f のガードを参照）
#
# 関連: Issue #99、documents/plans/20261027.md（指示書）、
#       documents/plans/20261027-phase1.md（Phase 1 調査）、
#       documents/plans/20261028-vps-phase2.md（本スクリプトの手順書）

set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
SWAPFILE="/swapfile"
SWAP_SIZE_MB=2048

log() {
  echo "[bootstrap] $*"
}

skip() {
  echo "[bootstrap] skip: $*"
}

# 実際に状態を変えるコマンドはこの経路でのみ実行する。
# DRY_RUN=1 のときは実行せず、実行するはずだった内容を表示する。
run() {
  if [ "${DRY_RUN}" = "1" ]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# --- 0. root 権限の確認（DRY_RUN でも必ず止める） ---
# sudo なしでの実行は、途中で権限不足のエラーになるより先に、
# 正しい実行方法を示して終了する。
if [ "$(id -u)" -ne 0 ]; then
  echo "[bootstrap] エラー: root 権限が必要です。VPS 上で次を実行してください:" >&2
  echo "  sudo bash script/vps_bootstrap.sh" >&2
  exit 1
fi

if [ "${DRY_RUN}" = "1" ]; then
  log "DRY_RUN モード: 変更は行わず、実行する手順を表示します"
fi

# --- a. 前提確認（読み取りのみ。変更しない） ---
log "=== [a] 前提確認 ==="
log "OS: $(cat /etc/os-release | grep -E '^(NAME|VERSION)=' | tr '\n' ' ')"
log "カーネル: $(uname -r) / CPU: $(nproc) vCPU"
run_df_free() {
  df -h / | tail -1
  free -m
}
if [ "${DRY_RUN}" = "1" ]; then
  echo "[DRY-RUN] df -h / と free -m を表示（読み取りのみ）"
else
  run_df_free
fi

# --- b. スワップ 2GB 作成（冪等） ---
log "=== [b] スワップ (${SWAP_SIZE_MB}MB) ==="
if swapon --show=NAME --noheadings 2>/dev/null | grep -qx "${SWAPFILE}"; then
  skip "${SWAPFILE} は既に有効なスワップです"
elif [ "${DRY_RUN}" = "1" ]; then
  echo "[DRY-RUN] fallocate -l ${SWAP_SIZE_MB}M ${SWAPFILE}（失敗時は dd に切替）"
  echo "[DRY-RUN] chmod 600 ${SWAPFILE} && mkswap ${SWAPFILE} && swapon ${SWAPFILE}"
  echo "[DRY-RUN] /etc/fstab に '${SWAPFILE} none swap sw 0 0' を追記（既存行がなければ）"
else
  if [ -e "${SWAPFILE}" ]; then
    # 既存ファイルがあるがスワップとして有効でない場合は作り直さず停止する。
    # 勝手に消すとデータを失う恐れがあるため、管理者の判断を求める。
    echo "[bootstrap] エラー: ${SWAPFILE} が存在しますがスワップとして有効ではありません。" >&2
    echo "[bootstrap] 内容を確認のうえ、手動で対処してください（swapon / 削除など）。" >&2
    exit 1
  fi
  if ! fallocate -l "${SWAP_SIZE_MB}M" "${SWAPFILE}" 2>/dev/null; then
    log "fallocate が使えないため dd で作成します"
    dd if=/dev/zero of="${SWAPFILE}" bs=1M count="${SWAP_SIZE_MB}" status=progress
  fi
  chmod 600 "${SWAPFILE}"
  mkswap "${SWAPFILE}"
  swapon "${SWAPFILE}"
  if grep -qs "^${SWAPFILE}[[:space:]]" /etc/fstab; then
    skip "/etc/fstab に ${SWAPFILE} の行は既にあります"
  else
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
    log "/etc/fstab に ${SWAPFILE} を追記しました"
  fi
fi

# --- c. OS 更新 ---
log "=== [c] apt update / upgrade ==="
export DEBIAN_FRONTEND=noninteractive
run apt-get update
run apt-get upgrade -y

# --- d. 必要パッケージ（不足分のみ導入） ---
log "=== [d] 必要パッケージ ==="
for pkg in ca-certificates curl gnupg ufw git; do
  if dpkg -s "${pkg}" >/dev/null 2>&1; then
    skip "${pkg} は導入済みです"
  else
    run apt-get install -y "${pkg}"
  fi
done

# --- e. Docker 公式リポジトリ + Engine / Compose Plugin（冪等） ---
log "=== [e] Docker 導入 ==="
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  skip "Docker Engine と Compose Plugin は導入済みです（$(docker --version)）"
else
  # shellcheck disable=SC1091
  CODENAME=""
  if [ -r /etc/os-release ]; then
    CODENAME="$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}")"
  fi
  if [ -z "${CODENAME}" ]; then
    if [ "${DRY_RUN}" = "1" ]; then
      CODENAME="<codename>"
    else
      echo "[bootstrap] エラー: /etc/os-release から APT codename を取得できません。" >&2
      exit 1
    fi
  fi
  ARCH="$(dpkg --print-architecture)"
  log "APT codename: ${CODENAME} / arch: ${ARCH}"
  run install -m 0755 -d /etc/apt/keyrings
  if [ -f /etc/apt/keyrings/docker.asc ]; then
    skip "/etc/apt/keyrings/docker.asc は既にあります"
  else
    # パイプを run 経由にすると DRY_RUN 時の表示が崩れるため分岐する。
    if [ "${DRY_RUN}" = "1" ]; then
      echo "[DRY-RUN] curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
    else
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    fi
    run chmod a+r /etc/apt/keyrings/docker.asc
  fi
  if [ -f /etc/apt/sources.list.d/docker.sources ] || grep -rq "download.docker.com" /etc/apt/sources.list.d/ 2>/dev/null; then
    skip "Docker の APT リポジトリ設定は既にあります"
  else
    if [ "${DRY_RUN}" = "1" ]; then
      echo "[DRY-RUN] /etc/apt/sources.list.d/docker.sources に signed-by 付きリポジトリを登録"
    else
      cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    fi
  fi
  run apt-get update
  run apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# --- f. UFW（既存ルールは消さない。SSH 保護が最優先） ---
log "=== [f] UFW ==="
# 指定ポートの ALLOW ルールが登録済みかを判定する。
# UFW が無効なときは `ufw status` にルールが出ないため `ufw show added` も見る。
ufw_rule_allowed() {
  local port="$1"
  ufw status 2>/dev/null | grep -qE "${port}/tcp.*ALLOW" && return 0
  ufw show added 2>/dev/null | grep -qE "ufw allow ${port}/tcp" && return 0
  return 1
}

allow_if_missing() {
  # $1: ポート番号。既に ALLOW ルールがあれば追加しない（重複防止）。
  local port="$1"
  if ufw_rule_allowed "${port}"; then
    skip "${port}/tcp の ALLOW ルールは既にあります"
  else
    run ufw allow "${port}/tcp"
  fi
}

if [ "${DRY_RUN}" = "1" ]; then
  echo "[DRY-RUN] ufw allow 22/tcp（SSH を最初に許可。既存ルールがあれば skip）"
  echo "[DRY-RUN] ufw allow 80/tcp / ufw allow 443/tcp（既存ルールがあれば skip）"
  echo "[DRY-RUN] 'ufw status' で 22/tcp の ALLOW を確認できた場合のみ ufw --force enable"
  echo "[DRY-RUN] 22/tcp の ALLOW が確認できなければ中止する"
else
  # SSH を最初に許可する。80/443 より先に行い、この順序を変えないこと。
  allow_if_missing 22
  allow_if_missing 80
  allow_if_missing 443
  # 22 が許可済みであることを確認できなければ enable しない。
  # enable 時のプロンプトで SSH 切断の警告が出ても、22 許可がなければ中止する。
  # 有効化前は `ufw status` にルールが出ないため、登録済みルールで判定する。
  if ufw_rule_allowed 22; then
    log "22/tcp の ALLOW を確認しました"
    if ufw status | grep -q "Status: active"; then
      skip "UFW は既に有効です"
    else
      ufw --force enable
    fi
  else
    echo "[bootstrap] エラー: 22/tcp の ALLOW ルールを確認できませんでした。" >&2
    echo "[bootstrap] SSH 締め出し防止のため UFW の有効化を中止します。" >&2
    echo "[bootstrap] 'ufw status' を確認し、SSH ルールを手動で登録してから再実行してください。" >&2
    exit 1
  fi
fi

# --- g. 検証結果の表示（読み取りのみ。変更しない） ---
log "=== [g] 検証 ==="
if [ "${DRY_RUN}" = "1" ]; then
  echo "[DRY-RUN] docker --version / docker compose version / ufw status / free -m / ss -tln を表示"
else
  docker --version
  docker compose version
  ufw status verbose || ufw status
  free -m
  if command -v ss >/dev/null 2>&1; then
    ss -tln
  else
    echo "[bootstrap] ss コマンドがありません（待受ポートの表示を省略）"
  fi
fi

log "完了しました"

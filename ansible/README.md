# Ansible 構成（本番 VPS の構成管理）

`script/vps_bootstrap.sh` で一度作った VPS（`153.126.189.79`）を、
**冪等に再適用できる形**で管理するための構成。Issue #121 の派生。

対象は 2 つだけ。

| playbook | 責務 | 触るもの |
|---|---|---|
| `playbooks/site.yml` | OS ベースライン | apt、Docker、UFW（22/80/443） |
| `playbooks/app.yml` | アプリの反映 | rsync 転送、`.env`、Caddyfile の 1 行、`compose up`、ヘルス、スモーク |

既存の `script/deploy_production.sh` / `compose.production.yaml` / `Caddyfile` の
**本体は変更しない**。手順をなぞるのではなく、同じ状態に収束させる。

---

## 1. 前提

- controller（手元の Mac）に `ansible-core` があること

  ```bash
  pipx install ansible-core      # 導入済みなら不要
  ansible --version
  ```

- VPS に SSH 鍵で入れること（`ssh ubuntu@153.126.189.79`）。
  `inventory/hosts.yml` に接続情報がある。
- コレクションは不要（`ansible-core` だけで動く。`synchronize` ではなく
  既存の `rsync` を `command` で呼んでいるため）。

---

## 2. 使い方

`ansible/` 直下で実行する。

```bash
cd ansible

# 1) OS ベースライン（まずドライラン）
ansible-playbook playbooks/site.yml --check --diff
ansible-playbook playbooks/site.yml

# 2) アプリ反映（ドメイン未設定 = 現行の HTTP 運用のまま）
ansible-playbook playbooks/app.yml --check --diff
ansible-playbook playbooks/app.yml

# 3) ドメイン確定後（HTTPS 化）
ansible-playbook playbooks/app.yml \
  -e app_domain=example.com -e force_ssl=true
```

リポジトリ直下から実行する場合は設定ファイルを明示する。

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory \
  ansible/playbooks/app.yml
```

### よく使うスイッチ

| 変数 | 既定 | 意味 |
|---|---|---|
| `app_domain` | `""` | 空なら HTTP 運用。FQDN を入れると Caddy が自動 HTTPS |
| `force_ssl` | `false` | Rails の `force_ssl` + Cookie `secure`。**`app_domain` 必須**（誤設定は playbook が拒否） |
| `admin_allowed_ips` | `""` | 管理画面の IP 許可リスト（#120） |
| `app_build` | `true` | `docker compose build web` をやるか |
| `smoke_enabled` | `true` | `script/smoke_check.rb` を回すか |
| `os_upgrade` | `true` | apt の安全な更新をやるか |
| `ufw_enable` | `true` | UFW を触るか |

既定値は `inventory/group_vars/all/vars.yml`。

---

## 3. 秘密情報の扱い

- `inventory/group_vars/all/vault.yml`（**git 管理外**）に `vault_env` を置き、
  `ansible-vault edit` で管理する。テンプレートは `inventory/group_vars/all/vault.example.yml`。
- 平文で置く場合は `--ask-vault-pass` で渡す。
- `vault_env` に書いたキー**だけ**が `.env` に反映される。書いていない
  キーは現行値が残る（`lineinfile` は指定行のみ更新）。
- `.env` は **playbook が新規作成しない**。無ければエラーで止まる
  （秘密の正本を誤って空にしないため）。
- `slurp` と `lineinfile` には `no_log: true` を付けているので、値を
  画面に出さない。

---

> **`--diff` は付けないこと。** `.env` を `lineinfile` で書き換えるため、`--diff` を
> 付けると差分の前後行（DB パスワード等）が画面に出る。差分確認は
> `--check`（diff なし）+ 反映後に `grep -E '^(APP_DOMAIN|FORCE_SSL)=' .env` で行う。

---

## 4. Caddyfile の付け外し（重要）

リポジトリの `Caddyfile` は `http://{$APP_DOMAIN:localhost} {` で HTTP 固定の方針を
維持している。そして `app.yml` の最初のタスクが `rsync --delete` でコードを
転送するので、**転送のたびに VPS の Caddyfile は HTTP 形に戻る**。

そこで `app.yml` は転送の直後に 1 行だけ差し替える。

| `app_domain` | Caddyfile のサイトアドレス行 | 結果 |
|---|---|---|
| `""` | `http://{$APP_DOMAIN:localhost} {` | 現行どおり HTTP |
| `example.com` | `{$APP_DOMAIN:localhost} {` | Caddy が TLS 証明書を自動取得し HTTP→HTTPS に 308 |

`-e app_domain=...` を外して再実行すれば HTTP 形に戻る（冪等）。

---

## 5. 検証（本番未適用）

本番 VPS にはまだ適用していない。以下は手元で実施済み。

```bash
ansible-playbook playbooks/site.yml --syntax-check
ansible-playbook playbooks/app.yml  --syntax-check
ansible-inventory --list
```

本番適用前に確認すべきこと（未実施）:

- `ansible -m ping app` で疎通
- `site.yml --check` で UFW の差分が想定どおり（既存ルールを消さない）こと
- `app.yml --check` で `.env` の差分が `APP_DOMAIN` / `FORCE_SSL` など想定キーだけであること

---

## 6. ドメイン確定後の手順

オーナー向けの手順書は [`documents/guides/domain_setup.md`](../documents/guides/domain_setup.md)。
ドメイン取得 → DNS → パケットフィルタ → `app_domain` 指定で反映 → `force_ssl=true`、の順。

---

## 7. 既知の制限

- Docker の導入は Ubuntu の `docker.io` + `docker-compose-v2`。Docker 公式リポジトリ
  （最新版）は使わない。既に Docker が入っていれば何もしない。
- UFW は「許可を足す」だけで、削除・`reset` はしない（SSH 締め出し防止）。
- `docker compose` は `command` で呼んでいるので `--check` では実行されない
  （表示だけ）。実際の差分確認は `--diff` と `docker compose config` を併用する。

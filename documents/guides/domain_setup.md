# 公開ドメインの設定と HTTPS 化（Issue #121）

本番（さくらのVPS `153.126.189.79` / `/opt/agent-bank`）を **HTTP のみ** で
運用している状態から、独自ドメイン + HTTPS に切り替えるまでの手順。

作業は **すべてオーナー側（ドメイン取得・DNS・VPS のパケットフィルタ）** と
**サーバー側（`.env` と Caddyfile）** の 2 系統に分かれる。所要は DNS 浸透待ちを
除いて 30 分程度。

> 現状: サーバー内は全面稼働（スモーク 21/21）。`Caddyfile` は
> `http://{$APP_DOMAIN:localhost} {` で HTTP 固定。`APP_DOMAIN` 未設定。

---

## 0. 全体の流れ

| # | やること | どこで | 期待結果 |
|---|---|---|---|
| 1 | ドメインを用意（取得 or 既存のサブドメイン） | オーナー | ドメイン名が決まる |
| 2 | DNS の A レコードを `153.126.189.79` へ | オーナー | `dig +short` がその IP |
| 3 | さくらのパケットフィルタで 80/443 を開放 | オーナー | `nc -vz` が succeeds |
| 4 | `APP_DOMAIN` を設定して反映 | サーバー | Caddyfile が HTTPS 形になる |
| 5 | `https://ドメイン` の到達確認 | どこからでも | 200 / 証明書が正規 |
| 6 | `FORCE_SSL=1` を入れて反映 | サーバー | http → https に 308 |
| 7 | スモーク | サーバー | 21/21 成功 |

**順番を守る。** 3 より前に 4 をやると Caddy が証明書を取れず、
4 より前に 6 をやると全画面が到達不能になる（http で `force_ssl` が効くため）。

---

## 1. ドメインを用意する

新規に取る場合も、既存ドメインのサブドメインを使う場合も同じ。

- サブドメインで構わない（例: `lamprey.example.com`）。
- ネームサーバーは取得先のデフォルトのままで良い。
- **この時点でサーバー側の変更は不要。**

決まったら、以降のコマンドの `lamprey.example.com` を自ドメインに置き換える。

---

## 2. DNS の A レコードを VPS に向ける

| 種別 | 名前 | 値 | TTL |
|---|---|---|---|
| A | `lamprey`（または `@`） | `153.126.189.79` | 300（短めに） |

- IPv6 を使う場合は AAAA は**追加しない**（VPS 側の v6 到達性を確認していないため）。
- ワイルドカード（`*`）は不要。

### 浸透確認（期待結果: IP が 1 行だけ返る）

```bash
dig +short lamprey.example.com A
# => 153.126.189.79

# 伝播前は何も返らない / 古い IP が返る。TTL 300 なら数分〜15分で切り替わる。
```

`0.0.0.0` や別 IP が返るうちは **次に進まない**（Caddy の証明書取得が失敗する）。

---

## 3. 80/443 を開放して到達確認

さくらのVPS のコントロールパネル → サーバー設定 → **パケットフィルタ**で、
`Web(80)` と `Web(443)` を許可する。SSH(22) は現状のまま。

```bash
# 外から（手元の Mac で）
nc -vz lamprey.example.com 80
# => Connection to lamprey.example.com port 80 [tcp/http] succeeded!

nc -vz lamprey.example.com 443
# => Connection to lamprey.example.com port 443 [tcp/https] succeeded!
```

`Operation timed out` のままなら **パケットフィルタが閉じている**。ここを開けずに
次へ進むと、Caddy の ACME チャレンジ（HTTP-01）が通らず証明書が取れない。

> サーバー内から確認する場合は `ssh ubuntu@153.126.189.79 'sudo ss -ltnp | grep -E ":(80|443)"'`
> で Caddy が待ち受けていること（`docker compose` の `caddy` コンテナ）。

---

## 4. `APP_DOMAIN` を設定して反映する

### 4-a. Ansible で行う場合（推奨）

```bash
cd ansible
ansible-playbook playbooks/app.yml -e app_domain=lamprey.example.com --check --diff  # 差分確認
ansible-playbook playbooks/app.yml -e app_domain=lamprey.example.com                 # 反映
```

`app.yml` がやること:

1. `.env` の `APP_DOMAIN` / `domain` を更新（`FORCE_SSL` はまだ空のまま）
2. `Caddyfile` のサイトアドレス行を `{$APP_DOMAIN:localhost} {` に差し替え
3. `caddy` を再起動 → ビルド → `compose up -d` → `/_health` 待ち → スモーク

### 4-b. 手作業で行う場合

```bash
ssh ubuntu@153.126.189.79
cd /opt/agent-bank

# 1) .env
sed -i 's|^APP_DOMAIN=.*|APP_DOMAIN=lamprey.example.com|' .env
sed -i 's|^domain=.*|domain=lamprey.example.com|' .env

# 2) Caddyfile の 1 行（http:// を外すだけ。これで自動 HTTPS が有効になる）
sed -i 's|^http://\({[^}]*}\)|\1|' Caddyfile   # 20行目が `{$APP_DOMAIN:localhost} {` になっていれば成功

# 3) 反映（Caddy は設定を再読込、Rails は .env を読み直すため再作成）
sudo docker compose -f compose.production.yaml restart caddy
sudo docker compose -f compose.production.yaml up -d --no-deps --force-recreate web worker
```

### 期待結果

```bash
grep -nE '^(http://)?\{\$APP_DOMAIN:localhost\} \{' Caddyfile
# => 20:{$APP_DOMAIN:localhost} {          ← http:// が消えている

sudo docker compose -f compose.production.yaml logs --tail=30 caddy
# => "certificate obtained successfully" 系のログが出る（初回は 10〜60 秒）
```

---

## 5. `https://` の到達確認

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://lamprey.example.com/ja
# => 200

curl -sSI http://lamprey.example.com/ja | head -1
# => HTTP/1.1 308 Permanent Redirect        ← Caddy が HTTPS へ飛ばす

# 証明書が正規に取れているか（自己署名ではないこと）
echo | openssl s_client -servername lamprey.example.com -connect lamprey.example.com:443 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates
# => issuer が Let's Encrypt 系、subject が CN = lamprey.example.com
```

---

## 6. `FORCE_SSL=1` を入れる

Caddy 側の HTTPS が確認できてから入れる。Rails 側でも
`force_ssl` + セッション Cookie の `secure` が有効になる（`/_health` は除外）。

```bash
# Ansible
cd ansible && ansible-playbook playbooks/app.yml -e app_domain=lamprey.example.com -e force_ssl=true

# 手作業
ssh ubuntu@153.126.189.79 'cd /opt/agent-bank && sed -i "s|^FORCE_SSL=.*|FORCE_SSL=1|" .env \
  && sudo docker compose -f compose.production.yaml up -d --no-deps --force-recreate web worker'
```

### 期待結果

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://lamprey.example.com/ja      # 200
ssh ubuntu@153.126.189.79 "curl -sS -o /dev/null -w '%{http_code}\\n' http://127.0.0.1:3000/_health"   # 200（SSL 除外）
curl -sSI https://lamprey.example.com/ja | grep -i set-cookie                 # Secure が付く
```

---

## 7. スモークで回帰確認

```bash
ssh ubuntu@153.126.189.79 'cd /opt/agent-bank && PW=$(sed -n "s/^ROOT_PASSWORD=//p" ~/.env | head -1) \
  && echo "$PW" | sudo -S -p "" docker run --rm --network host \
  -v /opt/agent-bank/script/smoke_check.rb:/tmp/smoke_check.rb:ro \
  agent-bank-web ruby /tmp/smoke_check.rb https://lamprey.example.com'
# => 21/21 成功（すべて OK）
```

Ansible 経由なら `app.yml` の最後で自動実行される。

---

## 8. 切り分け

| 症状 | 原因の候補 | 確認 |
|---|---|---|
| `curl https://…` が `Connection refused` | 443 がパケットフィルタで閉じている / Caddy 停止 | `nc -vz ドメイン 443`、`compose ps` |
| 証明書が自己署名 / `NET::ERR_CERT_AUTHORITY_INVALID` | `Caddyfile` に `http://` が残っている | `grep` の期待結果（4 章）を再確認 |
| Caddy ログに `acme: challenge failed` | DNS 未浸透 / 80 が閉じている | `dig +short`、`nc -vz ドメイン 80` |
| 全画面が `ERR_TOO_MANY_REDIRECTS` | `FORCE_SSL=1` を Caddy の HTTPS 化前に投入した | `FORCE_SSL=` を空にして `web` を再作成 |
| 502 Bad Gateway | `web` が healthy でない | `compose ps`、`compose logs --tail=50 web` |
| 管理画面だけ 403 | `ADMIN_ALLOWED_IPS` に自分の回線が入っていない（#120） | `.env` の値を確認し `web` を再作成 |

`FORCE_SSL` を誤って先に入れてしまった場合の復旧:

```bash
ssh ubuntu@153.126.189.79 'cd /opt/agent-bank && sed -i "s|^FORCE_SSL=.*|FORCE_SSL=|" .env \
  && sudo docker compose -f compose.production.yaml up -d --no-deps --force-recreate web worker'
```

---

## 9. ロールバック（HTTP 運用に戻す）

```bash
cd ansible
ansible-playbook playbooks/app.yml -e app_domain= -e force_ssl=false
```

`app_domain` を空にすると `Caddyfile` は `http://` 形に戻り、`.env` の
`APP_DOMAIN` は `localhost`、`FORCE_SSL` は空になる。**冪等**なので何度流しても同じ。

---

## 10. 関連

- `ansible/README.md` — Ansible 構成の使い方
- `documents/guides/security_hardening.md` — `ADMIN_ALLOWED_IPS` / `FORCE_SSL` の詳細（#120）
- `documents/plans/20261028-vps-phase4.md` — Caddy 導入時の設計メモ（#99）

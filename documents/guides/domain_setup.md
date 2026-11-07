# 公開ドメインの設定と HTTPS 化（Issue #121）

本番（さくらのVPS `153.126.189.79` / `/opt/agent-bank`）を **HTTP のみ** で
運用している状態から、独自ドメイン + HTTPS に切り替えるまでの手順。

作業は **すべてオーナー側（ドメイン取得・DNS・VPS のパケットフィルタ）** と
**サーバー側（`.env` と Caddyfile）** の 2 系統に分かれる。所要は DNS 浸透待ちを
除いて 30 分程度。

> **2026-11-08 適用済み（当初の `persona-bank.jp` はレジストラに停止されたため、
> `rakuichi-rakumon.jp` に切り替えた。経緯は Issue #140）。** `https://rakuichi-rakumon.jp` で HTTP/2 200、証明書は
> Let's Encrypt（CN=`rakuichi-rakumon.jp`、有効期限 2027-02-05）、`http://` は 308 で
> HTTPS へ、セッション Cookie は `Secure`、スモーク 21/21。
> 以下の手順は「別ドメインへ移す／やり直す」ときの再現手順として残している。

### 適用結果（実測）

| 項目 | 結果 |
|---|---|
| `https://rakuichi-rakumon.jp/ja` | HTTP/2 **200** |
| `http://rakuichi-rakumon.jp/ja` | **308** → `https://rakuichi-rakumon.jp/ja` |
| 証明書 | `subject: CN=rakuichi-rakumon.jp` / `issuer: C=US; O=Let's Encrypt; CN=YE1` / 期限 2027-02-05 / `SSL certificate verify ok` |
| `set-cookie` | `Secure` / `HttpOnly` / `SameSite=Lax` |
| `.env` | `APP_DOMAIN=rakuichi-rakumon.jp` / `FORCE_SSL=1` / `domain=rakuichi-rakumon.jp` / `always_use_ssl=true` |
| `Caddyfile` 20 行目 | `{$APP_DOMAIN:localhost} {` |
| スモーク | **OK 全 21 項目が成功（1.0秒）** |
| `https://www.rakuichi-rakumon.jp/ja` | **301** → `https://rakuichi-rakumon.jp/ja`（証明書 `CN=www.rakuichi-rakumon.jp` / Let's Encrypt） |
| ACME | http-01 で取得成功（Caddy ログ `authorizations succeeded; finalizing order`） |

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

## 1. ドメイン（決定済み: `rakuichi-rakumon.jp`）

| 項目 | 値 |
|---|---|
| 本番 URL | `https://rakuichi-rakumon.jp` |
| レジストラ / DNS | GoDaddy（NS は `ns39/ns40.domaincontrol.com`） |
| 正しい A レコード | `@` → `153.126.189.79`（**1 本だけ**） |

### ⚠️ 取得直後の状態で残っている不要な A レコード（実測 2026-11-06）

```
dig +short rakuichi-rakumon.jp A
3.33.130.190      ← GoDaddy のパーキング（/lander に飛ばすだけの 114 バイトの HTML）
15.197.148.33     ← 同上
153.126.189.79    ← 本番 VPS（Caddy が応答）
```

A が 3 本あると**ブラウザが 3 本のうち 1 本をランダムに選ぶ**ため、2/3 の確率で
GoDaddy のパーキングページが出る。**この 2 本を削除するのが最初の作業**。

### `www` / `*` を使わない理由

| 候補 | 判定 | 理由 |
|---|---|---|
| `@`（`rakuichi-rakumon.jp`） | **採用** | 本番 URL はこれ 1 本に固定する |
| `www` | 301 で apex へ寄せる | `www` は apex への CNAME のまま。Caddyfile の `www.{$APP_DOMAIN}` ブロックが `https://rakuichi-rakumon.jp{uri}` へ **301** し、証明書も `www` 用に自動取得する（実測: `CN=www.rakuichi-rakumon.jp` / Let's Encrypt） |
| `*`（ワイルドカード） | 使わない | 未知のホスト名でも Caddy に届き、ACME の取得失敗・レート制限の原因になる。アプリは 1 ホストで足りる |

---

## 2. DNS の A レコードを整理する

GoDaddy → マイプロダクト → `rakuichi-rakumon.jp` → **DNS**。

| 操作 | タイプ | 名前 | 値 |
|---|---|---|---|
| **削除** | A | `@` | `3.33.130.190` |
| **削除** | A | `@` | `15.197.148.33` |
| **残す**（無ければ追加） | A | `@` | `153.126.189.79` |

- TTL は `600`（GoDaddy の既定）で構わない。切り替えを速くしたいなら `600` のまま数分待つ。
- **AAAA は追加しない**（VPS の IPv6 到達性を確認していない）。
- `www` の CNAME はそのままで良い（apex が 1 本になれば `www` も VPS を向く。ただし `https://www.…` は証明書が無いので使わない）。
- GoDaddy の **「ドメイン転送 / Forwarding」が有効**だとこの A 2 本が再生成される。転送を使っていないなら設定ごと解除する。

### 浸透確認（期待結果: `153.126.189.79` が 1 行だけ返る）

```bash
dig +short rakuichi-rakumon.jp A
# => 153.126.189.79

dig +short @8.8.8.8 rakuichi-rakumon.jp A
dig +short @1.1.1.1 rakuichi-rakumon.jp A
```

`3.33.130.190` / `15.197.148.33` がまだ混ざるうちは **次に進まない**
（その IP はパーキングを返すので、Caddy の証明書取得も不安定になる）。

---

## 3. 80/443 を開放して到達確認

さくらのVPS のコントロールパネル → サーバー設定 → **パケットフィルタ**で、
`Web(80)` と `Web(443)` を許可する。SSH(22) は現状のまま。

```bash
# 外から（手元の Mac で）。ドメインを引かず IP 直で見るのが速い。
nc -vz 153.126.189.79 80
# => Connection to 153.126.189.79 port 80 [tcp/http] succeeded!

nc -vz 153.126.189.79 443
# => Connection to 153.126.189.79 port 443 [tcp/https] succeeded!
```

### 実測済みの状態（2026-11-06）

| ポート | 実測 | 意味 |
|---|---|---|
| 80 | `succeeded!` | パケットフィルタは**通っている** |
| 443 | `Connection refused` | Caddy が HTTP 固定で 443 を listen していないため。**正常**。4 章の HTTPS 化後に成功すればよい |
| 22 | `succeeded!` | そのまま |

`443` が HTTPS 化後も `refused` のままなら、パケットフィルタ（`Web(443)`）を
確認する。`Operation timed out`（拒否ではなく無応答）の場合はパケットフィルタで
落ちている。ここが閉じていると Caddy の ACME チャレンジ（HTTP-01）が通らず
証明書が取れない。

> サーバー内からは `ssh ubuntu@153.126.189.79 'sudo ss -ltnp | grep -E ":(80|443)"'`
> で Caddy（`compose` の `caddy` コンテナ）の待ち受けを確認できる。

---

## 4. `APP_DOMAIN` を設定して反映する

### 4-a. Ansible で行う場合（推奨）

```bash
cd ansible
ansible-playbook playbooks/app.yml -e app_domain=rakuichi-rakumon.jp --check --diff  # 差分確認
ansible-playbook playbooks/app.yml -e app_domain=rakuichi-rakumon.jp                 # 反映
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
sed -i 's|^APP_DOMAIN=.*|APP_DOMAIN=rakuichi-rakumon.jp|' .env
sed -i 's|^domain=.*|domain=rakuichi-rakumon.jp|' .env

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
curl -sS -o /dev/null -w '%{http_code}\n' https://rakuichi-rakumon.jp/ja
# => 200

curl -sSI http://rakuichi-rakumon.jp/ja | head -1
# => HTTP/1.1 308 Permanent Redirect        ← Caddy が HTTPS へ飛ばす

# 証明書が正規に取れているか（自己署名ではないこと）
echo | openssl s_client -servername rakuichi-rakumon.jp -connect rakuichi-rakumon.jp:443 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates
# => issuer が Let's Encrypt 系、subject が CN = rakuichi-rakumon.jp
```

---

## 6. `FORCE_SSL=1` を入れる

Caddy 側の HTTPS が確認できてから入れる。Rails 側でも
`force_ssl` + セッション Cookie の `secure` が有効になる（`/_health` は除外）。

```bash
# Ansible
cd ansible && ansible-playbook playbooks/app.yml -e app_domain=rakuichi-rakumon.jp -e force_ssl=true

# 手作業
ssh ubuntu@153.126.189.79 'cd /opt/agent-bank && sed -i "s|^FORCE_SSL=.*|FORCE_SSL=1|" .env \
  && sudo docker compose -f compose.production.yaml up -d --no-deps --force-recreate web worker'
```

### 期待結果

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://rakuichi-rakumon.jp/ja      # 200
ssh ubuntu@153.126.189.79 "curl -sS -o /dev/null -w '%{http_code}\\n' http://127.0.0.1:3000/_health"   # 200（SSL 除外）
curl -sSI https://rakuichi-rakumon.jp/ja | grep -i set-cookie                 # Secure が付く
```

---

## 7. スモークで回帰確認

```bash
ssh ubuntu@153.126.189.79 'cd /opt/agent-bank && PW=$(sed -n "s/^ROOT_PASSWORD=//p" ~/.env | head -1) \
  && echo "$PW" | sudo -S -p "" docker run --rm --network host \
  -v /opt/agent-bank/script/smoke_check.rb:/tmp/smoke_check.rb:ro \
  agent-bank-web ruby /tmp/smoke_check.rb https://rakuichi-rakumon.jp'
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

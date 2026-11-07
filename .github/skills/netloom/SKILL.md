---
name: netloom
description: |
  第三者 API への接続を netloom に集約するスキル。netloom は薄いプロキシの Go 単体バイナリで、呼び出し側は URL・ヘッダ・認証方式を知らずに、1 コマンド = 1 往復で provider の答えをそのまま受け取る。すべての往復は VCR カセット（JSONL）に残り、`--replay` でオフライン再現できる（証跡付きの収集）。
  **送信元の一覧と版は `netloom version --sources` / `version --json` が唯一の正**（本文と設計書が仕様）。副作用のある操作（実メールの送信・prod への書き込み・公開 DOI の登録）は明示フラグが要る。
  以下、送信元ごとの要点:
  Google Trends はキーワード・地域・期間を指定して検索興味度（0–100 の相対指数）を取得し、
  2–5 語の相対比較も 1 回の呼び出しで取る。Apify は任意の actor を実行して dataset を読む。
  X API v2 は検索（直近 7 日 / 全期間）と投稿 1 件を取る。
  GA4 は Google Analytics Data API（HTTP）からレポート・リアルタイム・メタデータを取る
  （1 コマンド = 認証 1 + データ 1 の 2 往復。credential は Google の refresh grant）。
  GSC（Google Search Console）は searchAnalytics のクエリとプロパティ一覧を取り、netloom 自身が
  トークンを交換する（1 コマンド = 認証 1 + データ 1 の 2 往復）。
  news / cache は EC-CUBE 自サイトのニュース API（CRUD・サムネイル画像）とキャッシュクリアを扱い、
  article はガイド記事 API（CRUD・画像とそのメタデータ）を扱う（`--env dev|prod`。
  本番への書き込みは `--allow-prod-write` が要る）。
  contact はお問い合わせ API（CRUD。PII を含む）、ga4-orders は GA4 受注同期 API（CRUD。
  GA4 Data API の ga4 とは別物。売上データを含む）を扱う（同じ `--env dev|prod`）。
  landing-page は LP API（CRUD。`--clear-cache` は書き込みに付く。LP の本文は業務データ。
  prod 未デプロイ = live 受入は dev のみ）を扱う（同じ `--env dev|prod`）。
  openseo はローカル Docker の OpenSEO MCP（HTTP）からプロジェクト一覧・キーワードメトリクス・
  ランクキーワード・ドメイン概観・SERP 競合を取る（1 コマンド = 1 往復。credential 不要。Docker は呼び出し側）。
  gmail は既存の Gmail MCP サーバー（stdio）からメールを送る（1 コマンド = 1 MCP 往復。
  **送信は副作用**。OAuth はサーバー側で、netloom は credential を読まない）。
  meta-page / meta-instagram は Meta Graph API（Facebook Page / Instagram）から投稿・インサイトを取る
  （送信元を 2 つに分ける: Page 側は PAGE_TOKEN、Instagram 側は USER_TOKEN。1 コマンド = 1 往復。
  ページングは呼び出し側が応答の paging.next で回す）。
  mysql は EC-CUBE の MySQL を SSH トンネル経由で **読み取り専用**で見る
  （`mysql tunnel` でトンネルを起動（冪等）・`mysql tunnel-status` で状態・`mysql query --sql 'SELECT …'` で 1 文 = 1 往復。
  書き込みは無い。証跡はカセットに残り `--replay` でオフライン再現できる）。
  bigquery は BigQuery の**読み取り専用クエリ**を jobs.query の REST で直接実行する
  （`bigquery query --sql 'SELECT …' [--dry-run] [--max-rows N] [--project ID]`。**1 コマンド = 認証 1 + クエリ 1 の 2 往復**。
  `SELECT` / `WITH … SELECT` だけ。書き込みは無い。**BigQuery は課金が発生しうる**: まず `--dry-run`（課金なしの見積もり）。
  project は `--project` → `GOOGLE_CLOUD_PROJECT` → `GCLOUD_PROJECT`。証跡はカセットに残り `--replay` でオフライン再現できる）。
  calendar は Google Calendar API v3 からカレンダーと予定を扱う
  （`calendar list-calendars|list-events|get-event|create-event|update-event|delete-event`。**1 コマンド = 認証 1 + データ 1 の 2 往復**。
  **書き込み 3 つは副作用**（予定が作られる / 置き換えられる / 消える）— live の書き込みは owner 承認が前提。
  `update-event` は PATCH = 1 往復。calendar id は `--calendar-id` → `GOOGLE_CALENDAR_ID` → `primary`。証跡はカセットに残り `--replay` でオフライン再現できる）。
  apps-script は Google Apps Script API v1 からプロジェクト・ソース・バージョン・デプロイ・プロセスを扱い、任意の関数を実行する
  （`apps-script create-project|get-project|get-project-content|update-project-content|list-project-versions|create-version|list-deployments|get-deployment|create-deployment|update-deployment|delete-deployment|run-script|list-processes`。**1 コマンド = 認証 1 + データ 1 の 2 往復**。
  **書き込み 7 つと run-script は副作用** — とくに run-script は任意の関数を実行する（メール・シート等が起こりうる）。live は owner 承認が前提。
  script id は `--script-id`（推測しない）。証跡はカセットに残り `--replay` でオフライン再現できる）。
  site は自サイト（EC-CUBE）の**死活監視とデバッグ**を担う
  （`site check --env local|dev|prod --target front|mypage|admin|all`。Basic → CSRF 抽出 → ログイン POST → セッション確立 → 本リクエストを内部化し、
  各 URL の判定（200 を基本、保護ページの未ログイン 302 → ログインは正常、それ以外とエラー画面は NG）/ 応答時間 / 失敗段（basic·csrf·login·session·request）を一覧と `--format json` で返す。
  **1 コマンド = 面の URL 数 + ログイン段数（+ リダイレクトの hop）の往復**。exit 0 = 全件 OK / 1 = 1 件以上 NG / 2 = 前提不足。証跡はカセットに残り `--replay` で credential 無しに再現できる）。
  psi / crux は**非公開 API**（issue #24: 既定の導線に出さない。consumer の測定系 = ローカル Lighthouse が正で、明示指示があるときだけ使う。置き換えを意図しない）:
  psi は PageSpeed Insights API v5 からページの Lighthouse 測定を取り、crux は Chrome UX Report API v1 から実ユーザーのメトリクス（日次 / 履歴）を取る
  （`psi run --url URL [--strategy mobile|desktop] [--categories a,b,c]` / `crux query --origin ORIGIN | --url URL [--form-factor PHONE|DESKTOP|TABLET] [--metrics M1,M2]` /
  `crux history --origin ORIGIN | --url URL [--form-factor …] [--collection-periods N]`。**1 コマンド = 1 往復**。
  **credential は query の `key`**（`PAGESPEED_API_KEY` / `CRUX_API_KEY`。同じ値でも変数名は両方設定する。未設定なら 1 往復も送らず exit 2、`--replay` でも要る）。
  **キーはカセットの URL に残るので `.cassettes/` のみ・コミットしない**。**PSI は quota を消費する**。**キャッシュ回避は呼び出し側**（URL にダミーのクエリを付ける等。netloom は URL をそのまま送る）。
  **ローカル Lighthouse とは別測定系**（数値を混ぜて比較しない）。csv は無い。
  youtube は YouTube Data API v3 から動画検索と動画の詳細（日付補完）を取りる
  （`youtube search --query Q [--max-results N] [--published-after RFC3339] [--published-before RFC3339] [--region-code CC] [--relevance-language LANG] [--page-token TOKEN]` /
  `youtube videos --id ID[,ID…]`。**1 コマンド = 1 往復**。
  **credential は query の `key` = `YOUTUBE_API_KEY`**（psi / crux と同じ扱い。未設定なら 1 往復も送らず exit 2、`--replay` でも要る。**キーはカセットの URL に残るので `.cassettes/` のみ・コミットしない**）。
  **絶対日付の年次スライス（`publishedAfter` / `publishedBefore`）は Apify actor（rolling window）では代替不可**（issue #29）。
  **quota は呼び出し側**: `search.list` は 100 units/回（`videos.list` は 1 unit）。**ページングも呼び出し側**（`--page-token` は provider の値をそのまま。netloom は `nextPageToken` を追わない）。csv は無い。
  zenodo は Zenodo REST API から**公開 record・その版の一覧・自分の deposition とそのファイル**を読み、**下書きを書く**（作成 / metadata 更新 / 下書きの削除 / ファイルの upload（multipart）と file delete / newversion）
  （`zenodo record --id ID` / `zenodo record-versions --id ID [--sort S] [--size N]` / `zenodo deposition --id ID` / `zenodo deposition-files --id ID` /
  `zenodo deposition-create --input JSON|@FILE` / `zenodo deposition-update --id ID --input JSON|@FILE` / `zenodo deposition-delete --id ID` /
  `zenodo deposition-upload --id ID --file PATH` / `zenodo deposition-file-delete --id ID --file-id FILEID` / `zenodo deposition-newversion --id ID`。**1 コマンド = 1 往復**。
  **credential は 11 コマンド共通で必須**: `ZENODO_TOKEN` を `Authorization: Bearer` で送る（公開 record の読み取りにも送る 1 送信元 1 規則。未設定なら 1 往復も送らず exit 2、`--replay` は credential 不要）。
  id は呼び出し側が書いたまま path に入る。`--sort` / `--size` は**与えたときだけ**載る pass-through（検査しない）。
  **公開（DOI 登録）だけが不可逆**なので、`zenodo deposition-publish --id ID --allow-publish` は **`--allow-publish` が無ければ 1 往復も送らず exit 2**（`--replay` は不要）。下書きの書き込みには門を付けない。
  csv は無く、`deposition-files` は**配列**・`deposition-delete` は**文書無し**なので `text` も無い（json / verbatim の 2 形。`--format text` は exit 2）。
  lighthouse は**ローカル計測**（Node の lighthouse を exec）で、1 コマンド = N 回（既定 5）の計測を回し、**生 JSON を --out の run1.json 〜 runN.json に置くだけ**（解釈しない。issue #46）
  （`lighthouse run --url URL --out DIR [--runs N] [--form-factor mobile|desktop] [--chrome-path PATH] [--lighthouse-version V]`。run ごとに Chrome プロファイルを分ける。
  **カセットは無く `--cassette` / `--replay` / `--format` は exit 2**（証跡は `--out`。新規は 0600）。`node` / `npx` が無ければ exit 127、ツールの失敗は exit 1（`--runs` は続ける）。
  **psi / crux とは別測定系** — ローカル Lighthouse が consumer の測定の正で、混ぜない）。live は実測済み（親の 2026-10-19 実測: exit 0・約 21 秒・161 audits・`run1.json` 921,296 B・0600）。
  playwright は**ローカルブラウザ**（Playwright の Chromium を exec）で、`shot|html|eval` は 1 コマンド = 1 ページ読み込み（issue #47）
  （`playwright shot --url URL --out PATH [--full-page] [--playwright-version V]` / `html` / `eval --url URL --script FILE --out PATH`。出力は PNG / JS 実行後の DOM / 戻り値の JSON。
  `--viewport` / `--wait-until` は pass-through。**カセットは無く `--cassette` / `--replay` / `--format` は exit 2**。ブラウザの導入は呼び出し側（`npx playwright install chromium`）、`node` / `npx` が無ければ exit 127。
  **版とブラウザは対**（`playwright@V` は chromium ビルド `<rev>` を要求する。ピン = 1.63.0 = chromium-1243。導入済みが別のビルドなら `--playwright-version V` で合わせる）。live は未実測（修正後の 3 コマンドを親が実行する）。
  **`flow`（issue #53）は 4 つ目のコマンド**: `playwright flow --script FILE --out PATH [--timeout SEC] [--playwright-version V] [--env-allow NAME,...]` = **1 コマンド = 1 セッション = 1 ブラウザ起動 = N ページ読み込み**（「1 コマンド = 1 往復」の明示的な例外 — カートは browser context を跨げば引けない）。スクリプトを **Node コンテキスト**で評価し **`page` / `context` を引数に渡す**（`eval` のページコンテキストと別）。スクリプトは**async function の本体**（トップレベル await 可）、**return 値**が `--out` に JSON。**`--url` / `--viewport` / `--wait-until` は無い**（渡すと exit 2）。**スクリプトは `about:blank` から始まる — ページ内の `fetch` や DOM 参照の前に `page.goto` で対象ページを開くこと**（`about:blank` からの `fetch` は別 origin 扱いで CORS で失敗する = `TypeError: Failed to fetch`。`eval` から移すときに踏む罠 = issue #59）。`gtag` / `dataLayer` のスタブはスクリプト側、netloom はページの JS を書き換えない。live は親が dev サーバーで実行する）。
  **dev / ステージングが HTTP Basic の背後にあるとき**: playwright（4 コマンド共通）は **`HTTP_BASIC_AUTH_USER` / `HTTP_BASIC_AUTH_PASS` の両方が設定されているときだけ、netloom（ハーネス）が `Authorization: Basic <base64(user:pass)>` ヘッダをすべての要求に付ける**（issue #57。`site` ソースが transport で同じ 2 変数から同じヘッダを組むのと同じ形。片方だけなら付けない・未設定なら何もしない = 401 ページをそのまま証跡にできる）。`flow` のスクリプトが自分で `setExtraHTTPHeaders` を呼んでも同じヘッダになる（同じ 2 変数。1 回で足りる）。値はログ・エラー行に出ない。`env check --source playwright` がこの 2 変数を申告する（★ 任意 = 門にはしない）
  **flow のサンドボックスに届くもの（issue #61）**: スクリプト（Node コンテキスト）が `process.env` で読めるのは下の表だけ。**それ以外は届かない**（プロセス env 全体は継承しない）。`--env-allow` は `flow` だけが持つ（`shot` / `html` / `eval` に渡すと exit 2）。未設定の名前があると **exit 2 で何も始めない**（ブラウザ起動なし・`--out` なし）。**設定済みの空文字は空文字として届く**（`"FOO" in process.env` が真・値は `""`）。渡した値は netloom の出力（stdout / stderr の失敗行）には出ない（`[REDACTED]`）。**部分一致で伏せる**ので、1〜2 文字のような短い値を名指すと netloom 自身の行の同じ文字列も伏せる（値を出さないことを優先する安全側）。**ただしスクリプトが自分で `process.env.FOO` を return すると、その値は呼び出し側自身の `--out` に入る** — スクリプトの答えであって netloom の出力ではない。秘密を return しないのは呼び出し側の責任。
  | 届くもの | 条件 |
  |---|---|
  | `PATH` / `HOME` | 常に |
  | `HTTP_BASIC_AUTH_USER` / `HTTP_BASIC_AUTH_PASS` | 両方が設定されているときだけ（ハーネスが Basic ヘッダも付ける） |
  | `--env-allow` で名指した名前 | 設定されているとき（空文字を含む。未設定は exit 2） |
  | それ以外 | 届かない |
  devtools は **CDP の観測**（`chrome-devtools-mcp@1.11.0` を MCP のまま使う = google-trends / gmail と同じ経路）で、**1 コマンド = 決まった並びの `tools/call`**（issue #49 / #52。**「1 コマンド = 1 `tools/call`」の例外**）
  （`devtools network|console|snapshot --url URL --out PATH [--format json|text|verbatim]` / `devtools trace --url URL --out DIR [--analyze]`。
  network / console / snapshot = `navigate_page` → 読む（**2**）、trace = start → navigate → stop（**3**、`--analyze` で **4**）。
  **`network --match REGEXP [--max-details N]`**（issue #52）は、リスト後 **URL が RE2 式にマッチした要求だけ**を**同じセッション内で** `get_network_request` で取得する（**呼び出し回数 = 2 + M**、M = min(マッチ数, `--max-details`)。既定 **10**）。**reqid はセッション内の id** なので、リストしたセッションの中で取るのが唯一の経路（別コマンドの id では引けない = 実測 2026-10-20 に exit 1 で確認。`request` コマンドは削除）。**`--out` はリストのまま**、**各詳細は `<out>-detail-<requestId>.json` に 1 文書ずつ**（provider の文書をそのまま。netloom は parse しない。詳細は常に `json` = `--format` はリストにだけ効く）。マッチ 0 件でも exit 0（詳細ファイルが無いだけ）。`--match` は RE2 として読めればよく（無効な正規表現は exit 2）値の語彙は見ない。**`--match` の詳細の答えは POST ボディ・Cookie / Set-Cookie ヘッダを含む**。
  答えは `--out`（stdout には出さない。trace は `trace.json` + `insight.txt`）。**カセットは普通に記録する**（MCP の往復。`--replay` は並びの順に照合）。
  **`npx` / `node` が無ければ 1 往復もせず exit 127**（カセットも作らない）、ブラウザ（Chrome）はサーバーが自分で起動する（無ければツールのエラー = exit 1）。
  **サーバーは `--no-page-id-routing` で起動する**（`pageIdRouting` の既定 true は全 page-scoped ツールの schema に必須の `pageId` を足し、渡さないと `navigate_page` が isError になる — 2026-10-19 の live 実測 = A.36 判断 D23）。
  **計測ではない** — PageSpeed の数値（ローカル Lighthouse / psi）と混ぜない）。live は親が実行する（2026-10-19 の 1 回目で `pageIdRouting` の欠陥を発見・修正済み。修正後の再実行待ち）。
  auth google はローカルコマンド（対話専用の Google OAuth 同意フロー）で、ブラウザ同意から
  トークンファイル（$HOME/.config/netloom/google-<source>.json、0600）を書き、Google 5 送信元（gsc / ga4 / bigquery / calendar / apps-script）はそのファイルを credential として読める（値は stdout / stderr / カセットに出ない）。
  **注意（2026-10-20）**: netloom は **env ファイルも読む**（§7.5）ので、**`.env` / `.env.d/*.env` に書かれた `GOOGLE_TOKEN_FILE` は ① に勝つ** — ② / ③ へ降りたいときは **その行をコメントアウト / 削除する**（`env -u` だけでは足りない）。
  **解決順（issue #51）**: ①`GOOGLE_TOKEN_FILE`（設定されていればそれを使う）→ ②ソース既定パス `~/.config/netloom/google-<name>.json`（**存在的きのみ** = auth google の書込先と対称。apps-script の既定名は `gas`）→ ③`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN`。**Google の交換が失敗したときだけ**、失敗行に「どの credential を使ったか」（パスまたは変数名。値は出さない）が 1 つ足される（切り分け用）。`env check` の門は既定パスが存在的きときも満たされる。
  交換の証跡（2 frame）は `--cassette FILE` で caller の記録置き場に置ける（例: `data/gsc/cassettes/<YYYYMMDD>-auth-gsc.jsonl`。issue #22）。
  すべての往復は VCR カセットに残り、カセットからオフライン再現できる（証跡付きの収集）。
netloom-version: 0.14.2
---

# netloom（第三者 API の収集プロキシ）

このスキル自身は netloom のバイナリに埋め込まれている（正本は `internal/usecase/skill/netloom/SKILL.md`）。配布と確認は `netloom skill install` / `netloom skill check` で行い、手でコピーしない（CI の 1 ステップと複数 checkout への一括配布は下の「このスキルの配布」、README「スキルの配布」）。

第三者のデータ取得は netloom のコマンドだけで行う。provider の MCP サーバーを直接叩いたり、
actor を curl で呼んだりしない（証跡とオフライン再現が失われるため）。

`--replay` は同じ request の記録が複数あるとき、**その request の n 回目の要求に n 番目の記録**で答える（記録を順に消費する。**その request の記録を使い切ったら最初の記録** = issue #14 の規則）。site の mypage のように **1 コマンドが同じ URL を複数回要求する flow** はこの規則で live と同じ判定になる（設計書 §5.1）。**新しい証跡で再現したいときは `--cassette` を分ける**（`--cassette <新しいファイル>` で記録し、そのカセットを `--replay` する）。

同じ request を `--cassette` で 2 回記録すると、**追記の前に stderr へ 1 行で知らされる**（`netloom: <file> already holds a record for this request: a replay answers with the first one`。値は出ない。初回記録・`--replay` では出ない。通知は答えを変えない — 答えは §5.1 の規則（その request を 1 回だけ要求するコマンドでは最初の記録）が決める。issue #17）。
**カセットの検査はコマンドで行う**: `netloom cassette show --path FILE`（frame 一覧。payload 本文は出さず sha256 とバイト数（`N B` — 単位付き。issue #43）で示す。**URL の `key=` / `access_token=` の値は表示時だけ `[REDACTED]`** — カセットのバイトと `--replay` の照合は変わらない）と `netloom cassette check --path FILE [--path FILE ...] [--env-file FILE]` — **live 実行後のレダクト検査はこのコマンドにする**（手作業の grep ではなく。env の実値をレダクタと同じ値の集合から**変数名と件数だけで**数え、ヒット 1 件でもあれば exit 1 / credential が 1 つも解決できなければ exit 2。`grep -Fc '\[REDACTED\]'` のように -F なのにエスケープを付けると「0 件」の誤検知を起こす — issue #18 の実測。設計書 付録 A.28）。

**サイズの表示（issue #43）**: netloom がサイズを出すときは **UTF-8 バイト**で、**単位を必ず添える** — json はキー名に `bytes` を含める（`{"bytes": N}` か `xxx_bytes`。例 `article update --dry-run` の `fields_bytes`）、テキストは `N B`（例 `cassette show` のバイト数、`--dry-run` の `fields: citation=3 B`）。**単位なしの裸の数字を出さない**。**文字数を出す場面は今のところ無い**（出るようになったら `chars` という別キーで区別する）。

netloom は起動時に **cwd の env ファイルを自動で読む**（`<cwd>/.env` と `<cwd>/.env.d/*.env` を**両方**読む — `.env` が先で、同じ名前は `.env` が勝つ（issue #37）。`NETLOOM_ENV_FILE` で明示もできる — **1 つ、または `:` 区切りで複数**（`a.env:b.env`。全部を順に読み、先に定義されたものが勝つ。issue #25。**設定されている限り cwd の慣例は読まない**）。探索順・構文は設計書 §7.5）。だから **`set -a; source .env.d/xxx.env; set +a` を書かなくてよい**（書いてあっても動く）。**プロセスの環境変数が常に勝つ**ので、後から `export KEY=…` した値で上書きできる（値が空の env エントリでも勝つ）。読み込んだ値はこのプロセスの env に入り、**stdout / stderr / カセットには出ない**（レダクトされる — stderr に出るのは読み込んだファイル名と件数の 1 行だけ）。env ファイルは**ワークスペース外か gitignore の場所**に `chmod 600` で置き、コミットしない。

- **Google Trends**（MCP stdio）: `google-trends interest-over-time` / `compare-terms` / `related-queries` / `trending-now` / `interest-by-region`（ピン留めした`google-trends-mcp@0.1.1` の **5 ツール全部**。**1 コマンド = 1 MCP 往復**。検索語は `--keyword`（配列の `terms`）と `--term`（1 語）の 2 つの語がある）
- **Apify**（HTTP）: `apify run` / `apify dataset` / `apify run-status` / `apify actor` / `apify build` / `apify key-value-store`
- **X API v2**（HTTP）: `x search-recent` / `x search-all` / `x tweet`
- **GA4**（HTTP。Google Analytics Data API）: `ga4 run-report` / `ga4 run-realtime-report` / `ga4 get-metadata`（**1 コマンド = 認証 1 + データ 1 の 2 往復**。`--property` または `GA4_PROPERTY_ID`）
- **GSC**（HTTP。Google Search Console）: `gsc query` / `gsc sites`（**1 コマンド = 認証 1 + データ 1 の 2 往復**）
- **news / cache**（HTTP。EC-CUBE 自サイト API）: `news list|get|create|update|delete|image-upload|image-delete` / `cache clear`（**1 コマンド = 1 往復**。`--env dev|prod`）
- **article**（HTTP。EC-CUBE ガイド記事 API）: `article list|get|create|update|gate|delete|image-upload|image-delete`（**1 コマンド = 1 往復**。同じ環境・同じ認証。`gate` はゲートの一括切り替えで、フラグは `--input` だけ）
- **contact**（HTTP。EC-CUBE お問い合わせ API）: `contact list|get|create|update|delete`（**1 コマンド = 1 往復**。同じ環境・同じ認証。**応答に顧客の PII が入る**）
- **ga4-orders**（HTTP。EC-CUBE GA4 受注同期 API）: `ga4-orders list|get|create|update|delete`（**1 コマンド = 1 往復**。`X-GA4-API-Key` + `GA4_API_KEY`。**GA4 Data API の `ga4` とは別物**。応答に売上が入る）
- **landing-page**（HTTP。EC-CUBE LandingPage API）: `landing-page list|get|create|update|delete`（**1 コマンド = 1 往復**。同じ環境・同じ認証（`X-API-Key` + dev の Basic）。`--clear-cache` は create / update / delete に付く（1 往復のまま）。**prod 未デプロイ** = live 受入は dev のみ。**LP の本文（`body` / `js` / `css`）は業務データ** — カセットは `.cassettes/` のみ・コミットしない）
- **product**（HTTP。EC-CUBE 商品 / 成分 / 資材 API。**12 コマンド**）: `product list|get|get-by-code|create|update|delete` / `product component-list|component-get|component-purchases` / `product material-list|material-get|material-purchases`（**1 コマンド = 1 往復**。同じ環境・同じ認証（`X-API-Key` + dev の Basic）。**書き込み（create / update / delete）は ContentSync42 プラグイン有効時のみ** — 無効なら 405。`--purge` は取り消し不可の物理削除。**応答は商品と購買履歴（成分 / 資材の詳細は調達原価）を含む** — カセットは `.cassettes/` のみ・コミットしない）
- **openseo**（HTTP。ローカル OpenSEO の MCP over HTTP）: `openseo list-projects` / `keyword-metrics` / `ranked-keywords` / `domain-overview` / `serp-competitors`（**1 コマンド = 1 往復**。credential 不要。Docker コンテナは呼び出し側が起動・停止する）
- **gmail**（MCP stdio。既存の Gmail サーバーの再利用）: `gmail send-email`（**1 コマンド = 1 MCP 往復**。**送信は副作用** — live は実メールが飛ぶ。**live は `--allow-send`（make は `ALLOW_SEND=1`）が必須** — 無ければ exit 2 で送らない。OAuth はサーバー側）
- **meta-page / meta-instagram**（HTTP。Meta Graph API v25.0。Facebook Page / Instagram）: `meta-page posts|post|post-insights` / `meta-instagram media|media-insights`（**1 コマンド = 1 往復**。`PAGE_TOKEN` / `USER_TOKEN` は別のトークン。**ページングは回さない**。csv は無い）
- **`auth google`**（ローカルコマンド。provider を呼ばない）: 対話専用の Google OAuth 同意フロー（ループバック + PKCE）でトークンファイルを書く。Google 5 送信元（gsc / ga4 / bigquery / calendar / apps-script）の credential をこのファイルでも渡せる（①`GOOGLE_TOKEN_FILE` → ②ソース既定パス（**存在的きのみ**。apps-script の既定名は `gas`）→ ③3 変数 = issue #51 の解決順）
- **site**（自サイトの死活監視。HTTP）: `site check --env local|dev|prod --target front|mypage|admin|all [--product-id ID]`（**1 コマンド = 面の URL 数 + ログイン段数（+ hop）の往復**。**判定を送信元定義に持つ唯一の送信元**。exit 0 / 1 / 2）
- **bigquery**（BigQuery の読み取り専用クエリ。HTTP 直叩き）: `bigquery query --sql SQL|@FILE [--dry-run] [--max-rows N] [--project ID]`（**1 コマンド = 認証 1 + クエリ 1 の 2 往復**。`SELECT` / `WITH … SELECT` だけ。**書き込みは無い**。**BigQuery は課金が発生しうる** — まず `--dry-run`。project は `--project` → `GOOGLE_CLOUD_PROJECT` → `GCLOUD_PROJECT`。`--replay` はネット・credential 無し）
- **calendar**（Google Calendar API v3。HTTP 直叩き）: `calendar list-calendars` / `list-events` / `get-event` / `create-event` / `update-event` / `delete-event`（**1 コマンド = 認証 1 + データ 1 の 2 往復**。**書き込み 3 つは副作用** — live の書き込みは owner 承認が前提。`update-event` は **PATCH = 1 往復**。`list-events` は**与えたフラグだけ**を送る（既定値は発明しない）。calendar id は `--calendar-id` → `GOOGLE_CALENDAR_ID` → `primary`。csv は無い。カセットは予定・参加者を含む — `.cassettes/` のみ・コミットしない。`--replay` はネット・credential 無し）
- **apps-script**（Google Apps Script API v1。HTTP 直叩き）: `apps-script create-project` / `get-project` / `get-project-content` / `update-project-content` / `list-project-versions` / `create-version` / `list-deployments` / `get-deployment` / `create-deployment` / `update-deployment` / `delete-deployment` / `run-script` / `list-processes`（**1 コマンド = 認証 1 + データ 1 の 2 往復**。**書き込み 7 つと run-script は副作用** — live は owner 承認が前提（**run-script は任意の関数の実行**）。script id は `--script-id` 必須（netloom は推測しない。`list-processes` のみフィルタとして任意）。`--files` / `--parameters` は JSON であることだけを見てそのまま送る（**update-project-content は全ファイル置換**）。`pageSize` / `manifestFileName` / `devMode` は**与えたときだけ**送る（既定値は発明しない）。csv は無い。カセットはソースコード・デプロイメント・プロセスを含む — `.cassettes/` のみ・コミットしない。`--replay` はネット・credential 無し）
- **youtube**（HTTP。YouTube Data API v3）: `youtube search` / `youtube videos`（**1 コマンド = 1 往復**。credential は query の `key` = `YOUTUBE_API_KEY`（psi / crux と同じ扱い。未設定なら 1 往復も送らず exit 2、`--replay` でも要る）。search は `part=snippet` + `type=video` 固定で **`publishedAfter` / `publishedBefore` の絶対日付範囲（年次スライス）を pass-through**（**Apify actor の rolling window では代替不可** = issue #29）、videos は `part=snippet,statistics,contentDetails` 固定（`publishedAt` / `statistics` の補完）。**quota は呼び出し側**: `search.list` は 100 units/回（`videos.list` は 1 unit）。**ページングは呼び出し側**（`--page-token` は pass-through。netloom は `nextPageToken` を追わない）。csv は無い。**キーはカセットの URL に残る** — `.cassettes/` のみ・コミットしない）
- **zenodo**（HTTP。Zenodo REST API。**読み取り 4 コマンド + 書き込み 7 コマンド**）: `zenodo record` / `record-versions` / `deposition` / `deposition-files` と、`deposition-create` / `deposition-update` / `deposition-delete` / `deposition-upload` / `deposition-file-delete` / `deposition-newversion` / `deposition-publish`（**1 コマンド = 1 往復**。credential は **`ZENODO_TOKEN` を `Authorization: Bearer` で送る 11 コマンド共通の 1 規則** — 未設定なら 1 往復も送らず exit 2、`--replay` は不要。id は書いたまま path に入る。`--sort` / `--size` は**与えたときだけ**載る pass-through。`--input` は `{"metadata": …}` に包んで送る metadata 文書、`--file` は multipart で送るファイル。**ページング・リトライ・レート制限の待ちは作らない**。**csv は無く、`deposition-files`（配列）と `deposition-delete`（文書無し）は `text` も無い**。**publish だけが `--allow-publish` 必須**（公開 DOI は取り消せない）— 下書きの書き込みに門は無い。カセットは record / deposition の本文とファイルの証跡（field / sha256 / size。**バイトもファイル名も残さない**）を持つ — `.cassettes/` のみ・コミットしない）
- **`cassette`**（ローカルコマンド。provider を呼ばない。カセットを読むだけ）: `cassette show --path FILE`（frame 一覧: seq / direction / method or status / url（**`key=` / `access_token=` の値は表示時だけ `[REDACTED]`** — カセットのバイトと replay の照合は変わらない）/ payload の sha256 とバイト数（`N B`）/ at。**本文は出さない**）と `cassette check --path FILE [--path FILE ...] [--env-file FILE]`（カセットに env の実値が残っていないかを機械検査。**名前と件数だけ**を出して exit 1（ヒット）/ 0（0 件）/ 2（credential が 1 つも無）/ 3（読めない）。読み取り専用 — 往復しない・書き換えない。env の解決は §7.5 と同じ。設計書 付録 A.28）
- **lighthouse**（ローカル計測。**exec。カセットなし**）: `lighthouse run --url URL --out DIR [--runs N] [--form-factor mobile|desktop] [--chrome-path PATH] [--lighthouse-version V]` — **1 コマンド = N 回の exec**（既定 5）。`run1.json` 〜 `runN.json` に **Lighthouse の生 JSON を置くだけ**（parse しない。中央値も判定もしない）。**カセットは無く `--cassette` / `--replay` / `--format` は exit 2** — 証跡は `--out`（新規は 0600）。`node` / `npx` は前提（無ければ 1 回も起動せず exit 127）。**psi / crux とは別測定系**（混ぜない = ローカル Lighthouse が正）。live は実測済み（2026-10-19: exit 0・約 21 秒・`run1.json` 921,296 B・0600）
- **playwright**（ローカルブラウザ。**exec。カセットなし**）: `playwright shot --url URL --out PATH [--full-page]` / `playwright html --url URL --out PATH` / `playwright eval --url URL --script FILE --out PATH` / **`playwright flow --script FILE --out PATH [--timeout SEC] [--playwright-version V] [--env-allow NAME,...]`** — `shot|html|eval` は **1 コマンド = 1 ページ読み込み = 1 回の exec**、**`flow` は 1 コマンド = 1 セッション = 1 ブラウザ起動 = N ページ読み込み**（起票元の 5 ステップのように複数ページにまたがる操作を検証する。**「1 コマンド = 1 往復」の明示的な例外** — カートは browser context を跨げば引けない = 設計 付録 A.35 追補 2）。出力は `--out`: **PNG / JS 実行後の DOM / 戻り値の JSON**（`eval` = `page.evaluate(string)` と同じ評価 / **`flow` = async function の本体を Node コンテキストで評価し `page` / `context` を渡す。return 値が JSON**。戻り値は解釈しない。スクリプトの内容はログに出ない）。**カセットは無く `--cassette` / `--replay` / `--format` は exit 2**。ブラウザは **Playwright 自身の Chromium** で、**インストールは呼び出し側**（`npx playwright install chromium`。無ければツールのエラー = exit 1。netloom は何もインストールしない）。**版とブラウザは対** — 既定はピン 1.63.0（= chromium-1243）、導入済みに合わせて選ぶなら `--playwright-version V`（`--lighthouse-version` と同じ pass-through）
- **devtools**（CDP の観測。**MCP stdio のまま**。カセットあり）: `devtools network|console|snapshot --url URL --out PATH [--format json|text|verbatim]` / `devtools trace --url URL --out DIR [--analyze]` — **1 コマンド = 決まった並びの `tools/call`**（1 セッション・1 `initialize`。network / console / snapshot = 2、trace = 3、`--analyze` = 4。**「1 コマンド = 1 `tools/call`」の唯一の例外** = 設計 付録 A.36）。答えは **`--out`**（network / console / snapshot = 1 ファイル、trace = DIR に `trace.json` + `--analyze` なら `insight.txt`。**stdout には出さない**。`--out` は必須 = exit 2。新規は 0600）。json（既定）= provider 自身の `structuredContent` をインデント 2 でそのまま / text = provider の描画 / verbatim = 生バイト。**csv は無く、trace は `--format` を持たない**。**`network --match REGEXP [--max-details N]`（issue #52）はマッチした要求の詳細を同一セッションで取得する**（呼び出し回数 = **2 + M**、M = min(マッチ数, `--max-details`)。既定 **10**。`--out` はリストのまま、**各詳細は `<out>-detail-<requestId>.json` に 1 文書ずつ**（provider の文書そのまま・詳細は常に json）。**reqid はセッション内の id** なのでリストしたセッション内で取る（別コマンドの id では引けない = 実測 2026-10-20 に exit 1 で確認。`request` コマンドは削除）。詳細の答えは POST ボディ・Cookie / Set-Cookie を含む。マッチ 0 件でも exit 0）。**カセットは普通に記録する**（`--replay` は並びの順に照合。同じ request の反復でも壊れない）。**`npx` / `node` が無ければ 1 往復もせず exit 127**、`isError` / JSON-RPC error = exit 1。**Chrome は `chrome-devtools-mcp` が自分で起動する**（無ければツールのエラー = exit 1。netloom は導入も分類もしない）。**サーバーは `--no-page-id-routing` で起動する**（既定の `pageIdRouting` は全 page-scoped ツールの schema に必須の `pageId` を足す — 渡さないと `navigate_page` が isError。2026-10-19 の live 実測 = A.36 判断 D23）。**計測ではない**（PageSpeed の数値と混ぜない = 観察の道具）。live は親が実行する（2026-10-19 の 1 回目で欠陥を発見・修正済み。修正後の再実行待ち）
- **`env check`**（ローカルコマンド。provider を呼ばない。往復しない・カセットも作らない）: `env check [--source ID]... [--env local|dev|prod] [--format text|json] [--env-file FILE[:FILE…]]` — **実行の前に前提を確かめる**。netloom が読む名前ごとに「設定されているか / どこから来たか（プロセス env / どのファイル）/ 誰が読むか」を出し、**env ファイルが定義しているのに netloom が読まない名前**（typo・残骸）も出す。**値は絶対に出ない**（§7.4。ログに貼れる）。`--source` で絞ると門になり、その送信元が必要とする名前が（代替を含めて）欠けていれば exit 1。設計書 付録 A.30。**空値（`KEY=`）は `empty` と表示され、門では missing とみなす**（issue #56。「門が通るのに実行が失敗する」をなくすため。値は出さない）。**`<.env>` が `.env.d/` の同名の定義を隠しているとき**（§7.5 の解決順の帰結）は行末に `shadowed by: <ファイル>` を足す（明示リスト `NETLOOM_ENV_FILE` / `--env-file` では出さない = それは「そのリストだけ」の解決）。

---

# このスキルの配布（CI での drift 検出と複数 checkout への一括配布）

このスキル自身は netloom のバイナリに埋め込まれている（正本は `internal/usecase/skill/netloom/SKILL.md`。配布済みコピーが `.github/skills/netloom/SKILL.md`）。**手でコピーしない**。古いコピーは `netloom skill check` の exit code で検出できる（一致 = 0 / 不一致 = 1 / ファイルが無い・読めない = 3）。

## CI に 1 ステップ入れて drift を検出する

```yaml
# GitHub Actions（例。private module なので GOPRIVATE と取得の認証が要る）
- run: go install github.com/routeflags/netloom/cmd/netloom@latest
- run: netloom skill check --path .github/skills/netloom/SKILL.md
```

手元（`make install-go` 済み）は同じ 1 行:

```sh
netloom skill check --path .github/skills/netloom/SKILL.md
```

## 複数 checkout への一括配布

```sh
netloom skill install --scan <parent-dir>                  # プレビュー（既定。何も書かない）
netloom skill install --scan <parent-dir> --write          # 一致は UP-TO-DATE、異なるコピーは拒否（exit 1）
netloom skill install --scan <parent-dir> --write --force  # 異なるコピーも置き換える
netloom skill install --scan <parent-dir> --depth 2        # 深さ上限を明示（既定はリポジトリで 6 段。0 は親ディレクトリ自身のみ）
```

- `<parent-dir>` **自身とその配下**を**辞書順**に走査し、`.github/skills/netloom/SKILL.md` を持つリポジトリだけを対象にする（コピーが無いリポジトリには置かない — 新規導入は `--to`）。**レポジトリの配下は歩かない**（prune）: 各ディレクトリを Lstat 1 回で「レポジトリか」だけを確かめ、あれば記録して配下は列挙しない。**`.git` の状態（欠損・ファイル・ディレクトリ）には一切依存しない**、シンボリックリンクも辿らない。深さは**リポジトリで 6 段**まで（`--depth N` で変更可。`.delta/worktrees/<id>/<repo>` の 4 段は届く）。**リポジトリの checkout の中の入れ子のリポジトリは見つからない**（prune の帰結）
- **Delta の worktree も見つかる**（issue #44）: Delta の worktree は `<repo>/.delta/worktrees/<id>/<repo>` という**入れ子の checkout** なので、リポジトリを記録した後も**その `.delta/worktrees/` の直下だけは訪問**する（worktree の id とその下の checkout を Lstat 1 回ずつ。中は歩かない）。例外は `.delta/worktrees` だけ（一般の入れ子は従来どおり見つからない）。`--depth` の上限は worktree にも効く
- **部分を完全として読ませない**: 深さ上限で切った走査は末尾に `NOT VISITED: N directories (--depth M; raise --depth to look further)` の 1 行を出す（未訪問 0 件なら出ない。exit code は変わらない）
- 書き込みの規則（プレビュー既定・`--force` 無しの拒否・`UP-TO-DATE` は触らない）は単一 `--to` と同じ。報告は対象ごとに 1 行（`TARGET:` + `STATUS:`。`UP-TO-DATE` / `INSTALLED` / `PREVIEW` / `REFUSED` / `FAILED`）、0 件は `NO TARGETS:` の 1 行で exit 0。どれか拒否 = exit 1、I/O 失敗 = exit 3（最も重いもの。**実際に歩いたディレクトリ**のエラーに限る — レポジトリの中身は歩らない）。`--to` と `--scan` は併用できない（exit 2）。`--depth` は `--scan` のみ（`--to` 併用・負値は exit 2）

---

# env check（実行の前に前提を確かめる。ローカルコマンド）

## いつ使うか（トリガー）

- 「この run の前提（credential・root・環境別の名前）が揃っているか」を**実行の前に一度**確かめたい
- env ファイルの **typo・残骸**を見つけたい（**netloom が読まない名前**がそのまま見える）
- 送信元を 1 つに絞って「**その送信元が動くか**」を門にしたい（CI・自動化のゲート）
- 「この変数の値がどこから来ているのか」（プロセス env か、どの env ファイルか）を知りたい

## 実行（往復しない・カセットも作らない・値は出ない）

```sh
# cwd（= 実行するディレクトリ）の env の一覧。報告のみ（exit 0）
make env-check
bin/netloom env check

# 送信元を絞る = 門。その送信元が必要とする名前が欠けていれば exit 1
make env-check ENV_SOURCE=gsc,news
bin/netloom env check --source news --env dev

# 機械可読（name / set / origin / read_by / gate）。スクリプトの起動時チェックに
make env-check ENV_FORMAT=json | jq -e '.gate.ok'
bin/netloom env check --source gsc --format json

# 環境ファイルを明示（既定は §7.5 の解決。`: ` 区切りで複数）
bin/netloom env check --env-file .env.d/issues.env
```

- **cwd の env ファイルを実際に読んで**答える（`NETLOOM_ENV_FILE` があればそのリストだけ / なければ `<cwd>/.env` と `<cwd>/.env.d/*.env` を**両方**読む。§7.5 と同じ解決。再帰探索はしない）。**run を実行するディレクトリで実行する**
- `--env local|dev|prod`（既定 `dev`）は **site と EC-CUBE の環境別の名前**の解決に使う（例: dev なら `EC_DEV_ADMIN_ROUTE` → `ECCUBE_ADMIN_ROUTE` の順）
- **値は絶対に出ない**（名前・状態・出所・パスだけ。§7.4）。出力はログに貼れる
- **何も設定されていないときは、意味が 1 行出る**: `result: no variable any source reads is set — every source that needs a credential or a root refuses before it sends (exit 2); a source that reads no variable still runs`（読んだファイル 0 件・設定された名前 0 件は件数としても見える。判定は**送信元が読む名前**に限る — シェルが必ず持つ `PATH` / `HOME`（`npx` / `auth google` が読む）は数えないので、実運用のシェルでも出ます）

## 出力（text。既定）

```
env files (1 read): .env.d/issues.env
variables (52 — 4 set, 48 unset — name / state / origin / read by):
  SEO_API_KEY                 set    .env.d/issues.env  news, article, cache, contact, landing-page
  GOOGLE_CLIENT_ID            unset  -                  gsc, ga4, bigquery, calendar, apps-script
  APIFY_TOKEN                 set    environment        apify
unknown (1 — the env files state them, and netloom reads none of them):
  OLD_API_TOKEN               .env.d/issues.env
sources that read no variable: google-trends, openseo, gmail
gate (--source): 2 of 2 sources are missing a needed name — exit 1
  gsc    missing  GOOGLE_TOKEN_FILE or GOOGLE_CLIENT_ID + GOOGLE_CLIENT_SECRET + GOOGLE_REFRESH_TOKEN (a live run exchanges this credential for an access token; --replay exchanges nothing)
  news   ok       (satisfied by SEO_API_KEY, EC_DEV_BASE_URL, HTTP_BASIC_AUTH_USER, HTTP_BASIC_AUTH_PASS)
```

- `origin` は `environment`（プロセスの環境変数）か、読んだ env ファイルの名前。**プロセス env が常に勝つ**（§7.5）
- **代替（or）は誤警報を出さない**: Google の credential は `GOOGLE_TOKEN_FILE` **または** 3 変数、bigquery の project は `GOOGLE_CLOUD_PROJECT` / `GCLOUD_PROJECT` のどちらか、site の名前は環境別名 → 旧名の順。任意のもの（会員の pair・`GOOGLE_CALENDAR_ID`・`GOOGLE_CLOUD_QUOTA_PROJECT`・`SSH_ALIAS`）は出るが**門では要求しない**

## exit code

| exit | いつ |
|---|---|
| 0 | 報告した（`--source` 無し）、または選んだ送信元の前提がすべて揃った（何も設定されていない環境でも、報告のみなら 0 — 意味は `result:` の 1 行で読む） |
| 1 | `--source` で絞った送信元に**欠けている名前**がある（そもそも往復しないので「1 往復も送らない」は自明） |
| 2 | 引数（verb 無し・未知の verb / 未知の `--source` / 語彙外の `--env`・`--format` / その送信元が serve しない `--env`） |
| 3 | env ファイルが読めない（§7.5 の fail closed と同じ） |

---

# Google Trends（5 コマンド）

## いつ使うか（トリガー）

- 「Google Trends のデータを取って」「〈語〉の検索推移を見て」
- 「〈語 A〉と〈語 B〉を検索ボリュームで比較して」
- 「検索興味度を期間指定で」「Google トレンド」

## 前提

- netloom リポジトリの root で作業する（`make build` で `bin/netloom` を作る）。PATH に置くなら
  `make install`（`bin/netloom` へのシンボリックリンク。開発用）か `make install-go`（`go install` で実体。恒久版）で、`make update` が入れ替える
- 入っている版は `netloom version`（`--version` / `-v` も同じ）で確認できる。**版と送信元の確認は `netloom version --json`**（1 行の JSON。`sources` は常に含まれる。`--sources` は 2 行目に id を並べる。同時指定は exit 2）
- live 実行には Node / `npx` が必要（`npx --version` で確認）。**API キーは不要**
- ネットワークが無い・再現したいときは `REPLAY=<カセット>` を使う

## 実行（既定は live）

```sh
# 1 語の推移（既定: live / 構造化 json）
make trends KEYWORD="CBD オイル"

# 期間と出力形式を指定（ファイルへ）
make trends KEYWORD="CBD オイル" TIMEFRAME="today 5-y" FORMAT=csv OUT=/tmp/cbd.csv

# 2–5 語の相対比較（1 回の呼び出し。同一 run 内だけ共通スケール）
make compare TERMS="CBD オイル,CBN オイル"
make compare TERMS="CBD オイル,CBN オイル,カンナビノイド" FORMAT=text

# 関連クエリ（TOP / RISING）・本日のトレンド・地域別の興味度（issue #27。csv は無い）
make trends-related KEYWORD="CBX"        # サーバーの schema は term（1 語）
make trends-trending                      # TODAY のトレンド（GEO=JP。KEYWORD も TIMEFRAME も取らない）
make trends-region  KEYWORD="CBX"        # 地域別（スコアは provider の指数）
```

| 変数 | 既定 | 値 |
|---|---|---|
| `KEYWORD` | （必須。`trends` / `trends-related` / `trends-region`） | 検索語 1 つ（`--keyword` または `--term`） |
| `TERMS` | （必須。`compare`） | 2–5 語のカンマ区切り |
| `GEO` | `JP` | ISO 3166-1 alpha-2（空 = 全世界。**`trends-trending` は 2 文字が必要**） |
| `TIMEFRAME` | `today 12-m` | `today 1-m`（30日）/ `today 3-m`（90日）/ `today 12-m` / `today 5-y`（5年）**この 4 語彙のみ**（`trends-trending` は取らない） |
| `FORMAT` | `json` | `json` / `csv` / `text` / `verbatim`。**`trends-related` / `trends-trending` / `trends-region` は `json` / `text` / `verbatim` の 3 つ**（`csv` を渡すと exit 2） |
| `OUT` | （stdout） | 出力ファイル |
| `REPLAY` | （live） | カセットからオフライン再現 |

- `make help` が全ターゲットを表示。stdout は**データのみ**（ビルド表示は stderr）
- 実行ごとに往復が `.cassettes/<UTC>-google-trends-….jsonl` に追記される（stderr にパスが出る）
- バイナリを直接叩く場合は `bin/netloom google-trends interest-over-time --keyword …` /
  `bin/netloom google-trends compare-terms --terms …` / `bin/netloom google-trends related-queries --term …` /
  `bin/netloom google-trends trending-now --geo JP` / `bin/netloom google-trends interest-by-region --term …`（フラグは `--help`）
- `trending-now` は **geo だけ** を取る（サーバーの schema に timeframe も term も無い。付けると exit 2）

## 出力形式（`FORMAT`）

| 値 | 内容 | 使いどころ |
|---|---|---|
| `json`（既定） | `{source, tool, geo, timeframe, terms:[{term, average?, series:[{date,value}]}]}` | エージェント / プログラム（jq でそのまま扱える） |
| `csv` | `term,geo,timeframe,date,value` | 表・スプレッドシート |
| `text` | provider の表をそのまま（エスケープなし） | 人が読む |
| `verbatim` | 受信した生バイト | 生データの確認（証跡用） |

`related-queries` / `trending-now` / `interest-by-region` の `json`（issue #27。サーバーが返す text から読む。述べていないフィールドは足さない）:

| コマンド | `json` の形 |
|---|---|
| `related-queries` | `{source, tool, geo, timeframe, term, top:[{query, value}], rising:[{query, value}]}` — **`value` は印字された文字列**（数値化は呼び出し側） |
| `trending-now` | `{source, tool, geo, date, trends:[{query, traffic, article?:{source, title}}]}` — 記事は先頭 1 件だけ（無ければ省略） |
| `interest-by-region` | `{source, tool, geo, timeframe, term, regions:[{region, code, score}]}` — `score` は整数（単位は provider の指数。範囲は検査しない） |

空の答え（サーバーの 1 文 `No related queries found for this term.` など）は空の配列で、**失敗ではない**（exit 0）。

`average` は **provider が返したときだけ**入る（`interest_over_time` には無い。計算で埋めない）。

## 値の読み方（誤読しやすい点）

- **0–100 の相対指数**。絶対検索数ではない（系列内の最大が 100）
- **run をまたいだ比較はできない**。語の比較は `compare` の 1 回の呼び出し（共通スケール）だけ
- **バケット粒度は timeframe で違う**（Google Trends 側の決定。キーワードには依らない。netloom は正規化しない）:
  `today 1-m` / `today 3-m` は**日次**（1 日 1 点: 実測 1-m=31 点 / 3-m=93 点）、`today 12-m` / `today 5-y` は
  **週次・日曜起点**（実測 12-m=53 点 / 5-y=262 点。2026-10-19 実測、設計 A.1）。週次を前提にした parse は
  **12-m / 5-y でのみ一致**する — 粒度差の吸収は呼び出し側の仕事
- `value: 0` は「そのバケットに検索が無かった」で、**収集失敗ではない**
- `timeframe` は**要求条件**。観測された範囲ではない。`today 5-y` は実行時刻基準のローリング 5 年
- **関連クエリの `value` はサーバーが印字した文字列**（rising の値は数値とは限らない）。`trending-now` の `traffic` も同じで、**数値化は呼び出し側**
- **`interest-by-region` の `score` は provider の指数**（行は provider が value の降順に並べ、**上位 30 件**に切ったもの — netloom は並べ替えも切り捨てもしない）

## 証跡とオフライン再現

```sh
# 記録済みカセットから再生（ネットも npx も使わない。request が一致しなければ exit 1）
make trends KEYWORD="CBX リキッド" REPLAY=.cassettes/20261017T144703Z-google-trends-interest-over-time-cbd-オイル.jsonl FORMAT=csv
```

- カセットは**追記のみ。編集・削除しない**（証跡）。**作成時の mode は 0600**（PII・売上・キーを含みうるため。env / トークンファイルと同じ姿勢。既存のカセットの mode は変えない）
- 記録前にレダクトされる（秘密情報の実値は入らない）
- `raw/` にカセットを置かない（呼び出し側の `raw/` は取得データ専用）
- 再現は**記録と同じ request**（keyword/terms・geo・timeframe）でのみ成功する

## 失敗の見分け

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 成功 | — |
| 1 | 失敗・拒否（replay 不一致、ツールがエラー、解釈できない応答） | stderr の 1 行を読む。応答形が変わった可能性は設計の付録 A.7 を確認 |
| 2 | 引数・語彙（timeframe 語彙外、terms が 1 語/6 語、`--term` 欠落、3 コマンドの `--format csv`、`--replay` と `--cassette` 併用） | 引数を直す |
| 3 | I/O（`--out` に書けない） | パスを直す |
| 124 | timeout（既定 300 秒） | 再実行、または owner に相談 |
| 127 | `npx` 不在 | Node を導入する |

### 失敗を追う（カセットを見る）

実行のたびに往復が `.cassettes/<UTC>-….jsonl` に記録される（**失敗も記録される**）。原因はこのカセットで追える:

```sh
C=$(ls -t .cassettes/*.jsonl | head -1)
jq -r '[.seq,.direction,(.method//.status//.stream//""),(.url//"")]|@tsv' "$C"   # frame 一覧
jq -r 'select(.direction=="recv")
  | (.payload | if type=="string" then (fromjson? // .) else . end) as $p
  | ($p.result.content[0].text // ($p.result.data | arrays | tostring)
     // ($p.data | objects | tostring) // $p.error.message // empty)' "$C"   # 応答 / 失敗理由
grep -nE 'Bearer [^[]|apify_api_[A-Za-z0-9]' "$C"            # 実値の形を探す（Authorization という名前と [REDACTED] が残るのは正しい）
```

HTTP の `recv` の `payload` は、コンパクトでバイトが変わらない JSON なら値のまま、整形済み JSON・CSV なら
**JSON 文字列**で入っている（`--format verbatim` / `--as csv` はどちらでも元バイトに戻る）。
`make` 経由の exit 2 は make 自身のもので、ツールの exit code は `bin/netloom …; echo $?` で確認する。詳しくは README §デバッグ。

**429（provider 側の制限）** は数分置いて再実行するか、過去の成功カセットを `--replay` する。
自動リトライはしない（決定どおり）。

---

# Apify（6 コマンド）

Apify は **VCR を通すだけの薄いプロキシ**。allow-list・入力スキーマ検証・コスト上限・ポーリングは
**無い**。actor は任意の ID、Apify が返したエラーはそのまま返る。

## いつ使うか（トリガー）

- 「YouTube / X / TikTok / Instagram の動画・投稿を Apify で集めて」
- 「〈採用済み actor〉を実行して、その dataset を読んで」
- 「Apify の run が終わったか」「いくらかかったか」（`run-status`）
- 「この actor の入力の形（スキーマ）を知りたい」 — **2 往復**: `actor` で `taggedBuilds.latest.buildId` を読み → `build` で `actorDefinition.input` を読む（**actor endpoint は `inputSchema` を返さない**。2026-10-19 実測）

## 前提: `APIFY_TOKEN`

- 値は**環境変数**で渡す。netloom は `APIFY_TOKEN` を読んで `Authorization: Bearer …` を組む
- env ファイルは**ワークスペース外**に置く（JCT のスクリプトは `APIFY_ENV`。この環境の既定は
  `/Users/bookair18/OS/media/06_symphony/symphony_workspaces/.env.d/apify.env`）
- **コミットしない**。`chmod 600` にする。値は stdout / stderr / カセットのどこにも出ない
- 未設定なら netloom は 1 往復も送らず exit 2（リクエストも課金も発生しない）

```sh
# 例: env ファイルを読んでから実行（JCT は src/collection/run-with-env.sh <env-file> <command> が担う）
set -a; source "${APIFY_ENV:-/Users/bookair18/OS/media/06_symphony/symphony_workspaces/.env.d/apify.env}"; set +a
```

## 実行（1 コマンド = 1 往復 = カセット 1 往復）

```sh
# 1) actor を実行（入力は JSON 文字列 or @FILE。actor は任意の ID）
make apify-run ACTOR=gJvjeCYNraSfhIaNd INPUT='{"search_term":"CBXリキッド","max_videos":5}'
#    → {"data":{"id","status","defaultDatasetId",…}} が返る（既定 json は **provider の封筒を保つ**。FORMAT=text で要約 = 名前のある member は封筒 1 段下（data）でも同じ名前で出る）
#    → defaultDatasetId の行を 2) に渡す。WAIT=SEC は waitForFinish（既定は TIMEOUT と同じ値）

# 2) dataset の items を取る（provider の表現のまま）
make apify-dataset DATASET=<defaultDatasetId> LIMIT=5
make apify-dataset DATASET=<defaultDatasetId> LIMIT=5 ITEM_FORMAT=csv OUT=/tmp/items.csv   # CSV は Apify のバイトそのまま

# 3) run の状態と課金
make apify-run-status RUN=<runId> FORMAT=text
#    → status: SUCCEEDED / usageTotalUsd: 0.0026

# 4) actor のメタデータ（issue #30。読み取りのみ = 課金なし）
bin/netloom apify actor --actor <actorId> [--format json|text|verbatim]
#    GET https://api.apify.com/v2/acts/<actorId>
#    → {"data":{"id","name","username","taggedBuilds",…}}。FORMAT=text は id / name / username の要約
#    **この応答に inputSchema は無い**（2026-10-19 実測）。build の id は data.taggedBuilds.latest.buildId

# 5) actor build の文書（issue #30 増分。読み取りのみ = 課金なし）
bin/netloom apify build --build-id <buildId> [--format json|text|verbatim]
#    GET https://api.apify.com/v2/actor-builds/<buildId>
#    → スキーマは **actorDefinition.input**（本物の JSON Schema。実測した actor では properties 42 個）。
#      旧 inputSchema も在るが**文字列**（netloom は JSON に開かない — 受信のまま返す）
#    → **`jq '.data.inputSchema'` を actor の応答にかけても常に null**（この 2 往復が正しい経路）
#    → 使い方: actor の taggedBuilds.latest.buildId をここに渡す（スキーマを読むのは 2 往復）
#    → FORMAT=text は id / status / actId の要約

# 6) key-value store の 1 レコード（issue #30。読み取りのみ = 課金なし）
bin/netloom apify key-value-store --store-id <storeId> --key <key> [--format json|verbatim]
#    GET https://api.apify.com/v2/key-value-stores/<storeId>/records/<key>
#    → 応答は**レコードの本文そのもの**（{"data":…} の封筒ではない。Content-Type は保存された型）
#    JSON レコードは --format json（既定）が整形 / --format verbatim は受信バイト（改行を足さない）
```

make の変数名は CLI のフラグ名とは少し違う（`FORMAT` / `CASSETTE` / `OUT` / `REPLAY` は Google Trends と共通）:
`ACTOR`=`--actor` / `INPUT`=`--input` / `WAIT`=`--wait` / `DATASET`=`--dataset-id` / `LIMIT`=`--limit` /
`ITEM_FORMAT`=`--as` / `RUN`=`--run-id` / `TIMEOUT`=`--timeout`。
バイナリを直接叩くこともできる（`bin/netloom apify run --actor … --input …`）。
**`actor` / `build` / `key-value-store` には make ターゲットが無い**（バイナリを直接叩く。issue #30）。

| フラグ | 意味 |
|---|---|
| `--actor ID` | 実行する actor（**任意の ID**。allow-list も name→ID 変換も無い） |
| `--input JSON` \| `@FILE` | run の入力（JSON であることだけを見る。スキーマは検証しない） |
| `--wait SEC` | `waitForFinish`。既定は `--timeout` と同じ値。**ポーリングはしない**（待つか待たないかだけ） |
| `--dataset-id ID` | dataset の ID（`apify run` の `defaultDatasetId`） |
| `--limit N` | items の上限（provider に渡すだけ。netloom は切り詰めない） |
| `--as json\|csv` | dataset の返り値（既定 `json` = items を整形、`csv` = Apify の CSV バイトそのまま）。**`--as` が第一の綴り**。`--format json\|csv` はその**別名**（同じ 1 つの選択の 2 綴り: 同じ値なら併用可、違う値なら exit 2。値は出力されない） |
| `--run-id ID` | `run-status` が見る run |
| `--build-id ID` | `build` が見る actor build（任意の ID。`actor` の `data.taggedBuilds.latest.buildId` から取る。issue #30 増分） |
| `--store-id ID` | `key-value-store` が見る store（任意の ID。issue #30） |
| `--key KEY` | `key-value-store` のレコードのキー（そのまま path に入る。issue #30） |
| `--format json\|text\|verbatim` | `run` / `run-status` / `actor` / `build` の出力（既定 `json` = 応答を整形、`text` = 1〜3 行の要約、`verbatim` = 受信バイト）。**dataset では `--format` は `--as` の別名（`json\|csv`）**。run / run-status に csv 別名は無い（provider 側に item format の選択が無い） |
| `--format json\|verbatim` | `key-value-store` の出力（既定 `json`）。**`text` は無い**（レコードの形は保存した側次第 — 存在しない member を並べる要約は嘘になる） |
| `--out` / `--cassette` / `--replay` / `--timeout` | Google Trends と同じ意味（`--timeout` は HTTP の context に当たる） |

### 採用済み actor の例（**例示であって制限ではない**）

JCT `config/collectors.json` と各 skill に実在する 5 件。**netloom は任意の ID を受け付ける**ので、
新しい actor を使うのに netloom の変更は要らない（どの actor を採用するかは呼び出し側が決める）。

| 用途 | actor ID（例） |
|---|---|
| YouTube 検索（`youtube-search`） | `gJvjeCYNraSfhIaNd` |
| YouTube スクレイプ（`youtube-scraper`） | `h7sDV53CddomktSi5` |
| X 検索（`x-search`） | `cPYLH3QT9GyzKhB4S` |
| TikTok 検索（`tiktok-search`） | `jQfZ1h9FrcWcliKZX` |
| Instagram 検索（`instagram-search`） | `TxU0ZBQIHdR20dr9C` |

- 入力の形（`search_term` / `max_videos` / `dateFilter` など）は**各 actor の skill / Actor ページ**で確認する
  （netloom は検証も補完もしない）
- actor ID はそのまま URL の path に入る（`user~actor` 形式も可）。`--build-id` / `--store-id` / `--key` も同じ（**エスケープ・検証なし**。値の `?` / `#` 以降は送られない — 設計 A.9 判断 D6）

## 課金の確認

- 実行前に: Actor ページ / JCT の skill にある単価。netloom は**コスト上限を持たない**
- 実行後に: `make apify-run-status RUN=<id> FORMAT=text` の `usageTotalUsd`
- `apify run` の応答（`status` / `usageTotalUsd`）はカセットにも残る（後から検算できる）

## 失敗の見分け（Apify）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 2xx | — |
| 1 | 4xx / 5xx / 接続失敗 / DNS / TLS（stderr に `HTTP <status>` + 応答本文の先頭）、**JSON でないレコードを `key-value-store --format json` で読んだ**（stdout には何も出ない → `--format verbatim` で読む）、**`build --format text` で `id` / `status` / `actId` が 1 つも無い応答** | 本文は出力されない。`--cassette` を見れば応答全体が残っている。引数（actor ID・build ID・store ID・key・入力）を確認 |
| 2 | 引数・設定（`--actor` / `--input` / `--build-id` / `--store-id` / `--key` の欠落（空白のみも同じ）、JSON でない入力、`APIFY_TOKEN` 未設定、`--replay` と `--cassette` の併用、**`key-value-store --format text`**） | 引数と env を直す（拒否された run は **1 往復も送らず、カセットも作らない**） |
| 3 | I/O（`--out` / カセット / `@FILE` が読めない） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | run は Apify 側で続いている可能性がある。`run-status` で確認する |

## 証跡とオフライン再現（Apify）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-apify-run-<actor>.jsonl）
make apify-run ACTOR=gJvjeCYNraSfhIaNd INPUT=@input.json

# 同じ request で再生（ネットも credential も使わない。method + url + payload が一致しないと exit 1）
make apify-dataset DATASET=<id> ITEM_FORMAT=csv REPLAY=.cassettes/20261017T150000Z-apify-run-gjvjecynrasfhiand.jsonl

# actor / build / key-value-store の既定カセット名（issue #30）: actor は actor id、build は build id、KVS は store と key の両方
#   .cassettes/<UTC>-apify-actor-<actor>.jsonl
#   .cassettes/<UTC>-apify-build-<build>.jsonl
#   .cassettes/<UTC>-apify-key-value-store-<store>-<key>.jsonl
bin/netloom apify key-value-store --store-id <storeId> --key <key> --replay .cassettes/20261019T120000Z-apify-key-value-store-store-1-input.jsonl
```

- カセットには `send`（method / url / headers / payload）と `recv`（status / payload）の 2 行
- `Authorization` は記録前に `[REDACTED]` になる（実値は入らない）
- 4xx / 5xx を記録したカセットを再生すると、**同じ失敗**になる（成功に偽装されない）
- カセットは**追記のみ**。編集・削除しない。`raw/` に置かない
- **`key-value-store` の応答はレコードの本文**（`{"data":…}` の封筒ではない）。**JSON でないレコードは `--format json` が exit 1**、`--format verbatim` が受信バイトそのまま（改行も足さない）

---

# X API v2（3 コマンド）

X も **VCR を通すだけの薄いプロキシ**。allow-list・field 名の検証・ページングの自動化・リトライ・
レート制限の待ち・費用上限は**無い**。検索式・期間・page token・field はそのまま送られ、X が返した
エラーはそのまま返る。**live は owner 決定で禁止中**（当面 0 円。JCT `ISS-20261015-COL-030`）。

## いつ使うか（トリガー）

- 「X（旧 Twitter）の投稿を公式 API で集めて」（スクレイピング actor ではなく）
- 「この検索式の投稿を直近 7 日 / 全期間で」（`search-recent` / `search-all`）
- 「この投稿 ID の本文・日時を取って」（`tweet`）
- 「X の取得を request-only の証跡付きで再現したい」（カセットの `--replay`。ただし Request-only VCR の分離は未実装、下の「まだ無いもの」参照）

## 前提: `X_BEARER_TOKEN`

- 値は**環境変数**で渡す（app-only の Bearer）。netloom は `X_BEARER_TOKEN` を読んで `Authorization: Bearer …` を組む
- env ファイルは**ワークスペース外**に置く（`APIFY_ENV` と同じ扱い。**このマシンには X の env ファイルが無い**）
- **コミットしない**。`chmod 600` にする。値は stdout / stderr / カセットのどこにも出ない
- 未設定なら netloom は 1 往復も送らず exit 2
- **live request は owner 承認まで禁止**（JCT `ISS-20261015-COL-030` §3.4）。今できるのはテスト（偽 X API）とカセットの `--replay`

## 実行（1 コマンド = 1 往復 = カセット 1 往復）

```sh
# 1) 直近 7 日の検索（search-recent）
make x-search-recent QUERY='CBX lang:ja' MAX_RESULTS=100 TWEET_FIELDS=created_at,public_metrics
#    GET https://api.x.com/2/tweets/search/recent?query=…。既定 json。FORMAT=text で result_count・newest_id・oldest_id・next_token

# 2) 全期間の検索（search-all。上位 tier が無いと provider が 403 を返す）
make x-search-all QUERY='CBX lang:ja' START_TIME=2025-01-01T00:00:00Z END_TIME=2025-02-01T00:00:00Z
#    ページングは回さない: NEXT_TOKEN=<前の meta.next_token> で次の 1 往復を自分で実行する

# 3) 投稿 1 件
make x-tweet ID=<post-id> TWEET_FIELDS=created_at,text
#    FORMAT=text で id: / created_at: / text: の要約
```

make の変数は `QUERY` / `MAX_RESULTS` / `START_TIME` / `END_TIME` / `NEXT_TOKEN` / `TWEET_FIELDS` /
`USER_FIELDS` / `EXPANSIONS` / `ID`（`FORMAT` / `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` は共通）。
バイナリを直接叩く場合は `bin/netloom x search-recent --query …`。

| フラグ | 意味 |
|---|---|
| `--query TEXT` | search-recent / search-all: 検索式（必須。そのまま送る。`since:` / `until:` もそのまま） |
| `--max-results N` | search: `max_results`（0 以下は exit 2。X の 10〜100・10〜500 は netloom は検証しない） |
| `--start-time` / `--end-time` | search: `start_time` / `end_time`（RFC3339 のまま。解釈しない） |
| `--next-token TOKEN` | search: `next_token`（**ページングは回さない**） |
| `--tweet-fields` / `--user-fields` / `--expansions` | search / tweet: field セレクタ（カンマ区切りのまま。未知の名前もそのまま） |
| `--id ID` | tweet: 投稿 ID（必須） |
| `--format json\|text\|verbatim` | 出力（既定 json = 応答を整形、text = 要約、verbatim = 受信バイト）。**csv は無い** |
| `--out` / `--cassette` / `--replay` / `--timeout` | 他と同じ意味（`--replay` と `--cassette` は併用しない） |

## 出力の読み方

- `json` は X の生構造のまま（検索 = `{"data":[…],"meta":{…}}`、投稿 = `{"data":{…}}`）。**0 件（`result_count: 0`）は失敗ではない**
- `text` は search = `result_count` / `newest_id` / `oldest_id` / `next_token`、tweet = `id` / `created_at` / `text`。**応答に無い項目は出ない**（1 つも無ければ exit 1）
- **値を解釈しない**: 件数・期間・言語の判定は呼び出し側。`next_token` を渡して続きを取るのも呼び出し側

## 失敗の見分け（X）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 2xx（0 件の検索を含む） | — |
| 1 | 4xx / 5xx（**429 を含む**。リトライしない）/ 接続失敗 / replay 不一致（stderr に `HTTP <status>` + 本文先頭） | 本文は出力されない。`--cassette` を見れば応答全体が残っている。403 なら search-all の tier を確認。429 は数分置いて再実行 |
| 2 | 引数・設定（`--query` / `--id` 欠落、`--max-results <= 0`、`X_BEARER_TOKEN` 未設定、`--replay` と `--cassette` の併用） | 引数と env を直す |
| 3 | I/O（`--out` / カセット） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | 再実行、または owner に相談 |

## 証跡とオフライン再現（X）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-x-<command>-<target>.jsonl）
make x-search-recent QUERY='CBX lang:ja' MAX_RESULTS=100

# 同じ request で再生（ネットも token も使わない。method + url + payload が一致しないと exit 1）
make x-search-recent QUERY='CBX lang:ja' MAX_RESULTS=100 REPLAY=.cassettes/20261018T120000Z-x-search-recent-cbx-lang-ja.jsonl FORMAT=text
```

- カセットには `send`（method / url / headers。GET なので payload は無い）と `recv`（status / payload）の 2 行
- `Authorization` は記録前に `[REDACTED]` になる（実値は入らない）
- 4xx / 5xx を記録したカセットを再生すると、**同じ失敗**になる（成功に偽装されない）
- **X のカセットは応答本文に投稿データ（本文・ID・`next_token` 原値）を含む**。**コミットしない**。`raw/` に置かない。共有・貼り付けもしない（JCT `ISS-20261015-COL-030` §4.1: X 元投稿データをリポジトリに保存しない）
- カセットは**追記のみ**。編集・削除しない

---

# GA4（3 コマンド）

GA4 も **VCR を通すだけの薄いプロキシ**。dimension / metric の allow-list・ページングの自動化・
リトライ・レート制限の待ち・値の解釈は**無い**。相手は **Google Analytics Data API**（`https://analyticsdata.googleapis.com/v1beta`）で、
**1 コマンド = 認証 1 + データ 1 の 2 往復（カセット 4 frame）**。credential は Google の
refresh grant（netloom 自身がトークンを交換する。GSC と同じ道）。

> 0.4.0 までは既存の GA4 MCP サーバー（`ga4_mcp_server.py`）を wrapper 越しに実行していた。
> その配線はこのマシンの絶対パス（wrapper / env ファイル / venv python）を含む唯一の箇所だったので、
> 送信元を HTTP に移して消した。**当時の MCP カセットは新しい実装では再生できない**（証跡としては有効）。
> 2026-10-19 に `GOOGLE_TOKEN_FILE` で 3 コマンドを実測した（`get-metadata` は 200、report 2 つは
> property 0 を report に使えないため API の 403 = 転送・記録は実測）。

## いつ使うか（トリガー）

- 「GA4 のセッション / ユーザー数を取って」「アナリティクスのレポートを見て」
- 「直近 7 日の推移」「日別のセッション」（`run-report`。日付は `7daysAgo` などの相対値もそのまま）
- 「いまのリアルタイムのユーザー」（`run-realtime-report`）
- 「このプロパティで使える dimension / metric を確認して」（`get-metadata`）
- 「GA4 の取得を証跡付きで残したい」（netloom 経由。カセットが証跡になる）

## 前提

- **`mcp_ga4_*` や Analytics Data API を直接叩かない**（seo の `ga4-analytics` skill は直接使う手順だが、
  それではリポジトリ側に証跡が残らない）。**GA4 の取得は netloom 経由**にする（往復がカセットに残る）
- **credential は Google の refresh grant**（GSC と同じ変数）: `GOOGLE_TOKEN_FILE`（env のパス。
  `netloom auth google --source ga4` が書くファイル）→ その `client_id` / `client_secret` / `refresh_token`、
  無ければ `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN`。**どちらも無ければ 1 往復も送らず exit 2**
- **プロパティは `--property ID` か env `GA4_PROPERTY_ID`**: どちらも無ければ 1 往復も送らず exit 2
  （値は裸の id = `123456789` の形。URL は `/v1beta/properties/<id>:runReport` になる）
- live は**読み取り専用**（`analytics.readonly` スコープ）。書き込み・設定変更（Admin API）は無い
  （2026-10-19 に `GOOGLE_TOKEN_FILE` で 3 コマンドを実測。`--property 0` は metadata 専用なので、report の live には実 property id が要る）

## 実行（1 コマンド = 認証 1 + データ 1 = カセット 4 frame）

```sh
# 0) 合意（owner が 1 回だけ）とプロパティ
netloom auth google --source ga4 --client-secrets /path/to/credentials.json
#    → $HOME/.config/netloom/google-ga4.json（0600）
export GOOGLE_TOKEN_FILE="$HOME/.config/netloom/google-ga4.json"
export GA4_PROPERTY_ID=123456789          # または毎回 --property 123456789

# 1) レポート（既定: 直近 7 日 / 構造化 json）
make ga4-report METRICS=sessions DIMENSIONS=date
make ga4-report METRICS=sessions DIMENSIONS=date START_DATE=30daysAgo END_DATE=today FORMAT=csv OUT=/tmp/sessions.csv
#    METRICS は必須（空は exit 2）。DIMENSIONS は空可（次元なしレポート）。
#    LIMIT（既定 100）/ OFFSET（既定 0）/ KEEP_EMPTY_ROWS / PROPERTY もそのまま渡る

# 2) リアルタイム（直近のスナップショット）
make ga4-realtime DIMENSIONS=deviceCategory METRICS=activeUsers LIMIT=10

# 3) メタデータ（dimension / metric の語彙）
make ga4-metadata OUT=/tmp/ga4-metadata.json          # 入れ子なので csv は無い（FORMAT=csv は exit 2）
```

バイナリを直接叩く場合は `bin/netloom ga4 run-report --metrics sessions --dimensions date --property 123456789`（他のフラグも同じ語）。
make 変数は `DIMENSIONS` / `METRICS` / `START_DATE` / `END_DATE` / `PROPERTY` / `OFFSET` /
`KEEP_EMPTY_ROWS`（`FORMAT` / `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` / `LIMIT` は共通）。

| フラグ | 意味 |
|---|---|
| `--dimensions T` | run-report / realtime: dimension（カンマ区切りのまま。**空可**） |
| `--metrics T` | run-report（**必須**）/ realtime（既定 `activeUsers`）: metric（カンマ区切りのまま） |
| `--start-date` / `--end-date` | run-report: 期間（既定 `7daysAgo` / `today`。解釈しない） |
| `--property ID` | 3 コマンド共通: プロパティ（**省略時は env `GA4_PROPERTY_ID`**。どちらも無ければ exit 2） |
| `--limit` / `--offset` / `--keep-empty-rows` | run-report（`limit` は realtime も）: そのまま渡す（**ページングは回さない**） |
| `--format` | json（既定）/ csv（run-report と realtime のみ。rows を平坦化）/ text / verbatim |
| `--out` / `--cassette` / `--replay` / `--timeout` | 他と同じ（`--replay` と `--cassette` は併用しない） |

## 出力の読み方

- `json`（既定）は **API の応答文書をそのまま**（キー順は受信のまま）: `dimensionHeaders` / `metricHeaders` /
  `rows`（各 row は `dimensionValues[].value` と `metricValues[].value`）/ `rowCount` / `kind`。
  metadata は `name` / `dimensions` / `metrics`
- `csv` は `rows` を平坦化した表（列 = **呼び出し側が名指した** `--dimensions` と `--metrics` の順。
  応答のヘッダから列を推測しない）。**0 行でもヘッダは出る**。`totals` / `maximums` / `minimums` は含まれない
- `text` は行数の要約（`rows: N`。0 行は `rows: 0`）。metadata は `dimensions: N` / `metrics: N`
- `verbatim` は受信バイトそのまま（証跡）
- **値を解釈しない**: 指標の意味・比較・集計は呼び出し側。未知の dimension / metric 名は GA4 が返した
  エラーがそのまま出る（allow-list は netloom に無い）

## 失敗の見分け（GA4）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 成功（0 行のレポートを含む） | — |
| 1 | 4xx / 5xx、交換の失敗（`invalid_grant` など）、replay 不一致（stderr に GA4 のメッセージがそのまま出る） | メッセージを読む。401 なら credential（`GOOGLE_*` / トークンファイル）。403 ならスコープか権限。dimension / metric 名の誤りは 400 に出る |
| 2 | 引数・設定（`--metrics` 欠落、`--property` も `GA4_PROPERTY_ID` も無い、credential 未設定、`get-metadata` の `csv`、`--replay` と `--cassette` の併用） | 引数と env を直す |
| 3 | I/O（`--out` / カセット / トークンファイルが読めない） | パスを直す |
| 124 | timeout（既定 300 秒。交換 + データの合計） | 再実行、または owner に相談 |

## 証跡とオフライン再現（GA4）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-ga4-<command>-<列 or property>.jsonl）
make ga4-report METRICS=sessions DIMENSIONS=date

# 同じ request で再生（ネットも credential も使わない。method + url + body が一致しないと exit 1）
make ga4-report METRICS=sessions DIMENSIONS=date REPLAY=.cassettes/20261017T173613Z-ga4-run-report-date-sessions.jsonl FORMAT=text
```

- カセットには HTTP の frame が 4 つ残る（**交換の send / recv**、**データの send / recv**。§5.1）。
  交換も証跡として残る（`client_secret` / `refresh_token` / `Authorization` は `[REDACTED]`）
- `--replay` は**交換をしない**（credential もネットも使わない）。データ要求（method + url + body）だけで答える
- **0.4.0 までの MCP カセットは再生できない**（frame の形が違う）。証跡としては有効なので削除しない
- **GA4 のカセットはプロパティの集計値を含む**ので `.cassettes/`（gitignore）にだけ置き、**コミットしない**。
  `raw/` に置かない。テストは偽 API（`httptest`。実データを fixture に置かない）
- 失敗（401 などの 4xx を含む）もカセットに残る（証跡）。再生すると**同じ失敗**になる（成功に偽装されない）
- カセットは**追記のみ**。編集・削除しない

---

# GSC（Google Search Console。2 コマンド）

GSC も **VCR を通すだけの薄いプロキシ**。クエリ body の検証・dimensions の allow-list・ページングの
自動化・リトライ・レート制限の待ち・値の解釈・正規化は**無い**。site と body はそのまま送られ、GSC が
返したエラーはそのまま返る。**1 コマンド = 2 往復**（認証 + データ。netloom 自身がトークンを交換する）。

## いつ使うか（トリガー）

- 「Search Console の検索パフォーマンスを見て」「このサイトの検索クエリ / クリック / 表示回数を取って」
- 「SC のプロパティ一覧を確認して」（`sites`）
- 「サーチコンソールのデータを証跡付きで取って」（カセットが証跡になる）

## 前提: `GOOGLE_*` の 3 つ（netloom が交換する）

- 値は**環境変数**で渡す。netloom は `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN`
  を読み、`https://oauth2.googleapis.com/token` に form-encoded で exchange して access token にする
- env ファイルは**ワークスペース外**に置く（seo の `.env.d/google_search_console.env` と同じ変数名。
  **値は読まない・出力しない**）。**コミットしない**。`chmod 600` にする
- **3 つのどれかが欠けていれば netloom は 1 往復も送らず exit 2**（リクエストも課金も発生しない）
- **代わりに `GOOGLE_TOKEN_FILE`（env のパス）でもよい**: そのファイル（`netloom auth google` が書く google-auth の authorized user JSON）の `client_id` / `client_secret` / `refresh_token` を使う。**両方あればファイルが勝つ**（1 つの解決順）。無い = exit 3 / 壊れた JSON = exit 2。`--replay` は交換をしないのでどちらも読まない（設計書 §7.2 / 付録 A.22）
- 任意で `GOOGLE_CLOUD_QUOTA_PROJECT`（または `--quota-project`）→ `x-goog-user-project`。無ければ送らない

```sh
# 例: env ファイルを読んでから実行（値は出力しない）
set -a; source /path/to/.env.d/google_search_console.env; set +a
```

## 実行（1 コマンド = 認証 1 + データ 1 = カセット 4 frame）

```sh
# 1) searchAnalytics のクエリ（site と body は呼び出し側が書く。**日付は ISO の YYYY-MM-DD** —
#    GSC は GA4 と違って `7daysAgo` / `today` を受け付けず 400 を返す（実測: 実装メモ §9）)
make gsc-query SITE='sc-domain:example.com' BODY='{"startDate":"2026-10-10","endDate":"2026-10-17","dimensions":["query"],"rowLimit":5}'
#    POST https://searchconsole.googleapis.com/webmasters/v3/sites/sc-domain%3Aexample.com/searchAnalytics/query
#    dimensions / rowLimit / dimensionFilterGroups / startRow はそのまま送る（ページングは回さない）
make gsc-query SITE='sc-domain:example.com' BODY=@body.json FORMAT=csv OUT=/tmp/gsc.csv
#    csv の列 = body の dimensions の順 + clicks,impressions,ctr,position（body に dimensions が無ければ exit 2）

# 2) プロパティ一覧
make gsc-sites            # FORMAT=csv は siteUrl,permissionLevel / FORMAT=text は sites: N
```

バイナリを直接叩く場合は `bin/netloom gsc query --site … --body …` / `bin/netloom gsc sites`。
make 変数は `SITE` / `BODY` / `QUOTA_PROJECT`（`FORMAT` / `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` は共通）。
`BODY` は `INPUT` と同じ扱い（JSON を make の展開に通さない。`$` を含む値は `BODY=@body.json`）。

| フラグ | 意味 |
|---|---|
| `--site URL` | `query`: プロパティ（必須。`sc-domain:example.com` / `https://example.com/`。そのまま送る） |
| `--body JSON\|@FILE` | `query`: searchAnalytics の body（必須。JSON であることだけを見て送る） |
| `--quota-project ID` | 両方: `x-goog-user-project`（既定は env `GOOGLE_CLOUD_QUOTA_PROJECT`） |
| `--format` | json（既定）/ csv（query と sites）/ text / verbatim |
| `--out` / `--cassette` / `--replay` / `--timeout` | 他と同じ（`--timeout` は**認証 + データの合計**。`--replay` と `--cassette` は併用しない） |

## 出力の読み方

- `json`（既定）は GSC の生構造のまま: `{"rows":[{"keys":[…],"clicks":…,"impressions":…,"ctr":…,"position":…}],"responseAggregationType":…}`。
  **0 行のとき GSC は `{}` を返すことがある**（`text` はそのとき exit 1、json / csv / verbatim は成功）
- `csv` は `rows` を平坦化した表（列 = body の `dimensions` の順 + metrics）。`keys` が dimensions と
  合わない行は表にしない（exit 1）
- `text` は `rows: N`（+ `responseAggregationType`）、sites は `sites: N`
- **値を解釈しない**: 検索クエリの意味・期間比較・集計は呼び出し側。`startRow` を書いて続きを取るのも
  呼び出し側（netloom はページングしない）

## 失敗の見分け（GSC）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 2xx | — |
| 1 | **交換の失敗（`invalid_grant` = credential の期限切れ / 失効）**・データの 4xx / 5xx / 接続失敗 / replay 不一致 | stderr の 1 行を読む。`invalid_grant` なら credential を更新する（seo 側の作業）。それ以外は `--cassette` で応答全体を見る |
| 2 | 引数・設定（`--site` / `--body` 欠落、JSON でない body、`dimensions` 無しの csv、`GOOGLE_*` 未設定、`--replay` と `--cassette` の併用） | 引数と env を直す |
| 3 | I/O（`--out` / カセット / `@FILE`） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | 再実行、または owner に相談 |

**`invalid_grant`（HTTP 400）は credential の問題**（netloom の設定ではない）。トークン端点が
request / response ともカセットに残るので、そこで確認できる。

## 証跡とオフライン再現（GSC）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-gsc-<command>-<target>.jsonl）
make gsc-query SITE='sc-domain:example.com' BODY=@body.json

# 同じ request で再生（ネットも credential も使わない。**交換はしない**。method + url + payload が
# 一致しないと exit 1）
make gsc-query SITE='sc-domain:example.com' BODY=@body.json REPLAY=.cassettes/20261018T120000Z-gsc-query-sc-domain-example-com.jsonl FORMAT=csv
```

- カセットには **4 frame**: 交換の `send`（`/token`、form body） / `recv` → データの `send` / `recv`
- 交換の request body は **form-encoded のテキスト**で入る（`grant_type=refresh_token` は残り、
  `client_id` / `client_secret` / `refresh_token` の値は `[REDACTED]`）。応答の `access_token`（`ya29.…`）も伏せられる
- データの `Authorization` と `x-goog-user-project` は記録前に `[REDACTED]` になる（実値は入らない）
- 4xx / 5xx を記録したカセットを再生すると、**同じ失敗**になる（成功に偽装されない）
- **交換しか記録していないカセット**（credential が古く `invalid_grant` で終わった run）は、データ要求に
  答える frame が無いので再生できない（exit 1）
- **GSC のカセットは自分のサイトの検索語と数値を含む**ので `.cassettes/`（gitignore）にだけ置き、
  **コミットしない**。`raw/` に置かない。共有・貼り付けもしない
- カセットは**追記のみ**。編集・削除しない

---

# auth google（ローカルコマンド。Google OAuth の同意フロー。**対話専用**）

provider を呼ばない netloom 自身のコマンド（`skill` と同じ族。source を名指さない）。**人がブラウザで同意する 1 回だけのコマンド**で、GSC の refresh token（`.github/bin` の 3 本が取っていたもの）を netloom 自身で取る（issue #11）。

```sh
# 同意（1 回だけ。ブラウザが開く。開かなければ stderr に出た URL を開く）
make auth-google AUTH_CLIENT_SECRETS=/path/to/credentials.json AUTH_SOURCE=gsc
bin/netloom auth google --source gsc --client-secrets /path/to/credentials.json   # make と同じ

# できたトークンファイルだけでデータを取る（GOOGLE_REFRESH_TOKEN は不要）
GOOGLE_TOKEN_FILE="$HOME/.config/netloom/google-gsc.json" bin/netloom gsc sites
```

| フラグ | 意味 |
|---|---|
| `--source NAME` | 既定スコープの表: `gsc` → webmasters / `ga4` → analytics.readonly / `calendar` → calendar / `gas` → script.* + spreadsheets。**`calendar` / `gas` は送信元ではない**（スコープ名。`gas` の 6 スコープは `apps-script` 送信元の live トークンが使う — 付録 A.27） |
| `--scopes A,B` | 既定を上書き（カンマ区切り。空要素は exit 2） |
| `--client-secrets FILE` | OAuth クライアント JSON（`{"installed":{…}}`。**必須・既定パスなし**。netloom は推測しない） |
| `--token-file FILE` | 書き出し先（既定 `$HOME/.config/netloom/google-<source>.json`。dir 0700・file 0600） |
| `--cassette FILE` | 交換の証跡（2 frame）の記録先（issue #22。**caller の記録置き場に置く** — 例: `data/gsc/cassettes/<YYYYMMDD>-auth-gsc.jsonl`。他コマンドと同じ意味・同じ規則。既定は `.cassettes/<UTC>-auth-google-<source>.jsonl`） |

- **対話専用**: stdin / stdout / stderr が端末で `CI` が未設定のときだけ動く。**CI・自動テストは exit 2**（listener も開かない）
- ループバック（`http://127.0.0.1:<ephemeral>/`）+ PKCE（S256）。待ち時間は既定 300 秒（専用フラグは無い）。Ctrl-C で中断できる
- トークンファイルは google-auth の authorized user JSON と互換（`client_id` / `client_secret` / `refresh_token` / `token` / `scopes` / `expiry` の 6 つ。**1 行・末尾改行なし**）。書き込みは一時ファイル + rename（原子的）
- **値は stdout / stderr / カセットに出ない**。交換の往復はカセット（既定 `.cassettes/<UTC>-auth-google-<source>.jsonl`、`--cassette FILE` で caller の記録置き場に変更可 = issue #22）に残るが、form の `client_id` / `client_secret` / `code` / `code_verifier` と応答の `access_token` / `refresh_token` は `[REDACTED]`
- **同意の redirect（ブラウザ → ループバック）は記録しない**（URL に code が載るため）
- 失敗の写像: 同意キャンセル・state 不一致・`invalid_grant` = exit 1 / `--client-secrets` が読めない・トークンファイルを書けない = exit 3 / 引数と client JSON の形 = exit 2 / 300 秒超過 = exit 124


---

# news / cache（EC-CUBE 自サイト API。8 コマンド）

ショップ自身のニュースの CRUD・サムネイル画像・キャッシュクリアを、**VCR を通す薄いプロキシ**として扱う。
フィールドの検証・allow-list・画像の形式やサイズの検査・ページングの自動化・リトライ・レート制限の待ち・
値の解釈・キャッシュの状態管理は**無い**（API が返したエラーはそのまま返る）。仕様の正は seo-operations の
`ec-news-api` スキル。

## いつ使うか（トリガー）

- 「ショップのニュース（新着情報）を一覧 / 取得したい」「ニュースを登録 / 修正 / 削除したい」
- 「ニュースにサムネイル画像を付けたい / 外したい」
- 「更新がフロントに出ないのでキャッシュをクリアしたい」
- 「本番ではなく開発サーバーで試したい」（`ENV=dev`。本番は `ENV=prod`）

## 前提: `SEO_API_KEY`（+ 開発環境は Basic 認証）

- live は環境変数 `SEO_API_KEY`（`X-API-Key` ヘッダ）と、**開発サーバーでは** `HTTP_BASIC_AUTH_USER` /
  `HTTP_BASIC_AUTH_PASS`（netloom が `Authorization: Basic <base64(user:pass)>` を組む）が要る
- env ファイルは**ワークスペース外**に置く。**コミットしない**。`chmod 600` にする。値は stdout / stderr /
  カセットのどこにも出ない（`X-API-Key` と `Authorization` は名前を残して `[REDACTED]`）
- **どれか欠けていれば netloom は 1 往復も送らず exit 2**（カセットも作らない）
- **開発サーバーの base URL は env `EC_DEV_BASE_URL` から読む**（news / article / cache / contact / ga4-orders / landing-page / product の **7 送信元共通**。**コードに値は無い**）。未設定なら `--env dev` のコマンドは **exit 2**（メッセージに変数名が出る。1 往復も送らない）。`--replay` でも要る（URL がカセットの照合に要る）
- **値は credential ではない**ので、カセットの URL にはそのまま載る（証跡として必要。レダクトされない）。呼び出し側（seo-operations）は同じ値に `ADMIN_DEV_URL` の名前を付けて `.env.d/admin_dev.env` に置く
- `cache clear` はニュースと記事 API の共用キャッシュクリア（同じ場所・同じ認証）

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
# 一覧（`--format csv` は固定の列。LIMIT / OFFSET は API に渡すだけ）
make news-list LIMIT=10 OFFSET=0
make news-list FORMAT=csv OUT=/tmp/news.csv

# 1 件（`--format text` は id / title / publish_date の要約）
make news-get ID=1239

# 作成 → 更新 → 削除（CLEAR_CACHE=1 で書き込み後のクリアを同じ往復に載せる）
make news-create INPUT='{"title":"invented","top_page_notice":true}' CLEAR_CACHE=1
make news-update ID=1239 INPUT=@body.json
make news-delete ID=1239 CLEAR_CACHE=1

# サムネイル（multipart。形式・5MB は API の判定。**派生バリアントはサーバー側で生成されない**）
make news-image-upload ID=1239 FILE=thumb.jpg CLEAR_CACHE=1
make news-image-delete ID=1239

# 共用キャッシュクリア（同期実行。200 が返ればクリア済み）
make cache-clear

# 本番への書き込みは明示フラグが要る（読み取りは不要。読み取りに付けると exit 2）
make news-delete ID=1239 ENV=prod ALLOW_PROD_WRITE=1
```

| 変数 | 既定 | 値 |
|---|---|---|
| `ID` | （get / update / delete / image-* で必須） | ニュース ID |
| `INPUT` | （create / update で必須） | 本文の JSON 1 文書（または `INPUT=@body.json`） |
| `FILE` | （image-upload で必須） | 画像のパス（jpeg / png / webp・5MB 以内は API の判定） |
| `LIMIT` / `OFFSET` | （省略 = API の既定） | 一覧の件数 / 読み飛ばし（`list` のみ） |
| `CLEAR_CACHE` | （未指定） | `1` で書き込みの URL に `clear_cache=1` |
| `NEWS_ENV` | `dev`（未指定なら dev） | `dev` / `prod` |
| `ALLOW_PROD_WRITE` | （未指定） | `1` で本番への書き込みを確認 |
| `FORMAT` | `json` | list: `json` / `csv` / `text` / `verbatim`、get と書き込み系: `json` / `text` / `verbatim` |
| `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | 他と同じ | |

## 出力の読み方

- `json`（既定）は API の文書のまま（`success` / `total` / `items` / `item` / `message` など）。
  **値を解釈しない**: ニュースの内容・公開日時の意味・キャッシュの状態は呼び出し側が読む
- `csv` は**一覧のみ**。列は `id,title,description,citation,url,link_method,publish_date,top_page_notice,creator_id`
  の固定で、API が述べていない項目は空セルになる（実測: 一覧は `citation` を返さない）
- `text` は要約: 一覧 = `total` / `limit` / `offset` / `items: N`、1 件 = `id` / `title` / `publish_date`、
  書き込み = `success` / `message` / `cache_cleared`（`cache clear` は `duration_ms`）
- **`title` は API の必須項目**。netloom は JSON であることしか見ないので、欠けた本文は API の 400 になる
- 画像の応答の `item.thumbnail_path` に保存値が入る（一覧ページでは未使用）

## 失敗の見分け（news / cache）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 2xx | — |
| 1 | 400 / 401 / 404 / 405 / 500（API の応答のまま）・接続失敗・replay 不一致 | stderr の 1 行とカセットを読む。401 はキー、404 は ID、405 はメソッドを確かめる |
| 2 | 引数・設定（`--id` / `--input` / `--file` 欠落、JSON でない本文、語彙外の `--env`、**本番書き込みのフラグ無し**、読み取りのフラグ、dev ホスト未記入、credential 未設定） | 引数と env を直す |
| 3 | I/O（`--out` / カセット / `@FILE` / `--file`） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | 再実行、または owner に相談 |

## 証跡とオフライン再現（news / cache）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-news-<command>-<target>.jsonl）
make news-list LIMIT=10

# 同じ request で再生（ネットも credential も使わない。method + url + 本文 / 証跡の一致が要る）
make news-list LIMIT=10 REPLAY=.cassettes/20261019T120000Z-news-list-all.jsonl
make news-image-upload ID=1239 FILE=thumb.jpg REPLAY=.cassettes/…-news-image-upload-1239.jsonl
```

- 1 コマンド = **2 frame**（`send` / `recv`）。失敗もカセットに残る
- **画像の `send` の `payload` は本文ではなく識別 JSON**（`{"kind":"multipart","fields":{…},"file":{"field":"file","sha256":…,"size":…}}`）。
  **本文・boundary・ファイル名はカセットに入らない**（boundary は毎回変わる）。replay は sha256 で照合するので、
  **同じ画像ならファイル名が違っても答える**。別の画像を渡すと exit 1（他の画像の応答を返さない）
- `X-API-Key` と dev の `Authorization` は記録前に `[REDACTED]`。**netloom が組む `Basic <base64>` の値も
  どこにも出ない**（provider がエコーしても伏せる）
- **news / cache のカセットはショップのニュースを含む**ので `.cassettes/`（gitignore）にだけ置き、
  **コミット・共有しない**。`raw/` に置かない。カセットは**追記のみ**（編集・削除しない）

---

# article（EC-CUBE ガイド記事 API。8 コマンド）

ガイド記事（物質辞典などの本体）の CRUD と画像を、news と同じ形で扱う。環境・認証・prod ガード・
multipart の証跡・カセットの規則は **news と同じ**（上の節）。**netloom は slug を解釈せず、slug → id の
解決もしない**（呼び出し側が `list` の `offset` を進めて見つける）。**大きな本文も切り詰めない**（カセットが
証跡で、切り詰めると replay の本文一致が失われる）。

## いつ使うか（トリガー）

- 「ガイド記事を公開 / 更新 / 削除したい」（原稿 → `loom md build` → intro/body/summary/citation の 4 分割 → PUT）
- 「公開済みの記事を slug で確かめたい」（`list` で id を引き、`get` で `status` と本文を見る）
- 「記事のヒーロー画像 / 記事内画像を入れ替えたい、alt / caption / position を直したい」
- 「記事のゲート（パスワード保護）を付け外ししたい・一括で切り替えたい」（`article gate --input`。下の「ゲート」節）

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
make article-list LIMIT=100                          # 一覧（`--format csv` は固定の列）
bin/netloom article list --fields id,slug,title,status,update_date   # 返すフィールドを絞る（slug → id の引き当てを軽く。issue #38）
make article-get ID=169                              # 1 件（text は id / title / slug / status / is_gated）
make article-create INPUT='{"title":"invented","slug":"invented-guide","body_html":"<p>invented</p>"}'
make article-update ID=169 INPUT=@body.json CLEAR_CACHE=1     # 部分更新（述べたフィールドだけ）
make article-update ID=169 INPUT=@body.json DRY_RUN=1          # 送信しない契約検査（exit 1 = 契約違反）
make article-delete ID=169 CLEAR_CACHE=1
# ゲートの一括切り替え（2026-10-24 追補。plugin 4.5.9 / 4.5.10。**dev で実測済み = 設計 A.16**）:
bin/netloom article gate --input '{"slugs":["invented-guide"],"is_gated":true,"dry_run":true}'
bin/netloom article gate --input @gate.json       # ids 優先 / 上限 100 件 / 部分成功は not_found
make article-gate INPUT='{"slugs":["invented-guide"],"is_gated":true,"dry_run":true}'   # make からも同じ本文（コマンドライン変数をシェルへ渡すので JSON が壊れない）

# 画像（--type は thumbnail（既定）/ image。type=image のメタデータは form field で送る）
make article-image-upload ID=169 FILE=hero.webp ARTICLE_TYPE=image ALT='説明' CAPTION='キャプション' POSITION=middle
#   ※ alt / caption を *クリア* するときは make ではなくバイナリで: bin/netloom article image-upload --id 169 --file hero.jpg --type image --alt ""
#   ※ alt / caption が保存されるのは type=image のときだけ（thumbnail でも送るが現行のショップ API は受け付けない: 2026-10-21 実測で thumbnail_path は保存・image_alt / image_caption は null。修復はショップ側 API — issue #54）
make article-image-delete ID=169 ARTICLE_TYPE=image
make cache-clear                                    # ニュースと共用（article でも同じ 1 本）
```

| 変数 | 既定 | 値 |
|---|---|---|
| `ID` | （必須） | 記事 ID |
| `INPUT` | （create / update で必須） | 本文の JSON（`title` / `slug` / `body_html` は API の必須。slug の形式・一意性も API の判定） |
| `FILE` | （image-upload で必須） | 画像（jpeg / png / webp・5MB 以内は API の判定。派生バリアントは API が生成） |
| `ARTICLE_TYPE` | （API の既定 = thumbnail） | `thumbnail` / `image` |
| `ALT` / `CAPTION` / `POSITION` | （API の既存値） | `type=image` のメタデータ（position は `after_intro` / `middle` / `after_summary`） |
| `LIMIT` / `OFFSET` | （API の既定） | 一覧の件数 / 読み飛ばし（100 件上限は API の仕様） |
| `CLEAR_CACHE` / `NEWS_ENV` / `ALLOW_PROD_WRITE` / `FORMAT` / `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | news と同じ | |
| `DRY_RUN` | （なし = 送信） | `1` で `--dry-run`（update の契約検査。下参照） |

**update の入力契約（issue #35 / #40）**: `--input` は**更新したいフィールドだけの JSON**
（API が述べるキーは `title` / `slug` / `body_html` / `intro_html` / `summary_html` /
`meta_description` / `citation` / `status` / `sort_no` / `category_slugs` の 10 個 + `custom_json_ld`（下））。
`article get` の生出力をそのまま渡すと応答専用のキー（`id` / `published` / `update_date` 等）が
混入し、**API が黙って無視する**ので本文は更新されても意図した変更が反映されない。`citation` は
65,535 バイト以内。

- **`custom_json_ld`（plugin v4.3.0。2026-10-19 時点で未デプロイ — カセットは API のデプロイ後に録画）**: `POST` / `PUT` の本文に string | null で追加（PUT は部分更新: 未指定 = 無変更 / `null` = クリア / 文字列 = 上書き。API は型とサイズだけ検証 — 非 string / 65,535 超は 400。GET の `item` に入り未設定は `null`）。`--dry-run` の既知キーには既に含む（デプロイ後の誤警報防止）。`--input` の扱いは変わらない（任意の JSON をそのまま送る）。csv の固定列には出ない（json で読む）

- **`--dry-run`（update のみ）は 1 往復も送らない契約検査**: `bin/netloom article update --id 169 --input @body.json --dry-run`
  - exit 0 = 送信可能 / **1 = 契約違反**（混入キーの名前とフィールドごとのバイト数——json は `fields_bytes`、text は `name=N B`（issue #43）——を出力。**値は出さない**）/ 2 = 入力が使えない（JSON でない・オブジェクトでない・`@FILE` が読めない）
  - **credential も `EC_DEV_BASE_URL` も要らない**（送らないので）。カセットも作らない。`--cassette` / `--replay` / `--clear-cache` とは併用不可（exit 2）。`--env prod` は `--allow-prod-write` が要る
  - CI / make のゲートにできる（`make article-update ID=169 INPUT=@body.json DRY_RUN=1`）

- **`--fields`（list のみ。issue #38）**: 返す item の member をカンマ区切りで指定（前後の空白は落とす。**provider のキー名の pass-through** — 語彙検証なし。新しい名前を足さない）。**出力側だけのフラグ** — query / request に載らず、request は `--fields` 無しと同じ（同じカセットで `--replay` できる）。json は `items` を指定どおりの順序で指定 member だけに絞る（`total` / `limit` / `offset` はそのまま。**item が述べない member は出さない**）、csv は列を同様に絞る（既定は固定列のまま）、text は変わらない（本文は既に出していない）。`get` には無い（付けたいときは別 issue）

## ゲート（`is_gated` と `article gate`。2026-10-24 追補）

ガイド記事にゲート（パスワードで守る）を付けられることがある（plugin 4.5.9 / 4.5.10。issue thch-vape.shop#731）。netloom はそれを**そのまま運ぶだけ**。

- **読み取り**: `article get` / `article list` の `item` / `items[]` に `is_gated`（bool）と `gate_configured`（bool。ゲートのパスワードを**持っているかどうかだけ**。値は返らない）が増える。**text の get は `is_gated` を述べる**（`gate_configured` は述べない）、**csv の列は `is_gated` だけを足す**（`gate_configured` は列にしない）——`gate_configured` はショップの環境変数の有無で決まり、**全行が同じ値**なので表にしても情報量がゼロ。判断に使うのは**組み合わせ**（`is_gated:true` + `gate_configured:false` = 誰も解錠できない）で、これは **1 記事の json の `item`** で見る
- **書き込み（既存）**: `article create` / `article update` の `--input` に `is_gated` を載せられる（**真偽値のみ**。`1` や `"true"` は 400）。`update` は**未指定なら現状維持**。netloom は型を見ない（400 はサーバーの答え）。**`--dry-run` の既知キーにも入っている**
- **一括（新規）**: `bin/netloom article gate --input '{"slugs":["invented-guide"],"is_gated":true,"dry_run":true}'` → `PUT /api/article/gate`、1 往復
  - 本文の member: `slugs` / `ids`（**`ids` 優先**）、`is_gated`、`dry_run`。**上限 100 件**・**冪等**（既に同じ値なら `unchanged`）・**部分成功**（見つからないキーは `not_found`、**全滅のときだけ 404**）
  - `@FILE` も使える（`create` / `update` と同じ規則。JSON であることだけ見て compact する）
  - **応答はそのまま**: `{"success":true,"is_gated":true,"updated":[235,236],"unchanged":[238],"not_found":[{"key":"slug","value":"invented-999","reason":"not_found"}],"dry_run":true}`。text は `success` / `is_gated` / `dry_run` + `updated` / `unchanged` / `not_found` の**件数**（どのキーが落ちたかは json / verbatim）
  - **`not_found[].value` の型は `key` で変わる**（`key:"slug"` は文字列、`key:"id"` は数値）。読む側で型を決め打ちしない
  - **フラグは `--input` だけ**（`--slugs` / `--gated` / `--dry-run` / `--id` / `--clear-cache` は無い — 付ければ exit 2）。本文は呼び出し側が書き、`dry_run` は本文の member（フラグにすると「どのキーが本文に載るか」の形を netloom が持つことになる = 薄いプロキシを崩す）。件数上限も `is_gated` の型も**検証しない**（400 / 404 はサーバーの答え）
  - **`--env prod` は `--allow-prod-write` が要る**（書き込みの門は他の書き込みと同じ）。`--replay` は門を素通り、カセットの既定名は `.cassettes/<UTC>-article-gate.jsonl`
- **`--dry-run`（update）と `dry_run`（gate の本文）は別物**: 前者は **netloom のローカル契約検査**（1 往復も送らない・キー名の点検）、後者は **サーバー側の dry run**（往復し、何をするはずだったかを `updated` / `unchanged` で返す）。`article gate --dry-run` は無い（exit 2）
- **実測済み（2026-10-24。dev。状態は変えていない）**: `get` の `item` は 25 キーで `is_gated: true` / `gate_configured: true`、csv は 13 列（末尾 `is_gated`）、`gate` の `dry_run: true` = `unchanged: [235]`、`dry_run` を外すと `unchanged: [235]`（既に同じ値なので状態不変）、`is_gated: 1` = **400**。**`ids` は `slugs` に優先**、`key: id` の `not_found[].value` は**数値**、101 件は **400**（上限 100）
- **全滅 404 の本文は `success: true`**: 「サーバーが要求を解釈できたか」（`success`）と「対象があったか」（HTTP status）は**別の層**。**netloom は HTTP status で exit code を決める**（404 = exit 1・本文は stdout に出さない）ので、`success` を見て成否を判断しないこと。**残る未確認は `gate_configured: false` の環境だけ**（構成を変える必要があるため）

## 失敗の見分け（article）
news と同じ（exit 1 / 2 / 3 / 124。付録 A.16）。**401** はキー、**404** は ID、**400** は
「必須（title / slug / body_html）・slug 形式/重複・status 値・カテゴリ slug・citation の型/長さ（>65,535
バイト）・画像の形式/サイズ/未設定」——どれも **API の文面がそのまま返る**ので、stderr の 1 行とカセットで読む。

## 証跡とオフライン再現（article）

```sh
make article-list LIMIT=100                          # 記録（.cassettes/<UTC>-article-list-all.jsonl）
make article-list LIMIT=100 REPLAY=.cassettes/20261019T120000Z-article-list-all.jsonl
make article-update ID=169 INPUT=@body.json REPLAY=.cassettes/…-article-update-169.jsonl
```

- 画像の `send` の `payload` は証跡 JSON で、**`fields` に `type` / `alt` / `caption` / `position` が入る**
  （本文・boundary・ファイル名は入らない。replay は sha256 とフィールドの一致で答える）
- **未公開（`status=draft`）の原稿本文を含む**ので `.cassettes/`（gitignore）にだけ置き、
  **コミット・共有しない**。`raw/` に置かない。カセットは**追記のみ**。

---

# contact（EC-CUBE お問い合わせ API。5 コマンド）

ショップのお問い合わせ（ContactManagement42 の `dtb_contact`）の CRUD を、news と同じ形で扱う。環境・
認証（`X-API-Key` + dev の Basic）・prod ガード・カセットの規則は **news と同じ**（上の節）。**画像と
キャッシュクリアのエンドポイントは無い**ので `--file` / `--clear-cache` / image コマンドは存在しない。

**PII の扱い**: 応答には氏名・メール・電話・住所・問い合わせ本文が入る。**netloom はレダクトしない**
（`list` / `get` の応答にも PII が入るため、レダクトするなら replay の同一結果が壊れる。付録 A.17 の
設計相談 1 への回答）。**だからこそカセットは `.cassettes/`（gitignore）にだけ置き、コミット・共有・
`raw/` 配置をしない**（shop 側の規約: 顧客レベルのデータをリポジトリに残さない）。

## いつ使うか（トリガー）

- 「お問い合わせを一覧 / 取得したい」「お問い合わせの対応状況（`status_id`）や備考を更新したい」
- 「外部フォームからのお問い合わせを登録したい」（`contact create`。API の必須は `name01` / `name02` / `email`）
- 「開発サーバーで試したい」（`NEWS_ENV=dev`。本番は `NEWS_ENV=prod` + 書き込みは `ALLOW_PROD_WRITE=1`）

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
make contact-list LIMIT=10 OFFSET=0          # 一覧（`--format csv` は固定の列。API の既定は limit=20・最大 100）
make contact-get ID=41                       # 1 件（text は id / name01 / name02 / status_id）
make contact-create INPUT='{"name01":"invented","name02":"one","email":"invented@example.test"}'
make contact-update ID=41 INPUT='{"status_id":2,"note":"invented"}'   # 部分更新（述べたフィールドだけ）
make contact-delete ID=41
```

| 変数 | 既定 | 値 |
|---|---|---|
| `ID` | （get / update / delete で必須） | お問い合わせ ID |
| `INPUT` | （create / update で必須） | 本文の JSON（または `INPUT=@body.json`。`name01` / `name02` / `email` は API の必須） |
| `LIMIT` / `OFFSET` | （API の既定） | 一覧の件数 / 読み飛ばし（`list` のみ） |
| `NEWS_ENV` / `ALLOW_PROD_WRITE` / `FORMAT` / `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | news と同じ | |

- `text` は要約: 一覧 = `total` / `limit` / `offset` / `items: N`、1 件 = `id` / `name01` / `name02` /
  `status_id`、書き込み = `success` / `message`（`cache_cleared` は無い）
- `csv` の列は `id,name01,name02,email,kana01,kana02,phone_number,postal_code,addr01,addr02,contents,note,contact_type,status_id`
  の固定で、**API が述べていない項目は空セル**（`status_name` / `create_date` などは json / verbatim で読む）
- `--env prod` の書き込み（create / update / delete）は `--allow-prod-write` が無ければ exit 2。読み取りは不要

## 証跡とオフライン再現（contact）

```sh
make contact-list LIMIT=10                   # 記録（.cassettes/<UTC>-contact-list-all.jsonl）
make contact-list LIMIT=10 REPLAY=.cassettes/20261019T120000Z-contact-list-all.jsonl
```

- 1 コマンド = **2 frame**（`send` / `recv`）。失敗（400 / 401 / 404 / 500）もカセットに残り、replay は**同じ失敗**を返す
- `X-API-Key` と dev の `Authorization` は記録前に `[REDACTED]`
- **カセットは顧客の PII を含み、レダクトされない**。`.cassettes/`（gitignore）にだけ置き、**コミット・共有しない**。`raw/` に置かない。カセットは**追記のみ**（編集・削除しない）

---

# ga4-orders（EC-CUBE GA4 受注同期 API。5 コマンド）

ショップの GA4 受注同期（SalesReport42 の `plg_sales_report42_ga4_order`。`sync_status` = pending /
`eccube_order_id` の紐づけ）の CRUD を、news と同じ形で扱う。環境（`--env dev|prod`）・dev の Basic・
prod ガード・カセットの規則は **news と同じ**。**認証だけが違う**: **`X-GA4-API-Key` ヘッダで
`GA4_API_KEY` を送る**（ヘッダ名も変数名も news と別。**値はショップの `SEO_API_KEY` と同じもの** = 下の注意）。

**GA4 Data API の `ga4` とは別物**: あちらは集計レポートを Analytics Data API（HTTP。Google の refresh grant）で読む送信元で、こちらは
ショップの受注テーブルを HTTP で管理する送信元。名前が似ているが、コマンドも認証も別（`--property` などは
取らない）。

**実運用**: `list` / `get` / `update` / `delete` が主。**`create` はバックフィルとテスト用**（本来は GA4
側の連携が POST する）。**画像・キャッシュクリアのエンドポイントは無い**。

**売上の扱い**: 応答には売上額・`transaction_id`・`user_id`・商品明細が入る。**netloom はレダクトしない**
（理由は contact と同じ。付録 A.18 の設計相談 2 への回答）。**カセットは `.cassettes/`（gitignore）に
だけ置き、コミット・共有・`raw/` 配置をしない**。

## いつ使うか（トリガー）

- 「GA4 の受注が同期されているか確認したい」（`ga4-orders list` / `get`）
- 「`sync_status` を `synced` にし、`eccube_order_id` を紐づけたい」（`ga4-orders update`）
- 「バックフィル / テストで受注を 1 件登録したい」（`ga4-orders create`。必須は `transaction_id` / `value`。**`transaction_id` は実在する `dtb_order.order_no`（文字列）** — 2026-10-24 の契約変更で、実在しない番号は 422）

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
make ga4-orders-list LIMIT=10 OFFSET=0       # 一覧（`--format csv` は固定の列。最後の列は item_count）
make ga4-orders-get ID=7                     # 1 件（text は order の id / transaction_id / sync_status）
make ga4-orders-update ID=7 INPUT='{"sync_status":"synced","eccube_order_id":1234}'   # 現状 405
make ga4-orders-delete ID=7                  # 現状 405
make ga4-orders-create INPUT='{"transaction_id":"<実在する order_no>","value":1500}'   # バックフィル・テスト用。実在しない番号は 422
```

| 変数 | 既定 | 値 |
|---|---|---|
| `ID` | （get / update / delete で必須） | **`plg_sales_report42_ga4_order.id`**（＝ `list` の `items[].id`）。**受注番号ではない**（受注番号は `transaction_id` = `dtb_order.order_no`。取り違えると 404） |
| `INPUT` | （create / update で必須） | 本文の JSON（または `INPUT=@body.json`。create の必須は `transaction_id` / `value`） |
| `LIMIT` / `OFFSET` | （API の既定） | 一覧の件数 / 読み飛ばし（`list` のみ） |
| `NEWS_ENV` / `ALLOW_PROD_WRITE` / `FORMAT` / `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | news と同じ | |

- `csv` の列は `id,transaction_id,value,tax,shipping,coupon,user_id,device_category,referrer,source,medium,campaign,item_count` の固定（**一覧の item は明細配列を持たず `item_count` だけ**。`sync_status` / `eccube_order_id` は json / verbatim で読む）
- **応答の封筒は `status`（ok / error）**（2026-10-24 の契約）: 一覧 = `{status,total,limit,offset,items}`、詳細 = `{status,order:{…,items:[…]}}`（**`order` の下**）、書き込み = `{status,message,ga4_order_id,…}`。**text** は list = `total` / `limit` / `offset` / `items: <件数>`、get = `order` の `id` / `transaction_id` / `sync_status`、書き込み = `status` / `message` / `ga4_order_id` / `existing_ga4_order_id` / `sync_status`
- **`create` の 2 つの応答を混同しない**: 実在しない受注番号は **422**（exit 1。本文は出力しない）、真の重複は **200 `{"status":"skipped",…,"existing_ga4_order_id":N}`**（**成功** = exit 0。その行は既にある）
- **`update` / `delete` は現状 405**（ショップ側にルートが無い = `Allow: POST`。exit 1）。コマンドは残してあるので、ルートが付いた日にそのまま動く。**失敗を成功に偽装しない**（405 は本文も出力しない）
- **`GA4_API_KEY` の値はショップの `.env` の `SEO_API_KEY` と同じもの**（サーバーが `X-GA4-API-Key` を `hash_equals` で比べる。netloom の変数名は `GA4_API_KEY`）。揃っていないと 401 `Invalid API key.`
- `--env prod` の書き込み（create / update / delete）は `--allow-prod-write` が無ければ exit 2。読み取りは不要
- **一覧の絞り込みはサーバー側で実装済み**（`?sync_status=pending|synced|error` / `?transaction_id=<完全一致>`。PR #502。語彙外の `sync_status` は 400）。**netloom のフラグはまだ無い**（予約）— 必要になるまでは `json` で読んで `jq` で絞るか、`--limit` / `--offset` で読む

## 証跡とオフライン再現（ga4-orders）

```sh
make ga4-orders-update ID=7 INPUT='{"sync_status":"synced"}'   # 記録（.cassettes/<UTC>-ga4-orders-update-7.jsonl）
make ga4-orders-update ID=7 INPUT='{"sync_status":"synced"}' REPLAY=.cassettes/…-ga4-orders-update-7.jsonl
```

- 1 コマンド = **2 frame**（`send` / `recv`）。400 / 401 / 404 / **405** / 500 もカセットに残り、replay は**同じ失敗**を返す
- **`X-GA4-API-Key` と dev の `Authorization` は記録前に `[REDACTED]`**（値はカセット・stdout・stderr に出ない）
- **カセットは売上・受注を含み、レダクトされない**。`.cassettes/`（gitignore）にだけ置き、**コミット・共有しない**。`raw/` に置かない

---

# landing-page（EC-CUBE LandingPage API。5 コマンド）

ショップのランディングページ（`plg_landing`）の CRUD を、news と同じ形で扱う。環境（`--env dev|prod`）・認証（`X-API-Key` + dev の Basic = `SEO_API_KEY`）・prod ガード・`--clear-cache`・カセットの規則は **news と同じ**（上の節）。**画像エンドポイントは無い**（`plg_landing` に画像カラムが無い。本文 HTML 内の `<img>` はそのまま保存される）。

**prod は未デプロイ**: `/api/landing-page` のコードは thch-vape.shop の development のみ。本番反映は owner が main へマージ後にデプロイする。それまで prod の `/api/landing-page` は **404**（読み取りも 404 = exit 1）。**live 受入は dev のみ**。

**LP の本文は業務データ**: 詳細の応答（`get` / 書き込みの `item`）は `body`（HTML 文字列）/ `js` / `css` を含む。**netloom はレダクトしない**（contact / ga4-orders と同じ判断 = replay の同一結果）。**カセットは `.cassettes/`（gitignore）にだけ置き、コミット・共有・`raw/` 配置をしない**。**テスト fixture は偽データのみ**。

## いつ使うか（トリガー）

- 「ランディングページを一覧 / 取得したい」「LP を登録 / 修正 / 削除したい」
- 「更新がフロント（`/landings/{id}`）に出ないのでキャッシュをクリアしたい」（`--clear-cache`）
- 「本番ではなく開発サーバーで試したい」（`NEWS_ENV=dev`。prod は未デプロイ）

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
make landing-page-list LIMIT=10 OFFSET=0          # 一覧（5 項目。`--format csv` は id,title,product_id,create_date,update_date）
make landing-page-get ID=3                        # 1 件（全項目 = 5 項目 + body / js / css。text は id / title / product_id）
make landing-page-create INPUT='{"title":"invented","body":"<p>invented</p>","product_id":4}' CLEAR_CACHE=1
make landing-page-update ID=3 INPUT='{"title":"invented (updated)"}' CLEAR_CACHE=1   # 部分更新（述べたフィールドだけ）
make landing-page-delete ID=3 CLEAR_CACHE=1
```

| 変数 | 既定 | 値 |
|---|---|---|
| `ID` | （get / update / delete で必須） | LP ID |
| `INPUT` | （create / update で必須） | 本文の JSON（または `INPUT=@body.json`。`title` / `body` / `product_id` は API の必須。**netloom は JSON であることだけ見る** — 必須の欠落は API の 400） |
| `LIMIT` / `OFFSET` | （API の既定 = limit 20・最大 100） | 一覧の件数 / 読み飛ばし（`list` のみ） |
| `CLEAR_CACHE` | （未指定） | `1` で書き込みの URL に `clear_cache=1`（**1 往復のまま**） |
| `NEWS_ENV` / `ALLOW_PROD_WRITE` / `FORMAT` / `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | news と同じ | |

- `csv` は**一覧のみ**。列は `id,title,product_id,create_date,update_date` の固定。**get / create / update / delete に `--format csv` は exit 2**（詳細の `item` は body（HTML）/ js / css を含む = 1 セルに HTML が入る表は表ではない）
- `text` は要約: 一覧 = `total` / `limit` / `offset` / `items: N`、1 件 = `id` / `title` / `product_id`、書き込み = `success` / `message` / `cache_cleared`
- `--fields` は無い（一覧の契約が 5 項目で固定。付けると exit 2）
- `--env prod` の書き込み（create / update / delete）は `--allow-prod-write` が無ければ exit 2（**prod は未デプロイでも門は動く**）。読み取りは不要

## 失敗の見分け（landing-page）

news と同じ（exit 1 / 2 / 3 / 124。付録 A.33）。**401** はキー、**404** は ID（prod は未デプロイなので list も 404）、**400** は「必須（title / body / product_id）・長さ超過（title 255 文字 / body 65,535 バイト / js・css 65,535 バイト）・product_id の実在」——どれも **API の文面がそのまま返る**ので、stderr の 1 行とカセットで読む。

## 証跡とオフライン再現（landing-page）

```sh
make landing-page-list LIMIT=10                   # 記録（.cassettes/<UTC>-landing-page-list-all.jsonl）
make landing-page-list LIMIT=10 REPLAY=.cassettes/20261019T120000Z-landing-page-list-all.jsonl
make landing-page-update ID=3 INPUT='{"title":"x"}' CLEAR_CACHE=1 REPLAY=.cassettes/…-landing-page-update-3.jsonl
```

- 1 コマンド = **2 frame**（`send` / `recv`）。失敗（400 / 401 / 404 / 500）もカセットに残り、replay は**同じ失敗**を返す
- `X-API-Key` と dev の `Authorization` は記録前に `[REDACTED]`
- **カセットは LP の本文（業務データ）を含み、レダクトされない**。`.cassettes/`（gitignore）にだけ置き、**コミット・共有・`raw/` 配置をしない**。カセットは**追記のみ**（編集・削除しない）

---

# product（EC-CUBE 商品 / 成分 / 資材 API。12 コマンド）

ショップの商品（コアの `dtb_product` 系）と成分（StrainAdmin）・資材（MaterialManager42）を、news と同じ形で扱う。環境（`--env dev|prod`）・認証（`X-API-Key` + dev の Basic = `SEO_API_KEY`）・prod ガード・カセットの規則は **news と同じ**（上の節）。**product / component / material は 1 つの送信元**（同じサービス・同じキー・同じ環境で、呼び出し元のスキルは 1 つの単位）。

**読み取り（v1）は常時、書き込み（C/U/D）は ContentSync42 プラグイン有効時のみ**（無効時は書き込みルートが未登録で **405**）。**商品の価格・在庫変更は通知系（`plg_price_cut` / `plg_in_stock`）と DB トリガーに波及する**（管理画面と同じ `postUpdate` 経由）。

**応答は商品と購買履歴（成分 / 資材の詳細は調達原価）を含む**: netloom はレダクトしない（replay の同一結果が証跡の意味。contact / ga4-orders と同じ判断）。**カセットは `.cassettes/`（gitignore）にだけ置き、コミット・共有・`raw/` 配置をしない**。**テスト fixture は偽データのみ**。

**本文はそのまま返る（netloom は解釈しない）**: 成功の `{success,id,message,item}`、失敗の `{success,false,error}`、SKU 重複の `matches` など、応答の形は店側の `ec-product-api` スキルの持ち物。netloom は status と本文をそのまま渡すだけ（§2.2）。

## EC-CUBE 系 7 送信元の認証ルール（この節が正）

| 送信元 | ヘッダ | 読む変数 |
|---|---|---|
| article / news / contact / cache / landing-page / **product** | `X-API-Key` | `SEO_API_KEY`（**共用。新規キーは作らない**） |
| ga4-orders | `X-GA4-API-Key` | `GA4_API_KEY`（**この 1 つだけ別**） |

- dev（`--env dev`）は上に加えて `HTTP_BASIC_AUTH_USER` / `HTTP_BASIC_AUTH_PASS` が要る（netloom が `Authorization: Basic <base64(user:pass)>` を組む。**本番は送らない**）。**どれか欠けたら 1 往復も送らず exit 2**（カセットも作らない。欠けた名前は stderr の 1 行に出る。値は出ない）
- **prod への書き込みは `--allow-prod-write` が必須**（読み取りは不要。読み取りに付けると exit 2。`--purge` を含む delete も同じ門）

## いつ使うか（トリガー）

- 「商品を一覧 / 取得したい」「SKU（商品コード）で引きたい」「商品を登録 / 更新 / 廃止 / 物理削除したい」
- 「成分・資材のマスタを見たい」「その商品の成分 / 資材を見たい」「購買履歴を見たい」
- 「開発サーバーで試したい」（`NEWS_ENV=dev`。prod は `NEWS_ENV=prod` + 書き込みは `ALLOW_PROD_WRITE=1`）

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
# 一覧（`--format csv` は固定の列。フィルタは API のパラメータ名のまま、指定時のみ載る）
make product-list LIMIT=20 OFFSET=0
make product-list LIMIT=100 STATUS=3 FORMAT=csv OUT=/tmp/abolished.csv
make product-list LIMIT=0 STOCK=out FORMAT=json            # limit=0 は items 空 + total だけ（件数取得）
make product-list NAME='CBD' CODE=CBD-LQ CATEGORY_ID=57 TAG_ID=12

# 1 件 / SKU 引き（`--format text` は id / name / code / status の要約）
make product-get ID=179
make product-get-by-code CODE=CBD-LQ-10-30                   # 重複コードは API の 409（matches 付き）= exit 1

# 作成 → 更新 → 削除（`--purge` は取り消し不可の物理削除。既定の廃止は冪等）
make product-create INPUT='{"name":"invented","classes":[{"price02":4980}]}'
make product-update ID=179 INPUT='{"status":1,"classes":[{"id":541,"price02":4480,"stock":20}]}'
make product-delete ID=179
make product-delete ID=179 PURGE=1                           # 参照があると 409（廃止を使って）

# 成分 / 資材（マスタ一覧は商品非依存。--product-id を付けるとその商品の紐づけ）
make product-component-list LIMIT=20 TYPE=effect              # effect_type はマスタ値 1|2|3
make product-component-list PRODUCT_ID=160 KEYWORD=crd        # その商品の成分等
make product-component-get ID=10                              # base_unit_cost / latest_purchase を含む（text は id / component_name / unit / is_enabled）
make product-component-purchases ID=10 LIMIT=20               # text は一覧と同じ（total / limit / offset / items: N）
make product-material-list PRODUCT_ID=164 SCOPE=class         # scope は --product-id と併用時のみ有効（単独は API が 400）
make product-material-list PRODUCT_CLASS_ID=541               # 規格単位のみ（product_id とは同時指定不可）
make product-material-get ID=1                                # text は id / name / material_code / unit / is_active
make product-material-purchases ID=1 LIMIT=20                 # text は一覧と同じ
```

| 変数 | 既定 | 値 |
|---|---|---|
| `ID` | （get / update / delete / 成分・資材の get と purchases で必須） | 商品 / 成分 / 資材の ID |
| `CODE` | （get-by-code で必須） | 商品コード（SKU）。path に入る |
| `INPUT` | （create / update で必須） | 本文の JSON（または `INPUT=@body.json`。`name` / `classes[]` は API の必須。**未知キーは API が 400 で弾く**） |
| `PURGE` | （未指定 = 廃止） | `1` で `?mode=purge`（**取り消し不可**。参照があると 409） |
| `LIMIT` / `OFFSET` | （API の既定 = limit 20・上限 100） | 5 つの list 形コマンドの件数 / 読み飛ばし（**指定時のみ載る。limit=0 は total だけ**） |
| `NAME` / `CODE` / `STATUS` / `STOCK` / `STOCK_STATUS` / `CATEGORY_ID` / `TAG_ID` | （未指定） | `list` のフィルタ（API のパラメータ名のまま。**`status` の既定は 1・2 で、3（廃止）は明示時のみ**） |
| `TYPE` / `PRODUCT_ID` / `KEYWORD` | （未指定） | `component-list` / `material-list` のフィルタ（`type` は component / effect / flavor / terpene） |
| `PRODUCT_CLASS_ID` / `SCOPE` / `IS_ACTIVE` | （未指定） | `material-list` のフィルタ（`scope` = product / class。`is_active` 未指定は有効・無効の両方） |
| `NEWS_ENV` / `ALLOW_PROD_WRITE` / `FORMAT` / `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | news と同じ | （`FORMAT` の語彙は下） |

- **フィルタの値は netloom が検証しない**（§2.2）: `status` / `stock` / `stock_status` / `type` / `scope` / `is_active` の嫌な値、`scope` の単独使用、`product_id` と `product_class_id` の同時指定は**API の 400 が答える**（そのまま返る）
- **日付フィルタ（`update_date_start` / `update_date_end`）は無い**（起票元が外部同期仕様と突き合わせ未確認。必要になったら別 issue）
- **`--clear-cache` は無い**（商品の書き込み API は `clear_cache` を受け付けず、プラグインが内部でキャッシュをクリアする。付けると exit 2）

## 出力の読み方（`FORMAT`）

| 値 | 内容 |
|---|---|
| `json`（既定） | API の文書のまま（`success` / `total` / `items` / `item` / `message` / `mode` など）。**値を解釈しない** |
| `csv` | **`list` のみ**。列は `id,name,code,price02,price02_inc_tax,stock,stock_unlimited,status,categories,main_image,update_date` の固定で、API が述べていない項目は空セル。**他のコマンドに `csv` は exit 2** |
| `text` | 一覧 = `total` / `limit` / `offset` / `items: N`（**成分 / 資材の一覧と 2 つの purchases も同じ** — 封筒だけを数え、item の項目は名指さない）、商品の 1 件 = `id` / `name` / `code` / `status`、**成分の 1 件 = `id` / `component_name` / `unit` / `is_enabled` / 資材の 1 件 = `id` / `name` / `material_code` / `unit` / `is_active`**（**価格・原価は出さない** = 商品 get の要約と同じ規則）、書き込み = `success` / `message` / `mode`（`mode` は delete の `abolish` / `purge`）。応答が述べた member だけを出し、**どれも述べていない応答は exit 1** |
| `verbatim` | 受信バイトそのまま |

## 状態コード（**そのまま返る。netloom はどれも解釈しない**）

| HTTP | 意味（店側のスキルの言葉） | 切り分け |
|---|---|---|
| 400 | パラメータ不正 / 本文の検証エラー / 未知キー / `scope` の単独使用など | 送った値と本文を確かめる（エラー文面はそのまま stderr に出る） |
| 401 | API キーが無効 | `netloom env check --source product` が読む名前を出す（失敗行にもこの 1 行が付く） |
| 404 | 対象なし（商品 / 成分 / 資材の ID） | ID を確かめる |
| 405 | 書き込みルート未登録（ContentSync42 無効） | プラグインの有効化を確かめる |
| 409 | 商品コード重複（`matches` 付き）/ 参照のある商品の purge | ID で引き直す（先頭を黙って返さない安全側の仕様）/ 廃止を使う |
| 500 | API キー未設定など（サーバー側） | `env` の `SEO_API_KEY` を確かめる |

## コマンド体系の差（7 送信元。**変えない**）

EC-CUBE 系は `list` / `get` / `create` / `update` / `delete` + `--limit` / `--offset` / `--input` / `--env` / `--allow-prod-write` で揃っている。**残る差は 3 つだけ**で、いずれも意図的: ① `ga4-orders` のヘッダ名（`X-GA4-API-Key`。別の資格情報）② `cache` は `clear` 1 動詞（エンドポイントが 1 つ）③ 書き込みの prod 門（安全要件）。**SKU 引きだけは動詞が別**（`get-by-code` — `get --code` に寄せるとルートの選択が送信元定義の外に出るため。設計 付録 A.37 判断 D4）。

## 失敗の見分け（product）

news と同じ（exit 1 / 2 / 3 / 124。付録 A.37）。

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 2xx | — |
| 1 | 400 / 401 / 404 / 405 / 409 / 500（API の応答のまま）・接続失敗・replay 不一致 | 上の状態コード表と stderr の 1 行、カセットを読む |
| 2 | 引数・設定（`--id` / `--code` / `--input` 欠落、JSON でない本文、語彙外の `--env` / `--format`、**prod 書き込みのフラグ無し**、読み取りのフラグ、dev ホスト未設定、credential 未設定、`--clear-cache` / `--fields` を付けた） | 引数と env を直す（**何も送っていない**） |
| 3 | I/O（`--out` / カセット / `@FILE`） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | 再実行、または owner に相談 |

## 証跡とオフライン再現（product）

```sh
make product-list LIMIT=20                      # 記録（.cassettes/<UTC>-product-list-all.jsonl）
make product-list LIMIT=20 REPLAY=.cassettes/20261021T120000Z-product-list-all.jsonl
make product-get-by-code CODE=CBD-LQ-10-30 REPLAY=.cassettes/…-product-get-by-code-cbd-lq-10-30.jsonl
```

- 1 コマンド = **2 frame**（`send` / `recv`）。失敗（400 / 401 / 404 / 405 / 409 / 500）もカセットに残り、replay は**同じ失敗**を返す
- `X-API-Key` と dev の `Authorization` は記録前に `[REDACTED]`
- **カセットは商品と購買履歴（成分 / 資材の詳細は調達原価）を含む**。`.cassettes/`（gitignore）にだけ置き、**コミット・共有しない**。`raw/` に置かない。カセットは**追記のみ**（編集・削除しない）

---

# openseo（ローカル OpenSEO の MCP over HTTP。5 コマンド）

OpenSEO（ローカル Docker のコンテナ `repo-open-seo-1`。`ghcr.io/every-app/open-seo`）の MCP エンドポイントを、
**VCR を通す薄いプロキシ**として扱う。プロジェクト一覧の解釈・キーワードの語彙検証・ページングの自動化・
リトライ・レート制限の待ち・値の解釈・正規化は**無い**（サーバーが返したエラーはそのまま返る）。仕様の正は
seo-operations の `openseo-mcp` スキル。**1 コマンド = 1 往復**（`initialize` なしで `tools/call` を 1 回 POST。
実測 2026-10-19）。

## いつ使うか（トリガー）

- 「OpenSEO のプロジェクト id を知りたい」（`list-projects`）
- 「〈キーワード〉の検索ボリューム / KD / CPC / intent を取りたい」（`keyword-metrics`）
- 「このドメインがどのクエリで上位にいるか見たい」（`ranked-keywords`）
- 「このドメインのオーガニック流入 / キーワード数 / 被リンクの概観を見たい」（`domain-overview`）
- 「〈キーワード〉の SERP で競合しているドメインを見たい」（`serp-competitors`）
- 「OpenSEO の取得を証跡付きで残したい」（カセットが証跡になる）

## 前提: ローカル Docker（credential は無い）

- 相手は**このマシンの Docker コンテナ**（`repo-open-seo-1`、`http://127.0.0.1:3001/mcp`）。**netloom は
  起動・停止しない** — `docker start repo-open-seo-1`（または seo の `start_openseo.sh`）は呼び出し側の作業
- **credential は要らない**（API キーもトークンも無い。netloom は環境変数を読まない）
- **落ちていれば exit 1**（`Connection refused` / `HTTP <status>` の 1 行。その失敗もカセットに残る）
- エンドポイントはコードの定数（`internal/adapters/sources` の 1 か所）。別マシンではそこを直す

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
# 1) プロジェクト一覧（id は次の 4 コマンドが取る。json / text / verbatim）
make openseo-list-projects

# 2) キーワードメトリクス（KEYWORDS はカンマ区切り → 配列で送られる）
make openseo-keyword-metrics PROJECT_ID=<id> KEYWORDS='h4cbh,h4cbh 副作用'
make openseo-keyword-metrics PROJECT_ID=<id> KEYWORDS='h4cbh' FORMAT=csv OUT=/tmp/kwm.csv

# 3) ランクキーワード（行は深い入れ子。json / text / verbatim。csv は無い）
make openseo-ranked-keywords PROJECT_ID=<id> TARGET=thch-vape.shop

# 4) ドメイン概観（1 オブジェクト。json / text / verbatim。csv は無い）
make openseo-domain-overview PROJECT_ID=<id> DOMAIN=thch-vape.shop

# 5) SERP 競合（KEYWORDS はカンマ区切り → 配列。行は provider の自由形式。json / text / verbatim。csv は無い）
make openseo-serp-competitors PROJECT_ID=<id> KEYWORDS='h4cbh,h4cbh 副作用'
```

バイナリを直接叩く場合は `bin/netloom openseo list-projects` /
`bin/netloom openseo keyword-metrics --project-id … --keywords …` /
`bin/netloom openseo ranked-keywords --project-id … --target …` /
`bin/netloom openseo domain-overview --project-id … --domain …` /
`bin/netloom openseo serp-competitors --project-id … --keywords …`。

| 変数 | 既定 | 値 |
|---|---|---|
| `PROJECT_ID` | （keyword-metrics / ranked-keywords / domain-overview / serp-competitors で必須） | OpenSEO のプロジェクト id（`list-projects` の `projects[].id`） |
| `KEYWORDS` | （keyword-metrics / serp-competitors で必須） | カンマ区切りのキーワード（配列で送る。個数の上限は server 側） |
| `TARGET` | （ranked-keywords で必須） | ドメインまたは URL（そのまま送る） |
| `DOMAIN` | （domain-overview で必須） | 概観を取るドメイン（そのまま送る） |
| `FORMAT` | `json` | keyword-metrics: `json` / `csv` / `text` / `verbatim`、他の 4 つ: `json` / `text` / `verbatim` |
| `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | 他と同じ | |

## 出力の読み方

- `json`（既定）は**ツール結果の構造化文書**（`structuredContent`）: list-projects = `{projects:[…], meta}`、
  keyword-metrics = `{keywords:[…], meta}`（`search_volume` / `keyword_difficulty`（null あり）/ `cpc`（null あり）/
  `main_intent` / `competition` / `monthly_searches`）、ranked-keywords = `{keywords:[…], totalCount, meta}`（行は
  `keyword_data` / `ranked_serp_element` の深い入れ子）、domain-overview = **1 オブジェクト**
  （`domain` / `organicTraffic` / `organicKeywords` / `backlinks` / `referringDomains` / `hasData` / `fetchedAt` / `meta`。
  null の値あり。実測 2026-10-19）、serp-competitors = `{competitors:[…], meta}`（**行は provider の自由形式**。
  実測では空の配列）。`_meta` は `verbatim` で読める
- `csv` は **keyword-metrics のみ**。列は `keyword,search_volume,keyword_difficulty,cpc,competition,main_intent`
  の固定で、null（スキルで `—` の値）は空セル。他の 4 コマンドの `--format csv` は exit 2
  （ranked-keywords は深い入れ子、domain-overview は 1 オブジェクト、serp-competitors は行が自由形式 — 列の選択 = 解釈になるため）
- `text` は provider のテキスト（人が読む表。`keyword | volume | KD | CPC | competition | intent`）
- **値を解釈しない**: プロジェクトの意味・キーワードの採否・順位の比較は呼び出し側

## 失敗の見分け（openseo）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 2xx（JSON-RPC の result） | — |
| 1 | **Docker が落ちている / 接続失敗**・4xx / 5xx・JSON-RPC の error・ツールの isError・replay 不一致 | `docker ps \| grep open-seo` → `docker start repo-open-seo-1`。それ以外は stderr の 1 行とカセットを読む |
| 2 | 引数・設定（`--project-id` / `--keywords` / `--target` / `--domain` 欠落、空のキーワード、csv の語彙外、`--replay` と `--cassette` の併用） | 引数を直す |
| 3 | I/O（`--out` / カセット） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | 再実行、または owner に相談 |

## 証跡とオフライン再現（openseo）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-openseo-<command>-<target>.jsonl）
make openseo-keyword-metrics PROJECT_ID=<id> KEYWORDS='h4cbh'

# 同じ request で再生（ネットも Docker も使わない。method + url + payload が一致しないと exit 1）
make openseo-keyword-metrics PROJECT_ID=<id> KEYWORDS='h4cbh' REPLAY=.cassettes/…-openseo-keyword-metrics-h4cbh.jsonl
make openseo-domain-overview PROJECT_ID=<id> DOMAIN=thch-vape.shop REPLAY=.cassettes/…-openseo-domain-overview-thch-vape-shop.jsonl
make openseo-serp-competitors PROJECT_ID=<id> KEYWORDS='h4cbh,h4cbh 副作用' REPLAY=.cassettes/…-openseo-serp-competitors-h4cbh.jsonl
```

- 1 コマンド = **2 frame**（`send` = JSON-RPC の `tools/call`、`recv` = JSON-RPC の応答）。失敗もカセットに残る
- **カセットはプロジェクト id と実キーワードのメトリクスを含む**ので `.cassettes/`（gitignore）にだけ置き、
  **コミット・共有しない**。`raw/` に置かない。カセットは**追記のみ**（編集・削除しない）

---

# gmail（送信。既存の Gmail MCP サーバーを再利用）

Gmail の送信（`@gongrzhe/server-gmail-autoauth-mcp`、stdio）を **VCR を通す薄いプロキシ**として扱う。
宛先の形式・件名・本文の検証は**無い**（値はそのまま送る）。**OAuth はサーバー側**で、credential は
サーバーが `~/.gmail-mcp/` から読む（netloom は読まない）。**1 コマンド = 1 MCP 往復**（`tools/call` 1 回。
実測 2026-10-19）。

**送信は副作用**（実メールが 1 通飛ぶ）。live の送信は owner の承認があるときだけ実行する。

## いつ使うか（トリガー）

- 「メールを送って」「アラートをメールで出して」（`send-email`）
- 「送信の証跡をカセットに残したい」（1 コマンド = 1 往復が記録される）

## 前提: サーバー側の OAuth（netloom は credential を読まない）

- 相手は **`npx -y @gongrzhe/server-gmail-autoauth-mcp`**（stdio）。`npx` が PATH に要る
- **OAuth はサーバー側**で、credential はサーバーが `HOME` の `~/.gmail-mcp/`
  （`gcp-oauth.keys.json` / `credentials.json`）から読む。**netloom は読まない**（環境変数も無い）
- **送信は副作用**: live は実メールが飛ぶ。owner の承認なしに実行しない
- **live は `--allow-send`（make は `ALLOW_SEND=1`）が必須**（issue #42）。無ければ
  **1 往復も送らず exit 2**（`npx` も起動しない・カセットも作らない。メッセージにフラグ名が出る。**値は出ない**）。
  `REPLAY=<カセット>` は**要らない**（往復しない = 送信しない）。他のコマンドに付けると exit 2
  （効かないフラグを黙って無視しない）
- ネットワークが無い・再現したいときは `REPLAY=<カセット>`（メールは飛ばない・`ALLOW_SEND` も要らない）

## 実行（1 コマンド = 1 往復 = カセット 1 セッション）

```sh
# 送信（live = 実際にメールが飛ぶ。owner 承認のうえで。ALLOW_SEND=1 が必須）
make gmail-send-email TO='alert@example.test' SUBJECT='日次アラート' BODY='本文です' ALLOW_SEND=1
make gmail-send-email TO='a@example.test, b@example.test' SUBJECT='…' BODY='…' ALLOW_SEND=1   # 宛先はカンマ区切り → 配列
make gmail-send-email TO='alert@example.test' SUBJECT='日次アラート' BODY='@/path/to/body.txt' ALLOW_SEND=1   # 本文をファイルで渡す（改行の多い本文はこれ）
make gmail-send-email TO='alert@example.test' SUBJECT='日次アラート' BODY='@digest.md' HTML_BODY='@digest.html' ALLOW_SEND=1   # HTML パートも同じ 1 通で送る（表示を整えたいとき）

# 記録済みカセットから再現（ネットも npx も使わない。メールは飛ばない。ALLOW_SEND 不要）
make gmail-send-email TO='alert@example.test' SUBJECT='日次アラート' BODY='本文です' REPLAY=.cassettes/…-gmail-send-email-to1-d6a46423.jsonl
```

バイナリを直接叩く場合は `bin/netloom gmail send-email --to … --subject … --body … [--html-body …] --allow-send`
（`--allow-send` を忘れると exit 2 で送らない）。

| 変数 | 既定 | 値 |
|---|---|---|
| `TO` | （必須） | 宛先。カンマ区切り（1 件でも配列で送る。形式はサーバーの判定） |
| `SUBJECT` | （必須） | 件名（そのまま送る） |
| `BODY` | （必須） | 本文（そのまま送る。`@FILE` 可: `BODY='@/path/to/body.txt'` — ファイルのバイトがそのまま本文になる（issue #34）。本文が `@` で始まる場合はファイルとして読まれる） |
| `ALLOW_SEND` | （live は必須） | `1` で実送信を承認する（`--allow-send`。**無ければ live は exit 2 で 1 通も送らない・npx も起動しない**。`REPLAY` は不要） |
| `HTML_BODY` | （任意） | **同じ 1 通の HTML パート**（`--html-body`。issue #64）。`HTML_BODY='<b>太字</b>'` または `HTML_BODY='@digest.html'`（ファイルのバイトがそのまま）。**付ければ `body` と `htmlBody` が同じ `tools/call` に載る**（往復は増えない）。**実サーバーは `mimeType` を同時に送らないと `htmlBody` を使わない**（既定 text/plain）ので、netloom は `htmlBody` を名指したときだけ **`mimeType: multipart/alternative` も同じ引数に載せる**（issue #66。付けなければ 3 メンバーのまま） |
# mcp（任意の stdio MCP サーバー。`call` = 1 tools/call / `tools` = 1 tools/list）

netloom に送信元が無い MCP サーバー（stdio）でも、**往復をカセットに残したいとき**は `mcp call` を使う（設計 **A.38**。issue #65）。**サーバーも pin もツール名も netloom は持たない** — `--server` / `--tool` が呼び出し側の表明で、netloom は `npx -y <server>` を起動し、`initialize` → `notifications/initialized` → `tools/call` 1 回を記録する。

**ツール名・引数名を知りたいとき**は `mcp tools` を使う（issue #69）。`call` が名指す前にサーバーの offering（`name` / `description` / `inputSchema`）を読む — `call` 自体は今も `tools/list` を呼ばない。

## いつ使うか（トリガー）

- 「MCP サーバーの取得を netloom 経由にして証跡を残したい」（`mcp call`）
- 「このサーバーが何のツールを持っているか知りたい」（`mcp tools`。`call` の `--tool` / `--args` を書く前に 1 回読む）
- 「失敗したときにサーバーが何を返したか知りたい」（失敗もカセットに残る）
- 送信元があるもの（gsc / ga4 / meta / product など）は**そちらを使う**（語彙・整形・受入が済んでいる）

## 実行（1 コマンド = 1 往復 = カセット 1 セッション）

```sh
# LinkedIn のフィード（例。 サーバーもツール名も呼び出し側が書く）
netloom mcp call --server linkedin-mcp-tools@2.0.3 --tool get_feed \
  --args '{"count":25}' --env LINKEDIN_PROFILE_DIR --out feed.json

# make から
make mcp-call SERVER='linkedin-mcp-tools@2.0.3' TOOL=get_feed ARGS='{"count":25}' \
  ENV_NAMES=LINKEDIN_PROFILE_DIR OUT=feed.json

# 記録済みカセットから再現（サーバーを起動しない。npx も要らない）
netloom mcp call --server linkedin-mcp-tools@2.0.3 --tool get_feed --args '{"count":25}' --replay .cassettes/…jsonl

# ツール一覧を読む（1 コマンド = initialize → initialized → tools/list の 1 往復。tools/call は呼ばない）
netloom mcp tools --server linkedin-mcp-tools@2.0.3 --out tools.json
# → {"tools":[…]} がそのまま（既定 json。FORMAT=text で 1 行 1 ツール: 名前[タブ]説明の 1 行目）

# make から
make mcp-tools SERVER='linkedin-mcp-tools@2.0.3' OUT=tools.json
make mcp-tools SERVER='<同じ spec>' REPLAY=.cassettes/…-mcp-tools-<server>.jsonl   # サーバーを起動しない
```

| 変数 | 既定 | 値 |
|---|---|---|
| `SERVER` | （必須） | サーバーの npm spec（`npx -y <spec>`。**pin は呼び出し側の表明**。空白を含む spec は exit 2） |
| `TOOL` | （必須） | ツール名（**そのまま送る**。存在しない名前はサーバーの答え = exit 1。空・空白のみは exit 2） |
| `ARGS` | `{}` | 引数の JSON または `@FILE`（**JSON オブジェクトのみ**。member 名も値も検証しない。JSON でなければ exit 2、ファイルが読めなければ exit 3） |
| `ENV_NAMES` | （任意） | 子に渡す**変数名**（カンマ区切り。**値は環境から読む** — `NAME=VALUE` は exit 2。未設定の名前は exit 2 で何も起動しない。名指した値は出力で `[REDACTED]`） |
| `FORMAT` | `json` | `json` / `text` / `verbatim`（**csv は無い**） |
| `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | 他と同じ | `--cassette` / `--out` / `--replay` / `--timeout`（既定 300 秒） |

## 出力の読み方

- `json`（既定）= **ツールの文書**。結果の最初の text ブロックが JSON なら indent 2、そうでなければ**文字列としての JSON**。text ブロックが無く `structuredContent` があればそれ。**MCP の封筒（`content` / `isError`）は書かない**
- `text` = text ブロックそのまま、`verbatim` = 受信した result のバイトそのまま（証跡用。封筒ごと見たいときはこれ）
- `mcp tools` の `json`（既定）= **サーバーの `result`（`{"tools":[...]}`）そのまま**（indent 2。`inputSchema` もここに載っている = `call` の `--args` を書く材料）。`text` = 1 行 1 ツール（`名前[タブ]説明の 1 行目`。説明の無いツールは名前だけ）。`--filter` は無い（`json` + `jq` で足りる）
- 迷ったら `cassette show` で生の frame を見る（`text` / `verbatim` と同じものが入っている）

## 失敗の見分け（mcp）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | `tools/call` / `tools/list` 成功 | — |
| 1 | `isError` / JSON-RPC エラー / **replay 不一致** / ツール名が存在しない / `tools` の答えが `result.tools` を持たない（捏造しない） | stderr の 1 行とカセットを読む（provider の文言がそのまま入っている） |
| 2 | 引数・設定（`--server` / `--tool` の欠落・空白、`--args` が JSON オブジェクトでない、`--env` の代入・空の名前・**未設定の名前**、`--format csv`、`--replay` と `--cassette` の併用、`tools` に `--tool` / `--args` を付けた） | 引数を直す（値はコマンドラインに書かない） |
| 3 | I/O（`--out` / カセット / `--args @FILE`） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | サーバーの重さを見る（ログインが要るサーバーは遅い）。再実行 |
| 127 | `npx` / `node` が無い | Node を入れる（`--replay` は要らない） |

## 証跡・秘匿・注意

- カセットは **`.cassettes/<UTC>-mcp-call-<server>-<tool>.jsonl`**（**サーバーとツールが run の identity**）。`tools` は **`.cassettes/<UTC>-mcp-tools-<server>.jsonl`**（ツール名を名指さないのでサーバーだけ）。`--cassette` / `REPLAY=` で置き場を変えられる
- **記録前にレダクト**される: `Cookie` / `set-cookie` / `authorization` / `*_token` / `*_key` は**名前で値が消える**（`internal/adapters/redact`。新しい名前は 0 行）。**`--env` で名指した値もレダクト対象**。**未確認**: cookie 名が JSON の member 名でなく生のテキストで返る場合は初回 live でカセットを確認する（A.38 / §11 N36）
- **プロファイル（クッキーを含む）は netloom がコピーも変更もしない** — パスを `--env` で渡すだけ（子の環境は PATH / HOME + 名指した名前だけ）。**live の利用条件（LinkedIn の ToS・レート）は呼び出し側の責任**
- カセットには**引数と provider のデータ**が入るので `.cassettes/`（gitignore）にだけ置き、**コミット・共有・`raw/` 配置をしない**（追記のみ）
- **netloom は `tools/list` を呼ばない**ので、ツール名・引数の正しさはサーバーの答えでしか分からない（§2.2）

# Meta Graph API（Facebook Page / Instagram。2 送信元。5 コマンド）

Meta Graph API（base URL は `https://graph.facebook.com/v25.0`。呼び出し側の `fetch_meta_metrics.py` の `API_VER` と同じ）を**VCR を通す薄いプロキシ**として扱う。fields / metric の語彙検証・ページングの自動化・リトライ・レート制限の待ち・値の解釈・正規化は**無い**（Meta が返したエラーはそのまま返る）。**1 コマンド = 1 往復**。

**送信元が 2 つあるのは credential が 2 系統だから**: netloom の送信元は「host + credential」が 1 対 1。Facebook Page の投稿は `PAGE_TOKEN`、Instagram は `USER_TOKEN` を読む（呼び出し側の `PAGE_ID` / `IG_ACCOUNT_ID` は**credential ではなく対象** — `--page-id` / `--ig-account-id` で渡す）。

## いつ使うか（トリガー）

- 「Facebook Page の投稿一覧がほしい」（`meta-page posts`）
- 「この Facebook 投稿 1 件の中身/インサイトがほしい」（`meta-page post` / `post-insights`）
- 「Instagram のメディア一覧/インサイトがほしい」（`meta-instagram media` / `media-insights`）
- 「Meta の取得を証跡付きで残したい」（カセットが証跡になる）

## 前提: `PAGE_TOKEN` / `USER_TOKEN`（別々のトークン）

- **meta-page は `PAGE_TOKEN`、meta-instagram は `USER_TOKEN`** を環境変数で渡す（netloom が読む。値はコマンドラインに書かない — シェル履歴に残る）。**未設定なら 1 往復も送らず exit 2**
- 呼び出し側の置き場は env ファイル（例: `thch-vape.shop/.env.d/issues.env`）で、**ワークスペース外・chmod 600・コミットしない**。**このマシンにはまだ無いので live は未実行**（設計書 付録 A.21 の未確認 / §11 N18）
- トークンは **`Authorization: Bearer` ヘッダ**で送る（呼び出し側の `access_token` クエリではない）。理由: URL はカセットに記録されるため（ヘッダは名前ごと `[REDACTED]` になる）。**Graph API が Bearer を受け付けるかは live で未確認** — 401 が返ったら owner に相談（クエリ方式 + URL レダクトへの切替になる）
- base URL はコードの定数（`internal/adapters/sources` の 1 か所。2 送信元が共有）。別マシン・別バージョンではそこを直す

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
# 1) Facebook Page の投稿一覧（--fields / --limit はそのまま送る。ページングは回さない）
make meta-page-posts PAGE_ID=<page-id> FIELDS='id,message,created_time' LIMIT=100

# 2) Facebook 投稿 1 件 / そのインサイト（METRICS は必須。PERIOD は任意）
make meta-page-post POST_ID=<post-id> FIELDS='id,message'
make meta-page-post-insights POST_ID=<post-id> METRICS='post_fan_reach,post_engagements' PERIOD=lifetime

# 3) Instagram のメディア一覧 / メディアのインサイト（USER_TOKEN）
make meta-instagram-media IG_ACCOUNT_ID=<ig-id> FIELDS='id,caption,media_type,permalink,timestamp' LIMIT=100
make meta-instagram-media-insights MEDIA_ID=<media-id> METRICS='reach,likes,comments'
```

バイナリを直接叩く場合は `bin/netloom meta-page posts --page-id … [--fields …] [--limit N]` /
`bin/netloom meta-page post --post-id …` / `bin/netloom meta-page post-insights --post-id … --metrics … [--period P]` /
`bin/netloom meta-instagram media --ig-account-id …` / `bin/netloom meta-instagram media-insights --media-id … --metrics …`。

| 変数 | 既定 | 値 |
|---|---|---|
| `PAGE_ID` / `POST_ID` / `IG_ACCOUNT_ID` / `MEDIA_ID` | （それぞれのコマンドで必須） | 対象の id（呼び出し側が渡す。netloom は一覧も対応表も持たない） |
| `FIELDS` | （任意） | `--fields` のカンマ区切り（post / posts / media）。**語彙検証は無い** |
| `METRICS` | （insights で必須） | `--metrics` のカンマ区切り（post-insights / media-insights） |
| `PERIOD` | （任意） | `--period`（post-insights のみ。呼び出し側の例は `lifetime`） |
| `LIMIT` | （任意） | `--limit`（posts / media。そのまま渡す。0 以下も netloom は判定しない） |
| `FORMAT` | `json` | `json` / `text` / `verbatim`（**csv は無い**） |
| `CASSETTE` / `OUT` / `REPLAY` / `TIMEOUT` | 他と同じ | |

## 出力の読み方

- `json`（既定）は**ツール結果のテキストを JSON 文書として**書く: テキストが JSON 文書ならパースしてインデント 2、
  そうでなければ**文字列としての JSON 表現**（サーバーの成功応答は `Email sent successfully with ID: …` の文）
- `text` は provider のテキストそのまま（人が読む）。`verbatim` は受信した result のバイトそのまま（証跡用）
- **送信の成否は exit code と `isError` で見る**（失敗は exit 1 で、provider の文言が stderr の 1 行）

## 失敗の見分け（gmail）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 送信できた（result の text に message id） | — |
| 1 | ツールの isError・JSON-RPC の error（サーバー側の OAuth 失敗・宛先の拒否など）・replay 不一致 | stderr の 1 行とカセットを読む。OAuth なら `~/.gmail-mcp/` の状態を（サーバーの領分として）確認する |
| 2 | 引数・設定（`--to` / `--subject` / `--body` 欠落、**`--html-body` が何も述べない**（空 / 空白のみ / 空のファイル）、**`--allow-send` なしの live 送信**、`--allow-send` を他のコマンドに付けた場合、`--format csv`、`--replay` と `--cassette` の併用） | 引数を直す（送信の承認は `--allow-send` / `ALLOW_SEND=1`） |
| 3 | I/O（`--out` / カセット / `--body` / `--html-body` の `@FILE`） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | 再実行、または owner に相談 |
| 127 | `npx` が無い | Node / `npx` を入れる（`npx --version`） |

## 証跡とオフライン再現（gmail）

```sh
# 記録（live。ALLOW_SEND=1 が必須。CASSETTE 省略時は .cassettes/<UTC>-gmail-send-email-to<N>-<sha8>.jsonl = 宛先数と宛先集合のハッシュ。アドレス自体は出ない（issue #70））
make gmail-send-email TO='alert@example.test' SUBJECT='…' BODY='…' ALLOW_SEND=1

# 同じ request で再生（ネットも npx も使わない。tools/call の params が一致しないと exit 1）
make gmail-send-email TO='alert@example.test' SUBJECT='…' BODY='…' REPLAY=.cassettes/…-gmail-send-email-to1-d6a46423.jsonl
```

- 1 コマンド = init / initialized / tools/call の send と 2 つの recv。失敗もカセットに残る
- **カセットは宛先・件名・本文（`--html-body` を名指したときは HTML も）を含む**ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有しない**。
  `raw/` に置かない。カセットは**追記のみ**（編集・削除しない）
- `json`（既定）は provider の応答を整形したもの: 一覧 = `{data:[…], paging:{…}}`、単一 = `{id, message, created_time, …}`、insights = `{data:[{name, period, values:[{value}]}]}`
- `text` は 1〜2 行の要約: 一覧・insights は `data: <件数>` と、あれば `paging.next`（次の 1 往復に使う URL。**netloom は回さない**）、単一 post は `id` / `created_time`
- `verbatim` は受信バイトそのまま（証跡用）
- **値を解釈しない**: どの metric を採用するか・DB への投入（`platform_data.db`）・前回値との比較は呼び出し側（現行の `fetch_meta_metrics.py` の側）

## 失敗の見分け（meta）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 2xx | — |
| 1 | 4xx / 5xx（401 は token、403 は権限/承認、429 はレート制限）・接続失敗・replay 不一致 | stderr の 1 行とカセットを読む。**live の 401 は Bearer 未確認の可能性**（owner に相談） |
| 2 | 引数・設定（id / `--metrics` の欠落、`PAGE_TOKEN` / `USER_TOKEN` 未設定、csv、`--replay` と `--cassette` の併用） | 引数・env を直す |
| 3 | I/O（`--out` / カセット） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | 再実行、または owner に相談 |

## 証跡とオフライン再現（meta）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-<source>-<command>-<target>.jsonl）
make meta-page-post-insights POST_ID=<post-id> METRICS='post_fan_reach,post_engagements'

# 同じ request で再生（ネットも token も使わない。method + url + payload が一致しないと exit 1）
make meta-page-post-insights POST_ID=<post-id> METRICS='post_fan_reach,post_engagements' REPLAY=.cassettes/…-meta-page-post-insights-<post-id>.jsonl
```

- 1 コマンド = **2 frame**（`send` = GET + url、`recv` = status + 応答）。失敗もカセットに残る
- **カセットは投稿本文と指標を含む**ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有しない**。`raw/` に置かない。カセットは**追記のみ**（編集・削除しない）

---

# mysql（EC-CUBE の MySQL。SSH トンネル + **読み取り専用**クエリ）

## いつ使うか（トリガー）

- 「商品データを確認して」「在庫を見て」「コンポーネントをコピーして」（コピー元の確認まで）
  「注文を調べて」「この URL（`/strainadmin/product/165/…`）の商品は？」のような **EC-CUBE の DB を見る依頼**
- 既存の `.github/skills/eccube-db` の手順（`lsof` で確認 → `start_mysql_tunnel.sh` → `mysql -h 127.0.0.1 -P <port> … -e "SELECT …"`）を置き換える用途
- **使わない場面**: 書き込み（INSERT / UPDATE / DELETE / DDL / `CALL`）。**netloom には書き込みが無い**（呼び出し側のスクリプトに残る）。商品・記事の更新は管理画面か呼び出し側の資産で行う

## 前提: `MYSQL_*` と `SSH_ALIAS`（値は env ファイル、netloom は名前だけ知る）

- `MYSQL_HOST` / `MYSQL_PORT` / `MYSQL_DATABASE`（**接続の同一性**。credential ではない）/ `MYSQL_USER` / `MYSQL_PASSWORD`（live の credential）/ `SSH_ALIAS`（ssh config の alias）
- **`SSH_ALIAS` は env ファイルに無い**ことが多い（移管元のスキルも `SSH_ALIAS=<alias> bash start_mysql_tunnel.sh` の形で渡していた）— `export SSH_ALIAS=<alias>` で渡す
- **コードに既定値は無い**: 1 つでも未設定なら **1 往復も送らず exit 2**（メッセージに変数名。値は出ない）
- **ポートは `MYSQL_PORT` の 1 か所**（トンネルのローカル側 = クエリが繋ぐ先。`LOCAL_PORT` は無い）。far end は定義の定数（`127.0.0.1:3306`）
- 本番 / DEV は**呼び出し側の env ファイル**の違いだけ（同じ変数名）。`--env dev|prod`（既定 dev）はカセットの同一性とトンネルの系統を表す

```sh
# 例: env ファイルを読んでから実行（値は出力しない）
set -a; source /path/to/.env.d/mysql_xs_dev.env; set +a && export SSH_ALIAS=<dev の alias>
```

## 実行（トンネル → 1 クエリ = 1 往復）

```sh
# 1) トンネル（**冪等**。既に listening なら何も起動せず同じ 1 行で exit 0）
make mysql-tunnel MYSQL_ENV=dev
make mysql-tunnel-status          # dial で判定（listening = exit 0 / そうでない = exit 1）

# 2) 読み取り（**SELECT / SHOW / DESCRIBE / DESC / EXPLAIN の 1 文だけ**）
make mysql-query SQL='SELECT id, name, product_status_id FROM dtb_product WHERE id = 165' FORMAT=csv
make mysql-query SQL='SELECT COUNT(*) AS products FROM dtb_product' FORMAT=csv MYSQL_ENV=dev
make mysql-query SQL=@query.sql FORMAT=json CASSETTE=.cassettes/local.jsonl
```

- 送れる語彙は **5 語だけ**。`INSERT` / `UPDATE` / `DELETE` / DDL / `CALL` / `WITH … SELECT` / **複文**は **1 往復も送らず exit 2**（カセットも作らない）。加えて接続は **`START TRANSACTION READ ONLY`** で開く
- **`--sql @FILE` のファイルのバイトが文**（末尾改行も含む）。同じ文を再生するには同じバイトで渡す
- `--sql` はシェルの引用に注意（値に `'` を含む文は `@FILE` が安全）
- トンネルは **netloom が起動してデタッチするだけ**（`ssh -N -f`）で、netloom はプロセスを所有しない。止めるのは呼び出し側（openseo の Docker と同じ）

## 出力形式（`FORMAT` / `--format`）

| 値 | 内容 |
|---|---|
| `json`（既定） | 結果文書: `{"columns":["id","name"],"rows":[[165,"…"]]}`（行 = 列順の値の配列。NULL は `null`） |
| `csv` | 列をヘッダにした表（表計算にそのまま入る。**NULL は空セル**） |
| `text` | `columns: id, name` と `rows: 1` の要約（人が読む。値を読むのは csv / json） |

- **`verbatim` は無い**（`FORMAT=verbatim` は exit 2）
- 値の型は DB が返したまま: 数値は数値、文字列は文字列、NULL は null。**バイナリ列はテキストになる**（UTF-8 でないバイトは置換文字。base64 は作らない）
- 1 応答の上限は 16 MiB（超えたら拒否。**切り詰めない**）— 広い表は `LIMIT` で絞る（netloom はページングを回さない）

## 失敗の見分け（mysql）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 読み取り成功 / トンネル起動・listening | — |
| 1 | DB が返したエラー（表が無い 1146 など）・接続失敗・ssh の失敗・`tunnel-status` = していない・replay 不一致 | stderr の 1 行（DB / ssh の言葉）とカセットを読む。表名・文の誤りは呼び出し側で直す |
| 2 | 読み取り専用でない文 / 複文 / `--sql` 欠落 / `MYSQL_*` 未設定 / `--env` の語彙外 / `verbatim` / tunnel に `--cassette` | 引数と env を直す（**何も送っていない**） |
| 3 | I/O（`--out` / カセット） | パスを直す |
| 124 | timeout（`--timeout`。既定 300 秒） | 文を絞る・トンネルを確かめる |
| 127 | `ssh` が無い | ssh を入れるか PATH を直す |

- **`tunnel-status` は exit code が答え**（0 = listening / 1 = していない）。stderr の 1 行がアドレスを述べる
- 失敗の frame も残る: DB のエラーは `recv` の `error`、接続失敗は `send` だけ

## 証跡とオフライン再現（mysql）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-mysql-query-<env>.jsonl）
make mysql-query SQL='SELECT COUNT(*) AS products FROM dtb_product' FORMAT=csv

# 同じ文で再生（**ssh も MySQL もネットも使わない**。SQL + 接続の同一性（env / host / port / database）が一致しないと exit 1）
make mysql-query SQL='SELECT COUNT(*) AS products FROM dtb_product' FORMAT=csv REPLAY="$C"
```

- 1 コマンド = **2 frame**: `send` = `{sql, env, host, port, database}`、`recv` = `{columns, rows}`（または `error` / `partial`）
- **照合キーは SQL + 接続の同一性**なので、**DEV のカセットが本番のクエリに答えない**。同じ文を 2 回記録したカセットは**最初の記録**が返る（§5.1 の規則 = このコマンドは文を 1 回だけ要求するので最初の記録。issue #14）
- **credentials はカセットに入らない**（`MYSQL_PASSWORD` の実値は stdout / stderr / カセットのどこにも出ない。接続の同一性にも password / user を入れていない）
- **カセットはショップの行（PII・売上を含みうる）を持つ**ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有しない**。`raw/` に置かない。カセットは**追記のみ**（編集・削除しない）
- **本番 DB への読み取りは owner の承認が前提**（呼び出し側の本番 env ファイルを使う）。netloom 側の実測は DEV の読み取りだけ（2026-10-19。付録 A.23）

---

# site（自サイトの死活監視とデバッグ。判定を送信元定義に持つ唯一の送信元）

## いつ使うか（トリガー）

- 「サイトの動作確認をして」『デプロイ後に 500 が出ていないか見て』『キャッシュクリア後に確認して』
- 「フロント / マイページ / 管理画面の死活を見て」（面を変えて同じ語彙で）
- **流用の curl 手順（`curl_ec_check.sh` / ローカル検証ガイド / スキル 3 本 / AGENTS.md の curl 例）を置き換える用途**
- **使わない場面**: 常駐監視・スケジューラ・通知（cron / UptimeRobot 等は呼び出し側） / HTML の解釈・SEO 判定・スクレイピング / ログイン以外のフォーム送信・破壊的操作 / 負荷試験（netloom は逐次実行）

## 前提: 環境ごとの root と credential（名前だけを知る）

| 環境 | root | Basic | ログイン（環境別の名前 / 旧名はフォールバック） |
|---|---|---|---|
| `--env local` | `EC_LOCAL_BASE_URL`（未設定 = exit 2） | 送らない | `EC_LOCAL_ADMIN_ROUTE` + `EC_LOCAL_ADMIN_USER` / `EC_LOCAL_ADMIN_PASS`（旧名 `ECCUBE_ADMIN_ROUTE` / `ECCUBE_ADMIN_USER` / `ECCUBE_ADMIN_PASS`） |
| `--env dev`（既定） | `EC_DEV_BASE_URL`（EC-CUBE API と同じ変数） | `HTTP_BASIC_AUTH_USER` / `HTTP_BASIC_AUTH_PASS` | `EC_DEV_ADMIN_ROUTE` + `EC_DEV_ADMIN_USER` / `EC_DEV_ADMIN_PASS`（旧名は local と同じ 3 つ） |
| `--env prod` | 定数（live の shop） | 送らない | `EC_PROD_ADMIN_ROUTE` + `EC_PROD_ADMIN_USER` / `EC_PROD_ADMIN_PASS`（読み取りのみ。旧名は local と同じ 3 つ） |

- **管理画面と会員の credential は環境別の名前が先、旧名はフォールバック**（issue #25）: `EC_<ENV>_ADMIN_ROUTE` / `_ADMIN_USER` / `_ADMIN_PASS` / `_MEMBER_EMAIL` / `_MEMBER_PASSWORD`（`<ENV>` = `LOCAL` / `DEV` / `PROD`。`--env` が選ぶ。`EC_DEV_BASE_URL` と同じ family）。**旧名はその環境の環境別名が未設定のときだけ読み、変数ごとに「最初に設定されている名前が勝つ」**（混在も 1 組 — 環境別名の email + 旧名の password は pair）。旧名は**互換（移行期）および dev と prod で同じ値の店舗のための共有セット**（推奨の名前は環境別名）。**管理ルートは公開値ではない**（隠しパス）ので prod でも定数のままにしない。
- **マイページの会員ログインは任意**: `EC_<ENV>_MEMBER_EMAIL` / `EC_<ENV>_MEMBER_PASSWORD`（または旧名）の**両方**があるときだけログイン後も見る。無ければ未ログイン範囲（`/mypage/login` の 200 と保護ページの 302 → login）だけ。**片方だけは exit 2**
- **必須が欠けたら 1 往復も送らず exit 2**（カセットも作らない。メッセージは欠けた変数名を両方の綴りで出す。値は出さない。`--target front` は credential 不要で回せる）
- **`--replay` は route の名前だけを読む**（URL = 照合キー）し、credential は読まない
- **値はカセットにも stdout / stderr にも出ない**（password 系と Cookie の値は `[REDACTED]`。Set-Cookie は `Path` / `HttpOnly` などの属性だけ残る）

```sh
# 例: env ファイルを読んでから実行（値は出力しない）
set -a; source /path/to/.env.d/site.env; set +a
```

## 実行（面 × 環境。URL は定義 1 か所）

```sh
make site-check SITE_ENV=local SITE_TARGET=front SITE_PRODUCT_ID=1   # 人が読む一覧（既定 format = text）
make site-check SITE_ENV=dev   SITE_TARGET=all                       # 3 面（ログイン込み）
make site-check SITE_ENV=prod  SITE_TARGET=front                     # credential 無しで回せる読み取り
make site-check SITE_ENV=dev   SITE_TARGET=admin SITE_FORMAT=json    # 機械可読
```

- 面の語彙は **front / mypage / admin / all**（既定 all）、環境は **local / dev / prod**（既定 dev）
- **何を待つか**（送信元定義に固定）: front = `/`・`/products/list`・`/products/detail/<id>`（`--product-id`。省略時は `skipped`）・`/guide/articles`・`/contact`・`/ingredient/cbd` の 200 / mypage = `/mypage/login` の 200 と（未ログインで）`/mypage` の **302 → login** / admin = CSRF 付きログイン（GET → POST 302 → セッション確立）と `/{route}/`・`/{route}/product`・`/{route}/order` の 200
- リダイレクトは最大 5 hop まで追って履歴を出す（**ループ / 5 hop 超過 / Location なしは NG**）。**Symfony / PHP のエラー画面は 200 でも NG**（本文の既知のマーカーだけを見る）
- **応答時間は計るが、しきい値は無い**

## 出力形式（`SITE_FORMAT` / `--format`）

| 値 | 内容 |
|---|---|
| `text`（**既定**。site だけの例外） | 面ごとの一覧（判定 / status / 応答時間 / URL）。NG は最終 URL・リダイレクト履歴・主なヘッダ・段・本文の先頭・hint |
| `json` | `{source, env, target, round_trips, verdict, logins:[…], checks:[{face,url,expected,status,first_status,verdict,duration_ms,final_url,redirects,stage,error}]}` |
| `verbatim` | 受信した応答本文を順に（1 本文 = 末尾改行 1 つ。判定と証跡を分ける） |

## 失敗の見分け（site）

| exit | 意味 | 次の行動 |
|---|---|---|
| 0 | 全件 OK（ログインも確立） | — |
| 1 | 1 件以上 NG（ログイン失敗を含む） | stdout の一覧と `stage` を読む。`session` なら `ECCUBE_AUTH_MAGIC`、`csrf` ならログインルートと `_csrf_token`、`basic` なら Basic の 2 変数、`html/.cache-version` の hint は 500 の本文で出る |
| 2 | 前提不足（root / ルート / credential の未設定、接続不能） | メッセージの変数名を直す（**何も送っていない**。カセットも無い） |
| 3 / 124 / 127 | I/O / timeout / 依存（既存の共通規則） | 既存の表と同じ |

- **401 は exit 1**（stage = `basic`。dev のみ）。**credential の誤りでも値は出ない** — どの段で失敗したかだけが出る
- 判定は**決定的・機械可読**（監視からは exit code と `--format json` だけ読めばよい）

## 証跡とオフライン再現（site）

```sh
# 記録（live。CASSETTE 省略時は .cassettes/<UTC>-site-check-<env>-<target>.jsonl）
make site-check SITE_ENV=dev SITE_TARGET=all CASSETTE=.cassettes/site-dev.jsonl

# 同じコマンドで再生（**ネットも credential も使わない**。method + url + payload が一致しないと exit 1）
make site-check SITE_ENV=dev SITE_TARGET=all REPLAY=.cassettes/site-dev.jsonl
```

- **1 コマンド = 面の URL 数 + ログイン段数（+ リダイレクトの hop）の往復**。各往復は send / recv の 2 frame（`recv` は応答ヘッダも持つ — `Location` で hop をたどり、`Set-Cookie` で cookie jar を組み直す）
- ログイン POST の送信本文は**記録されない**（フィールド名と `_csrf_token` だけの evidence。password は `[REDACTED]`）。だから **`--replay` は credential 無しで同じ判定を返す**
- **カセットは管理画面・会員ページの内容とセッション状態を持つ**ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有・`raw/` 配置をしない**。カセットは**追記のみ**
- **prod の live は owner の承認が前提**（読み取りのみ）。netloom 側の実測は local / dev だけ（2026-10-19。付録 A.24）

---

# bigquery（BigQuery の読み取り専用クエリ）

## いつ使うか（トリガー）

- 「BigQuery のデータを見て」「このクエリの結果を取って」（**読み取りの依頼**）
- thch-vape の `.github/bin/bigquery_mcp_server.py`（FastMCP / stdio）を置き換える用途（issue #19）
- **使わない場面**: 書き込み（INSERT / UPDATE / DELETE / MERGE / DDL）。**netloom には書き込みが無い**（呼び出し側のツールに残る）
- **課金の注意**: BigQuery は**クエリがスキャンした量に応じて課金される**。実行前に必ず `--dry-run`（課金なしの見積もり）で `total_bytes_processed` を確認し、`WHERE` で絞る。`--max-rows` は返る行数の上限であり**スキャン量の上限ではない**

## 前提: project と credential（名前だけを知る）

- **project**: `--project` → env `GOOGLE_CLOUD_PROJECT` → `GCLOUD_PROJECT`（移管元の python が読んでいた 2 つをそのまま）。**どちらも無ければ 1 往復も送らず exit 2**。`--replay` も project を要る（照合キー）
- **credential は GSC / GA4 と同じ** `GOOGLE_TOKEN_FILE` → `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN`（netloom 自身が refresh grant を交換し、その往復も記録する）
- **live のトークンには bigquery スコープが要る**: `netloom auth google --source bigquery`（owner のブラウザ操作、1 回だけ。現行の ga4 / gsc 用トークンには無い。無ければ live は 403）

```sh
# 0) スコープの同意（owner が 1 回だけ。対話専用）
make auth-google AUTH_CLIENT_SECRETS=/path/to/credentials.json AUTH_SOURCE=bigquery
export GOOGLE_TOKEN_FILE="$HOME/.config/netloom/google-bigquery.json"

# 1) dry-run（**課金なし**。まずスキャン量を確認）
make bigquery-query SQL='SELECT * FROM `dataset.INFORMATION_SCHEMA.COLUMNS`' PROJECT=<project-id> DRY_RUN=1
#    → json の total_bytes_processed を読む（大きいなら WHERE で絞る）

# 2) 小さい SELECT を 1 回（パーティション・限定を推奨）
make bigquery-query SQL='SELECT 1 AS answer' PROJECT=<project-id>

# 3) オフライン再現（ネットも credential も使わない）
make bigquery-query SQL='SELECT 1 AS answer' PROJECT=<project-id> REPLAY="$C"
```

## 実行（1 コマンド = 2 往復 = カセット 4 frame）

- wire = `POST /bigquery/v2/projects/<project>/queries`、body は `{"query":…,"useLegacySql":false,"maxResults":N,"dryRun":bool}` を常に明示（standard SQL は移管元と同じ）
- **読み取り専用の門**: `SELECT` と **`WITH … SELECT`（CTE。本体が SELECT のときだけ）** で始まる 1 文だけ。`INSERT` / `UPDATE` / `DELETE` / `MERGE` / DDL / 複文 / `WITH … DML` は **1 往復も送らず exit 2**（カセットも作らない）
- **`jobComplete=false` はポーリングせず exit 1**（メッセージに `jobId`。続きは呼び出し側のツールで。設計書 §11 N26）

## 出力形式（`FORMAT` / `--format`）

- `json`（既定）= 結果文書（`fields` = schema の列名 / `rows` = 行（列順の JSON 値の配列）/ `job_id` / `total_rows` / `total_bytes_processed` / `cache_hit`。インデント 2）
- `csv` = fields をヘッダにした表（値は mysql の csv と同じ JSON 値のレンダリング。NULL は空セル）
- `text` = `rows:` と統計の要約
- `verbatim` = 受信バイトそのまま（証跡形。replay でも同じ）

## 証跡とオフライン再現（bigquery）

- **1 コマンド = 4 frame**: 交換（HTTP の send / recv）+ クエリ（`method: "query"` の send / recv。`send` = `{sql, project, dry_run?, max_rows?}`、`recv` = `{fields, rows, …, body}`）
- **照合キーは SQL + project + dry-run**。**ある project のカセットが別の project のクエリに答えない**。dry-run の記録が実行の replay に答えず、その逆も同じ。同じクエリの複数記録は**最初の記録**が返る（§5.1 の規則 = このコマンドはクエリを 1 回だけ要求するので最初の記録）
- **`--replay` はネットも credential も使わない**（交換をしない）
- **カセットはクエリ結果（業務データ）を持つ**ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有・`raw/` 配置をしない**。カセットは**追記のみ**
- **live は owner 承認が前提**（課金が発生しうる）。netloom 側は BigQuery への往復を 1 回も行っていない（テストは偽 BigQuery（`httptest`）で固定。手順は `docs/plan/20261019-bigquery.md` §7）

## 失敗の見分け（bigquery）

| exit | 何が起きたか | 直し方 |
|---|---|---|
| 0 | クエリの成功 / `--dry-run` の見積もり | — |
| 1 | BigQuery のエラー（4xx / 5xx。provider の言葉が 1 行）/ `jobComplete=false`（`jobId` つき）/ replay の不一致 / 接続失敗 / 16 MiB 超 | stderr の 1 行を読む。`jobId` は呼び出し側のツールで追える / replay は同じ SQL + project + dry-run で |
| 2 | 読み取り専用でない文 / 複文 / `--sql` 欠落 / project 未設定 / `--max-rows` 0 以下 / `--format` の語彙外 | 引数と env を直す（**何も送っていない**） |
| 3 | I/O（`--out` / カセット / `@FILE` が読めない） | パスを直す |
| 124 | timeout（`--timeout`。交換 + クエリの合計） | クエリを絞る |

---

# calendar（Google Calendar。6 コマンド）

## いつ使うか（トリガー）

- 「カレンダーを見て」「予定を調べて」「予定を作って / 直して / 消して」（**読み書きの依頼**）
- thch-vape の `.github/bin/google_calendar_mcp_server.py`（FastMCP / stdio）を置き換える用途（issue #20）
- **副作用の注意**: **create / update / delete はカレンダーに影響します**（予定が作られ / 置き換えられ / 消える）。**live の書き込みは owner の承認のうえで**実行する（gmail の送信と同じ扱い）。読み取り（list / get）は副作用なし

## 前提: calendar id と credential（名前だけを知る）

- **calendar id**: `--calendar-id` → env `GOOGLE_CALENDAR_ID` → **`primary`**（Google 自身が「自分のカレンダー」を指すエイリアス。**仮定**として置いた既定 — 付録 A.26 判断 D2）。**credential ではない**ので値はカセットの URL に載る。`list-calendars` は `--calendar-id` 不要（認証が誰の一覧かを決める）
- **credential は GSC / GA4 / bigquery と同じ** `GOOGLE_TOKEN_FILE` → `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN`（netloom 自身が refresh grant を交換し、その往復も記録する）
- **live のトークンには calendar スコープが要る**: `netloom auth google --source calendar`（owner のブラウザ操作、1 回だけ。書き込みにも足りる）

```sh
# 0) スコープの同意（owner が 1 回だけ。対話専用）
make auth-google AUTH_CLIENT_SECRETS=/path/to/credentials.json AUTH_SOURCE=calendar
export GOOGLE_TOKEN_FILE="$HOME/.config/netloom/google-calendar.json"

# 1) 読み取り（副作用なし）
make calendar-list-calendars                                     # カレンダー一覧（id / summary / timeZone / primary / accessRole）
make calendar-list-events TIME_MIN=2026-10-19T00:00:00Z MAX_RESULTS=10 SINGLE_EVENTS=1 FORMAT=text
make calendar-get-event EVENT_ID=<event-id>                      # 1 件

# 2) 書き込み（**副作用。owner 承認のうえで**）
make calendar-create-event INPUT='{"summary":"invented","start":{"dateTime":"2026-10-20T10:00:00+09:00"},"end":{"dateTime":"2026-10-20T11:00:00+09:00"}}'
make calendar-update-event EVENT_ID=<event-id> INPUT='{"summary":"invented (updated)"}'   # PATCH = 1 往復
make calendar-delete-event EVENT_ID=<event-id>                   # 204 本文なし = 出力なし・exit 0

# 3) オフライン再現（ネットも credential も使わない。3 形で一致）
make calendar-list-calendars REPLAY="$C"
```

## 実行（1 コマンド = 2 往復 = カセット 4 frame）

- wire = `GET /users/me/calendarList` / `GET|POST /calendars/<id>/events` / `GET|PATCH|DELETE /calendars/<id>/events/<eventId>`（base = `https://www.googleapis.com/calendar/v3`）
- **`list-events` は素通し**: `--time-min` / `--time-max` / `--max-results` / `--query` / `--single-events` / `--order-by` / `--page-token` は**与えたときだけ** query に載る（移管元 python の `timeMin=now` / `maxResults=20` / `singleEvents=true` は持ち込まない）。`--max-results` 0 以下は exit 2
- **`--input` は JSON であることだけ**を見て compact して送る（`@FILE` 可。**イベントのフィールドは語彙検証しない** — provider の答えが判定）
- **`update-event` は PATCH = 1 往復**（移管元の read-modify-write は採らない。パッチ本文は呼び出し側が書く）
- id は 1 パスセグメントにエスケープ（`:` は `%3A`）

## 出力形式（`FORMAT` / `--format`）

- `json`（既定）= 応答本文をインデント 2（`delete` の 204 は出力なし）
- `text` = リストは `calendars: N` / `events: N`（items が無い = 0 = **成功**）、イベントは `id:` / `summary:` / `status:`（答えが主張する member だけ。1 つも無ければ拒否）
- `verbatim` = 受信バイトそのまま（証跡形。replay でも同じ）
- **`csv` は無い**（`start` / `end` が date と dateTime の 2 形、`attendees` は配列 — 列を固定すると netloom が解釈することになる。`--format csv` は exit 2）

## 証跡とオフライン再現（calendar）

- **1 コマンド = 4 frame**: 交換（HTTP の send / recv）+ データ（HTTP の send / recv。**新しい frame は無い**）
- **照合キーは method + url + payload**（HTTP の規則そのまま）。calendar id / event id は URL に載る。**ある calendar / event のカセットが別の予定に答えない**。同じ request の複数記録は**最初の記録**が返る（§5.1 の規則 = このコマンドはデータ要求を 1 回だけ行うので最初の記録）
- **`--replay` はネットも credential も使わない**（交換をしない）
- **カセットは予定の本文・参加者・カレンダー名（業務・個人データ）を持つ**ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有・`raw/` 配置をしない**。カセットは**追記のみ**
- **live は 1 往復も未実行**（書き込みは副作用 = owner 承認が前提。読み取りも、calendar スコープの同意が実在するか不明のため未実行。手順は `docs/plan/20261019-calendar.md` §7）

## 失敗の見分け（calendar）

| exit | 何が起きたか | 直し方 |
|---|---|---|
| 0 | 6 コマンドの成功（**0 件のリストを含む**。delete の 204 = 出力なし） | — |
| 1 | Calendar のエラー（4xx / 5xx。provider の言葉が 1 行）/ `invalid_grant`（交換の失敗）/ replay の不一致 / 接続失敗 | stderr の 1 行を読む。replay は同じ calendar / event / query で |
| 2 | `--event-id` / `--input` 欠落 / `--input` が JSON でない / `--max-results` 0 以下 / `--format` の語彙外 / credential 未設定 | 引数と env を直す（**何も送っていない**） |
| 3 | I/O（`--out` / カセット / `@FILE` が読めない） | パスを直す |
| 124 | timeout（`--timeout`。交換 + データの合計） | 窓を絞る |


# apps-script（Google Apps Script API。13 コマンド）

## いつ使うか（トリガー）

- 「Apps Script のプロジェクトを見て / 作って / ソースを更新して / バージョンとデプロイを管理して」「スクリプトの関数を実行して」（**読み書きと実行の依頼**）
- thch-vape の `.github/bin/gas-mcp-server-server.py`（FastMCP / stdio）を置き換える用途（issue #21）
- **副作用の注意**: **書き込み 7 つは Projects に影響します**（プロジェクトが作られ / ソースが置き換えられ / バージョン・デプロイが作られ / 消える）。とくに **`run-script` は任意の関数を実行します** — スクリプトができること（メール送信・シート書き込み等）はすべて起こりうる。**live の書き込みと実行は owner の承認のうえで**実行する（gmail の送信と同じ扱い）。読み取り（get / list）は副作用なし

## 前提: script id と credential（名前だけを知る）

- **script id**: `--script-id` が**必須**（`list-processes` のみ省略可 = `userProcessFilter.scriptId` のフィルタ）。**netloom は script id を推測しない・一覧も持たない** — id は呼び出し側が知っている（Drive のファイル id）
- **credential は GSC / GA4 / bigquery / calendar と同じ** `GOOGLE_TOKEN_FILE` → `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN`（netloom 自身が refresh grant を交換し、その往復も記録する）
- **live のトークンには script スコープが要る**: `netloom auth google --source gas`（owner のブラウザ操作、1 回だけ。**6 スコープ = 旧 `gas-mcp-server-auth.py` と同じ**。送信元名が `apps-script` なのは A.0「略称を使わない」ため — `gas` はスコーププロファイルの名前）

```sh
# 0) スコープの同意（owner が 1 回だけ。対話専用）
make auth-google AUTH_CLIENT_SECRETS=/path/to/credentials.json AUTH_SOURCE=gas
export GOOGLE_TOKEN_FILE="$HOME/.config/netloom/google-gas.json"

# 1) 読み取り（副作用なし）
make apps-script-get-project SCRIPT_ID=<script-id>                     # メタデータ
make apps-script-get-project-content SCRIPT_ID=<script-id>             # ソースファイル一覧
make apps-script-list-project-versions SCRIPT_ID=<script-id> PAGE_SIZE=10
make apps-script-list-deployments SCRIPT_ID=<script-id>
make apps-script-get-deployment SCRIPT_ID=<script-id> DEPLOYMENT_ID=<id>
make apps-script-list-processes PAGE_SIZE=10                           # 全 script のプロセス

# 2) 書き込みと実行（**副作用。owner 承認のうえで**）
make apps-script-create-project TITLE='invented'
make apps-script-update-project-content SCRIPT_ID=<id> FILES=@content.json   # **全ファイル置換**
make apps-script-create-version SCRIPT_ID=<id> DESCRIPTION='v1'
make apps-script-create-deployment SCRIPT_ID=<id> VERSION_NUMBER=1
make apps-script-run-script SCRIPT_ID=<id> FUNCTION=hello PARAMETERS='["world"]'   # **関数の実行**
make apps-script-delete-deployment SCRIPT_ID=<id> DEPLOYMENT_ID=<id> # 204 本文なし = 出力なし・exit 0

# 3) オフライン再現（ネットも credential も使わない。3 形で一致）
make apps-script-get-project SCRIPT_ID=<script-id> REPLAY="$C"
```

## 実行（1 コマンド = 2 往復 = カセット 4 frame）

- wire = `POST|GET /projects` / `GET /projects/{id}` / `GET|PUT /projects/{id}/content` / `GET|POST /projects/{id}/versions` / `GET|POST /projects/{id}/deployments` / `GET|PUT|DELETE /projects/{id}/deployments/{deploymentId}` / `POST /scripts/{id}:run` / `GET /processes`（base = `https://script.googleapis.com/v1`）
- **`--files` / `--parameters` は JSON であることだけ**を見て compact して送る（`@FILE` 可。**ファイル・パラメータの語彙検証はしない** — provider の答えが判定）。`--files` は `{"files": …}` の envelope に包まれる（endpoint のスキーマの形）
- **素通し**: `--page-size` / `--page-token` / `--manifest-file-name` / `--description` / `--dev-mode` は**与えたときだけ** wire に載る（移管元の pageSize=50 / manifestFileName="appsscript" / devMode=false は持ち込まない）。`--page-size` / `--version-number` の 0 以下は exit 2（typo 検査のみ）
- id は 1 パスセグメントにエスケープ（`:` は `%3A`。`/scripts/{id}:run` の `:run` は API 自身の接尾辞）
- **`update-project-content` は全ファイル置換**: 既存ファイルはすべて消えて files の配列どおりになる（netloom は検証もマージもしない。呼び出し側が全ファイルを含めた配列を渡す）

## 出力形式（`FORMAT` / `--format`）

- `json`（既定）= 応答本文をインデント 2（`delete-deployment` の 204 は出力なし）
- `text` = リストは `versions: N` / `deployments: N` / `processes: N` / `files: N`（member が無い = 0 = **成功**）、プロジェクトは `scriptId:` / `title:`、デプロイは `deploymentId:` / `updateTime:`（答えが主張する member だけ。1 つも無ければ拒否）、`run-script` は封筒の `result:` / `error:`（**そのまま。解釈しない**）
- `verbatim` = 受信バイトそのまま（証跡形。replay でも同じ）
- **`csv` は無い**（description はテキスト、deploymentConfig はオブジェクト — 列を固定すると netloom が解釈することになる。`--format csv` は exit 2）
- **`run-script` の封筒 `{response:{result,error}}` は解釈しない**: HTTP 200 で error が返っても **exit 0**（provider の応答のまま。text / json で error を読む）

## 証跡とオフライン再現（apps-script）

- **1 コマンド = 4 frame**: 交換（HTTP の send / recv）+ データ（HTTP の send / recv。**新しい frame は無い**）
- **照合キーは method + url + payload**（HTTP の規則そのまま）。script id / deployment id は URL に載る。**ある script のカセットが別の script に答えない**。同じ request の複数記録は**最初の記録**が返る（§5.1 の規則 = このコマンドはデータ要求を 1 回だけ行うので最初の記録）
- **`--replay` はネットも credential も使わない**（交換をしない）
- **カセットはソースコード・デプロイメント・プロセス（業務データ）を持つ**ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有・`raw/` 配置をしない**。カセットは**追記のみ**
- **live は 1 往復も未実行**（書き込み 7 つと run-script は副作用 = owner 承認が前提。読み取りも、6 スコープのトークンが実在するか不明。手順は `docs/plan/20261019-apps-script.md` §7）

## 失敗の見分け（apps-script）

| exit | 何が起きたか | 直し方 |
|---|---|---|
| 0 | 13 コマンドの成功（**0 件のリストを含む**。delete の 204 = 出力なし。run-script の封筒内 error も exit 0） | — |
| 1 | Apps Script API のエラー（4xx / 5xx。provider の言葉が 1 行）/ `invalid_grant`（交換の失敗）/ replay の不一致 / 接続失敗 | stderr の 1 行を読む。replay は同じ script / deployment / query で |
| 2 | `--script-id` / `--title` / `--files` / `--function` / `--version-number` / `--deployment-id` 欠落 / JSON でない `--files` / `--parameters` / `--page-size`・`--version-number` の 0 以下 / `--format` の語彙外 / credential 未設定 | 引数と env を直す（**何も送っていない**） |
| 3 | I/O（`--out` / カセット / `@FILE` が読めない） | パスを直す |
| 124 | timeout（`--timeout`。交換 + データの合計） | 窓を絞る |

---

# PageSpeed Insights / CrUX（psi / crux。1 コマンド = 1 往復。**非公開 API**）

**非公開 API（issue #24。owner 決定 2026-10-18）**: **consumer（seo-operations）の測定系（ローカル Lighthouse）が正**で、`psi` / `crux` は**明示指示があるときだけ**使う（**置き換えを意図しない**）。理由 = **別測定系**なので Before/After に混ぜられない（Source Separation）。**コマンドは残る** = ローカル Lighthouse が使えないとき（CI・別マシン）の緊急手段。

## いつ使うか（トリガー）

- **明示指示があるときだけ**（下の注記。既定の導線ではない）。ローカル Lighthouse が使えない環境（CI・別マシン）でページの測定が必要 / PSI の生 JSON（`lighthouseResult` / `loadingExperience` / `analysisUTCTimestamp`）が要る → **`psi run`**
- 実ユーザーのコア バイタル（CrUX データセット）が要る（日次のレコード = `crux query`、約 6 か月の履歴（週次の系列）= `crux history`）→ **`crux`**
- どちらも**ローカル Lighthouse とは別測定系**: 数値を混ぜて比較しない（consumer の AGENTS.md「Source Separation」）。ローカル Lighthouse が使えるならそれが正

## 前提: query キー（credential はヘッダではなくクエリ）

- `psi` は **`PAGESPEED_API_KEY`**、`crux` は **`CRUX_API_KEY`**（**同じ値でも変数名は両方設定する** — netloom は「このコマンドが読む変数」を推測しない）
- env ファイル（ワークスペース外・`chmod 600`・コミットしない）に置き、netloom が cwd の env ファイルから自動で読む（`export` でもよい）
- **未設定なら 1 往復も送らず exit 2（カセットも作らない）。`--replay` でも要る**（キーがカセットの URL の一部 = 照合キーだから）
- **キーはカセットの URL に残る**（意図的 = replay の URL 照合のため）。stdout と stderr の失敗行には出ない（`key=[REDACTED]`）。だから **カセットは `.cassettes/`（gitignore）にだけ置き、コミット・共有しない**

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
# ページの Lighthouse 測定（PSI は quota を消費する。キャッシュ回避は呼び出し側）
make psi-run PSI_URL=https://www.thch-vape.shop/ PSI_STRATEGY=mobile \
  PSI_CATEGORIES=performance,accessibility,best-practices,seo CASSETTE=data/psi/cassettes/$(date -u +%Y%m%dT%H%M%SZ)-psi-run.jsonl
#   category は各 1 つの query パラメータとして送られる（カンマ区切りを netloom が翻訳）
#   --format text でカテゴリ score と lab 監査の displayValue の要約（判定はしない）

# CrUX: 日次のレコード / 履歴
make crux-query   CRUX_ORIGIN=https://www.thch-vape.shop CRUX_FORM_FACTOR=PHONE CASSETTE=data/crux/cassettes/$(date -u +%Y%m%dT%H%M%SZ)-crux-query.jsonl
make crux-history CRUX_ORIGIN=https://www.thch-vape.shop CRUX_FORM_FACTOR=PHONE COLLECTION_PERIODS=5 CASSETTE=data/crux/cassettes/$(date -u +%Y%m%dT%H%M%SZ)-crux-history.jsonl

# オフライン再現（ネットなし。キーは要る。request が一致しなければ exit 1）
make psi-run PSI_URL=https://www.thch-vape.shop/ REPLAY=data/psi/cassettes/<記録>.jsonl FORMAT=verbatim
```

## キャッシュと quota（呼び出し側の仕事）

- **PSI は同一 URL をキャッシュする**。新鮮な測定が必要なら**呼び出し側が URL にダミーのクエリを付ける**（consumer の運用 = `?psrun=N` 等）。**netloom は URL をそのまま送る**（書き換えない）
- **PSI はキーの quota を消費する**（キーなし実行は共有クォータを枯渇させる — だから consumer はキー必須で運用する。同じ理由で netloom も未設定を exit 2 で止める）。crux も Google Cloud 側の quota。**live は owner 承認が前提**（現時点では 1 往復も未実行）

## 失敗の見分け

| exit | 何が起きたか | 直し方 |
|---|---|---|
| 0 | 2xx（要約の材料が無い応答も text では exit 1 になる点を除く） | — |
| 1 | API のエラー（400 / 404 / 429。provider の言葉が 1 行、キーは `key=[REDACTED]`）/ replay の不一致 / text 要約の材料なし | stderr の 1 行を読む。replay は同じ url / origin とキーで |
| 2 | `--url` 無し / origin と url 両方無し / `--collection-periods` 0 以下 / 語彙外 `--format` / **キー未設定** | 引数と env を直す（**何も送っていない**） |
| 3 | I/O（`--out` / カセット） | パスを直す |
| 124 | timeout（`--timeout`） | PSI は測定に 1 分超をかけることがある。窓を広げる |

---

# YouTube Data API v3（youtube。2 コマンド。1 コマンド = 1 往復）

## いつ使うか（トリガー）

- 「YouTube でこの検索語の動画を**指定した日付範囲**で探して」（`youtube search`）— **`publishedAfter` / `publishedBefore` の絶対日付の年次スライス（2016–2025 等）は Apify actor（rolling window = 直近 N 日）では代替不可**（issue #29。consumer 側 skill に 2026-10-10 実測の記録あり）。relative date だけでよいなら `apify` の youtube actor でも足りる
- 「この動画 id の `publishedAt` / `statistics`（再生数・高評価数）/ `contentDetails`（尺）を補完して」（`youtube videos`）— search の応答の `snippet` には `publishedAt` が入るが、statistics / contentDetails は動画の詳細 API のみが返す（Apify の相対 timestamp を絶対日付へ補完する youtube-date-enrichment と同じ用途）
- ページング・リトライ・レート制限の待ちは**作っていない**: 次のページは応答の `nextPageToken` を `--page-token` に渡して**呼び出し側が** 1 往復ずつ実行する

## 前提: `YOUTUBE_API_KEY`（credential はヘッダではなくクエリ）

- psi / crux と同じ query キーの型（付録 A.31 判断 D2）。変数名は移管元 JCT（`scripts/collect-youtube-japanese-keywords.sh`）と同じ `YOUTUBE_API_KEY`
- env ファイル（ワークスペース外・`chmod 600`・コミットしない）に置き、netloom が cwd の env ファイルから自動で読む（`export` でもよい）
- **未設定なら 1 往復も送らず exit 2（カセットも作らない）。`--replay` でも要る**（キーがカセットの URL の一部 = 照合キーだから）
- **キーはカセットの URL に残る**（意図的 = replay の URL 照合のため）。stdout と stderr の失敗行には出ない（`key=[REDACTED]`）。だから **カセットは `.cassettes/`（gitignore）にだけ置き、コミット・共有しない**

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

```sh
# 動画検索（part=snippet + type=video はコマンドが固定で載せる。pass-through は与えたときだけ）
make youtube-search QUERY='CBD オイル' MAX_RESULTS=5 \
  PUBLISHED_AFTER=2016-01-01T00:00:00Z PUBLISHED_BEFORE=2017-01-01T00:00:00Z \
  REGION_CODE=JP RELEVANCE_LANGUAGE=ja CASSETTE=data/youtube/cassettes/$(date -u +%Y%m%dT%H%M%SZ)-search.jsonl
#   → items[]（snippet / id）と nextPageToken を provider の表現のまま（既定 json）
#   FORMAT=text は items の件数と nextPageToken の有無だけ（解釈しない）

# 動画の詳細（part=snippet,statistics,contentDetails は固定。id はカンマ区切り）
make youtube-videos ID='<video-id>[,<video-id>…]' CASSETTE=data/youtube/cassettes/$(date -u +%Y%m%dT%H%M%SZ)-videos.jsonl
#   → publishedAt / statistics / contentDetails で補完

# ページングは呼び出し側: 応答の nextPageToken を --page-token（make なら PAGE_TOKEN）に渡して次の 1 往復を実行
make youtube-search QUERY='CBD オイル' PAGE_TOKEN='<前の nextPageToken>'

# オフライン再現（ネットなし。キーは要る。request が一致しなければ exit 1）
make youtube-search QUERY='CBD オイル' REPLAY=data/youtube/cassettes/<記録>.jsonl FORMAT=verbatim
```

## 出力（`FORMAT`）

- `json`（既定）: 応答をインデント（キー順は受信のまま）
- `text`: `items: N`（要素数。0 件なら `items: 0`）+ `nextPageToken: present`（member が在るときだけ）。**数えただけで判定しない**
- `verbatim`: 受信バイトそのまま（証跡用）
- **csv は無い**: `items[]` が `snippet` / `id` / `statistics` / `contentDetails` と深い入れ子で、列の選択が netloom の解釈になる（psi / crux と同じ判断）

## 証跡とオフライン再現（youtube）

- **1 コマンド = 2 frame**（`send` = GET + url（**キー入り・レダクトしない**）/ `recv` = status + payload。OAuth 交換なし = psi / crux と同じ型）
- **照合キーは method + url + payload**（HTTP の規則そのまま）。q / id / 日付 / pageToken は URL に載るので、**ある検索のカセットが別の検索に答えない**
- **`--replay` はネットも credential も使わない**（キーは要る — URL の一部だから）
- **カセットは URL にキー・検索語・動画 id を含む**ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有・`raw/` 配置をしない**。カセットは**追記のみ**
- **live は親が実行**（search.list 1 本 + videos.list 1 本 ≒ 110 units。手順は `docs/plan/20261019-youtube.md` §5）

## 失敗の見分け（youtube）

| exit | 何が起きたか | 直し方 |
|---|---|---|
| 0 | 2xx（`items: 0` の検索も成功） | — |
| 1 | API のエラー（400 / 403 / 429。provider の言葉が 1 行、キーは `key=[REDACTED]`）/ replay の不一致 / text 要約の材料なし | stderr の 1 行を読む。replay は同じ q / id とキーで。**429 は quota** — 当日の残量は呼び出し側の管理（netloom はリトライしない） |
| 2 | `--query` / `--id` 無し・空白のみ / 語彙外 `--format` / **キー未設定** | 引数と env を直す（**何も送っていない**） |
| 3 | I/O（`--out` / カセット） | パスを直す |
| 124 | timeout（`--timeout`） | 窓を広げる |

---

# Zenodo REST API（zenodo。読み取り 4 コマンド + 書き込み 7 コマンド。1 コマンド = 1 往復）

## いつ使うか（トリガー）

- 「この Zenodo の record（DOI / id）の文書を取って」（`zenodo record --id ID`）— タイトル・作成者・DOI・state などは応答の `metadata` / `pids` にある（netloom は解釈しない）
- 「この record の**版の一覧**を取って」（`zenodo record-versions --id ID`）— 応答は provider の検索封筒（`hits.hits` / `hits.total`）で、`--format text` は `total: N` だけを述べる。`--sort` / `--size` は**与えたときだけ**送る
- 「**自分の下書き**（deposition）の状態を見て」（`zenodo deposition --id ID`）— `state`（`inprogress` / `done` / `error`）と `submitted` が読める
- 「その deposition の**ファイル一覧**を取って」（`zenodo deposition-files --id ID`）— 応答は**配列**（`filename` / `filesize` / `checksum` / `id`）。**`--format text` は無い**（exit 2）
- 「**下書きを作って / metadata を直して / 消して**」（`zenodo deposition-create --input …` / `deposition-update --id ID --input …` / `deposition-delete --id ID`）— `--input` は metadata の文書で、netloom が `{"metadata": …}` に包んで送る。**下書きの書き込みに確認フラグは要らない**（公開側の副作用ではない）
- 「**その下書きにファイルを上げて / 消して**」（`zenodo deposition-upload --id ID --file PATH` / `deposition-file-delete --id ID --file-id FILEID`）— upload は multipart（`-F "file=@…"` と同じ形）。**カセットには field / sha256 / size だけが残る**（バイトもファイル名も残さない）
- 「**次の版の下書きを作って**」（`zenodo deposition-newversion --id ID`）
- 「**公開して**」（`zenodo deposition-publish --id ID --allow-publish`）— **公開は取り消せない**（DOI が登録される）ので、**`--allow-publish` が無ければ 1 往復も送らず exit 2**。live は owner の承認があるときだけ

## 前提: `ZENODO_TOKEN`（ヘッダで送る・11 コマンド共通）

- `Authorization: Bearer <ZENODO_TOKEN>`。**1 送信元 1 規則**: 公開 record の読み取りにも送る（「このコマンドだけ匿名」の例外は無い）
- env ファイルは**ワークスペース外**に `chmod 600` で置き、コミットしない（netloom は cwd の env ファイルを自動で読む）
- **未設定なら 1 往復も送らず exit 2（カセットも作らない）。`--replay` は credential 不要**（ヘッダは照合キーではない）
- **値はカセットに出ない**: `Authorization` は名前を残して `[REDACTED]`（既存規則）。stderr の失敗行でも伏せる。**スコープは `deposit:write`（下書きの書き込み）/ `deposit:actions`（publish などの action）** — Zenodo のスコープ表の 2 つ

## 実行（1 コマンド = 1 往復 = カセット 2 frame）

`make` ターゲットは**作っていない**（バイナリ直叩き。apify の判断 D8 と同じ）。

```sh
# 公開 record の文書（GET /api/records/<id>）
bin/netloom zenodo record --id 123 --cassette "$C"
bin/netloom zenodo record --id 123 --format text          # id / status / created のうち応答が述べたものだけ

# 版の一覧（GET /api/records/<id>/versions。sort / size は与えたときだけ載る）
bin/netloom zenodo record-versions --id 123 --sort mostrecent --size 5 --cassette "$C"
bin/netloom zenodo record-versions --id 123 --format text # total: N

# 自分の deposition（下書きを含む）とそのファイル
bin/netloom zenodo deposition --id 456 --cassette "$C"
bin/netloom zenodo deposition-files --id 456              # 配列。--format text は exit 2

# 下書きの書き込み（公開側の副作用ではないので確認フラグ不要）
bin/netloom zenodo deposition-create --input '{"title":"…","upload_type":"dataset"}' --cassette "$C"
bin/netloom zenodo deposition-update --id 456 --input @metadata.json --cassette "$C"
bin/netloom zenodo deposition-upload --id 456 --file records.csv --cassette "$C"
bin/netloom zenodo deposition-file-delete --id 456 --file-id file-1 --cassette "$C"
bin/netloom zenodo deposition-newversion --id 456 --cassette "$C"
bin/netloom zenodo deposition-delete --id 456             # 下書きの削除（204 = 出力なしで exit 0）

# 公開（不可逆。--allow-publish が無ければ exit 2 で何も送らない）
bin/netloom zenodo deposition-publish --id 456 --allow-publish --cassette "$C"

# オフライン再現（ネットも credential も使わない。request が一致しなければ exit 1）
bin/netloom zenodo record --id 123 --replay "$C" --format verbatim
```

## 出力（`--format`）

- `json`（既定）: 応答をインデント（キー順は受信のまま。配列もそのまま整列する）。**書き込みが本文無しで返ったとき（204 No Content）は何も書かず exit 0**
- `text`: `record` = `id` / `status` / `created`、`record-versions` = `total`（`hits.total` の復唱）、`deposition` / `deposition-create` / `deposition-update` / `deposition-newversion` / `deposition-publish` = `id` / `state` / `submitted`、`deposition-upload` / `deposition-file-delete` = `id` / `filename` / `filesize` のうち**応答が述べたものだけ**。無い行は出さず、1 つも無ければ exit 1（要約の材料なし。**捏造しない**）
- `verbatim`: 受信バイトそのまま（証跡用）
- **csv は無い**（Zenodo の列の語彙を netloom が発明しない）。**`deposition-files` は配列・`deposition-delete` は文書無しなので `text` も無い**（`json` / `verbatim` の 2 形。`--format text` は exit 2）
- **202 Accepted も成功**（publish。本文は provider が返したもの）

## 証跡とオフライン再現（zenodo）

- **1 コマンド = 2 frame**（`send` = method + url + headers（**レダクト済み**）/ `recv` = status + payload）
- **照合キーは method + url + payload**。id / sort / size は URL に載るので、**ある record のカセットが別の record・別の sort に答えない**。**upload は証跡（field / sha256 / size）で照合**するので、**同じ名前の別のファイルは一致しない**
- 既定名は `.cassettes/<UTC>-zenodo-<command>-<target>.jsonl`（`record-versions` は sort / size も、`deposition-file-delete` は file id も target に入る。**id を持たない `deposition-create` は `all`** = 別 request が同じ名前を共有しない）
- **カセットは record / deposition の本文を持つ**（研究データのメタデータ・下書き）ので `.cassettes/`（gitignore）にだけ置き、**コミット・共有・`raw/` 配置をしない**。**upload のカセットに実ファイルのバイトは残らない**（field / sha256 / size だけ）
- **live は owner の承認があるときだけ**（publish / delete の live は特に）。手順は `docs/plan/20261019-zenodo.md`

## 失敗の見分け（zenodo）

| exit | 何が起きたか | 直し方 |
|---|---|---|
| 0 | 2xx（202 も成功） | — |
| 1 | API のエラー（400 / 401 / 403 / 404 / 429。**公開済み deposition の編集・削除を provider が拒否した場合を含む**。provider の言葉が 1 行）/ replay の不一致 / text 要約の材料なし | stderr の 1 行を読む。replay は同じ id / sort / size とコマンドで。**429 は provider のレート制限** — netloom はリトライしない |
| 2 | `--id` / `--input` / `--file` / `--file-id` 無し・空白のみ / 語彙外 `--format`（`deposition-files` / `deposition-delete` の `text` を含む）/ **`--allow-publish` なしの publish** / **`ZENODO_TOKEN` 未設定** | 引数と env を直す（**何も送っていない**） |
| 3 | I/O（`--out` / カセット / `--input @FILE` / `--file`） | パスを直す |
| 124 | timeout（`--timeout`） | 窓を広げる |

---

# ローカル計測とローカルブラウザ（lighthouse / playwright。カセットを作らない 2 送信元）

この 2 つだけが**ローカルの Node ツールを netloom が exec する**送信元（設計 付録 A.34 / A.35。issue #46 / #47）。**`--cassette` / `--replay` / `--format` は exit 2**（ローカル exec は「往復」の記録対象ではない = `mysql tunnel` と同じ扱い）。**証跡は `--out` のファイル**で、netloom が**新規のみ 0600** で先に作る。**netloom は出力を parse しない**（生 JSON / PNG / DOM / 戻り値の JSON はそのまま）。stdout は空で、失敗した run だけが stderr に 1 行。

## いつ使うか（トリガー）

- **ローカルで PageSpeed（Lighthouse）を回して生 JSON を残す** → `lighthouse run`。consumer（seo-operations）の測定の正はこれ（**psi / crux とは別測定系。混ぜない**）。ページのスクリーンショット・実行後 DOM・ページ内での 1 スクリプトの評価 → `playwright shot|html|eval`（目視レビューや診断。`@playwright/mcp` は対話用として残る）。**複数ページにまたがる 1 セッションの操作**（カート追加 → 遷移 → 削除など。GA4 `remove_from_cart` の検証 = issue #53）→ **`playwright flow`**
- 計測の**解釈**（中央値・判定・比較・DB 格納）は呼び出し側の仕事（netloom はしない）
- ブラウザの導入は**呼び出し側**: Lighthouse はホストの Chrome（無ければ Lighthouse のエラー = exit 1）、playwright は **Playwright 自身の Chromium**（`npx playwright install chromium`。無ければ Playwright のエラー = exit 1）。**netloom は何もインストールしない**

## 実行

```sh
# lighthouse: 1 コマンド = RUNS（既定 5）回の計測。run<i>.json が生 JSON
bin/netloom lighthouse run --url https://www.thch-vape.shop/ --out /tmp/lh/mobile
bin/netloom lighthouse run --url https://www.thch-vape.shop/ --out /tmp/lh/desktop --form-factor desktop
bin/netloom lighthouse run --url https://www.thch-vape.shop/ --out /tmp/lh/one --runs 1 --timeout 900
# make lighthouse-run LIGHTHOUSE_URL=https://www.thch-vape.shop/ LIGHTHOUSE_OUT=/tmp/lh/mobile

# 前提: node / npx が PATH にあること（無ければ exit 127）。Chrome は Lighthouse が見つけたもの（--chrome-path で明示）

# playwright: shot|html|eval は 1 コマンド = 1 ページ読み込み。出力は --out（PNG / DOM / 戻り値の JSON）
bin/netloom playwright shot --url https://www.thch-vape.shop/ --out /tmp/pw/front.png --full-page --viewport 390x844
bin/netloom playwright html --url https://www.thch-vape.shop/ --out /tmp/pw/front.html --wait-until networkidle
printf '(() => ({title: document.title}))()' > /tmp/pw/script.js
bin/netloom playwright eval --url https://www.thch-vape.shop/ --script /tmp/pw/script.js --out /tmp/pw/title.json
# 版とブラウザは対（既定 1.63.0 = chromium-1243）。導入済みが別のビルドなら --playwright-version V で合わせる
bin/netloom playwright html --url https://www.thch-vape.shop/ --out /tmp/pw/front.html --playwright-version 1.64.0
# make playwright-shot PLAYWRIGHT_URL=… PLAYWRIGHT_OUT=/tmp/pw/front.png FULL_PAGE=1 VIEWPORT=390x844

# flow: 1 コマンド = 1 セッション = N ページ読み込み（issue #53。設計 付録 A.35 追補 2）
#   スクリプトは「page と context を引数に受ける async function の本体」。await page.goto / page.click がそのまま通る
#   **スクリプトは about:blank から始まる — ページ内の fetch / DOM 参照の前に page.goto で対象ページを開くこと**（CORS: TypeError: Failed to fetch を踏む = issue #59）
#   return した値（undefined は null）が --out に JSON（インデント 2）。--url / --viewport / --wait-until は無い（渡すと exit 2）
#   window.gtag / dataLayer のスタブはスクリプト側の仕事（netloom はページの JS を書き換えない）
printf '%s\n' \
  "await page.goto('https://dev.example.com/products/detail/17');  // 1. 商品詳細" \
  "await page.click('button.add-cart');                            // 2. カート追加（AJAX）" \
  "await page.waitForTimeout(1500);" \
  "await page.goto('https://dev.example.com/cart');                // 3. カートページ" \
  "await page.click('a[href*=\"/cart/remove/\"]');                   // 4. 削除リンク" \
  "await page.waitForTimeout(1500);" \
  "return await page.evaluate(() => ({ calls: (window.dataLayer || []).slice() }));  // 5. gtag の記録" \
  > /tmp/pw/flow.js
bin/netloom playwright flow --script /tmp/pw/flow.js --out /tmp/pw/flow-result.json --timeout 300
# make playwright-flow PLAYWRIGHT_OUT=/tmp/pw/flow.json SCRIPT=/tmp/pw/flow.js [TIMEOUT=SEC]

# eval のスクリプトは page.evaluate(string) と同じに評価される（1 つの式。関数ソースは自分で呼ぶ: (() => document.title)()。文は IIFE に包む — 設計 付録 A.35 追補 4 判断 D40）
#   flow へ移すときは最初に書く: flow のスクリプトは about:blank から始まるので、page.goto で対象ページを開いてから fetch / DOM 参照をする（issue #59）
# --viewport / --wait-until は pass-through（未知の値はツールが答える。flow には無い）
```

## 失敗の見分け

| exit | 何が起きたか | 直し方 |
|---|---|---|
| 0 | 全部成功（lighthouse は全 run） | — |
| 1 | ツールの非ゼロ終了（ページが開けない・**ブラウザ未導入**・**スクリプトの例外（eval / flow）**・パッケージが解決できない）。lighthouse は `netloom: run 2/5 failed (exit 3): …` の 1 行（**残りの run は実行済み**。部分結果は残る） | stderr の 1 行を読む（**スクリプトの内容は出ない = エラーは先頭 1 行だけ**）。ブラウザ未導入なら `npx playwright install chromium` は呼び出し側の手順。**`Executable doesn't exist at … chromium-<rev>` は版とブラウザの不一致** = `--playwright-version V` で導入済みに合う版を渡す（`playwright-core` の `browsers.json` で `<rev>` を確認） |
| 2 | 引数・語彙（`--url` / `--out` / `eval`・`flow` の `--script` 欠落、**flow への `--url` / `--viewport` / `--wait-until` / `--full-page`**、`--runs` 0 以下、`--form-factor` 語彙外、**`--cassette` / `--replay` / `--format`**） | 引数を直す（**1 回も起動していない**） |
| 3 | I/O（`--out` が書けない・`--script` が読めない） | パスを直す |
| 124 | `--timeout`（**コマンド全体**の上限。既定 300 秒） | 窓を広げる（5 run は 60〜90 秒が目安） |
| 127 | `node` / `npx` が PATH に無い（**1 回も起動しない**） | Node を入れる / PATH を通す |

## 証跡の形

- **カセットは無い**。`--out` が証跡: `run1.json` 〜 `runN.json`（lighthouse）/ PNG・HTML・JSON（playwright。**flow はスクリプトの return 値の JSON**）。**新規ファイルは 0600**（既存の mode は不変）
- `lighthouse` の JSON は **Lighthouse の生データ**（categories / audits。netloom は触らない）。`playwright eval` / `flow` の JSON は `JSON.stringify(戻り値, null, 2)` + 改行（`undefined` は `null`）
- **カセットの検査（`cassette check`）の対象外**（カセットを作らないため）
- **live は一部実測済み**: lighthouse は実測済み（exit 0・約 21 秒・`run1.json` 921,296 B・0600）。**playwright は未実測**（ピン 1.61.0 の Chromium 1228 が無くて exit 1 → 1.63.0 に修正。修正後の 3 コマンドは親が実行する）: 手順は `docs/plan/20261019-lighthouse-playwright.md` §7。**`flow` の live も未実行**（親が dev サーバーで 5 ステップを実行。オフラインの受入は偽 playwright パッケージの e2e テストで固定済み）: 手順は `docs/plan/20261019-playwright-flow.md` §7

---

# devtools（Chrome DevTools over CDP。カセットを作る MCP 送信元）

**CDP の観測**（設計 付録 A.36、issue #49 / #52）: ページが実際に投げた要求、**1 要求の詳細（POST ボディを含む）**、コンソールのメッセージ、実行後の DOM のアクセシビリティスナップショット、1 本のパフォーマンストレース。**ピンした `chrome-devtools-mcp@1.11.0` を MCP のまま使う**（google-trends / gmail と同じ `mcp_stdio` の経路）ので、netloom はハーネスを同梱しない。

## いつ使うか（トリガー）

- 「このページは実際に何を読み込んだか」「コンソールに何が出たか」「実行後の DOM はどうなっているか」「1 本のトレースがほしい」→ devtools
- **POST リクエストの中身（ボディ）がほしい**（例: GA4 の `/g/collect` の `en=` / `ep.*`）→ `devtools network --match '/g/collect'`（issue #52。詳細は同一セッションで取得し `<out>-detail-<requestId>.json` に置く）
- **PageSpeed の数値がほしい**（Lighthouse スコア・CWV）→ **`lighthouse run`（ローカル計測）**。devtools は**計測ではなく観察**なので、数値の before/after に混ぜない
- ページを操作して何かを取る（スクリーンショット・DOM・1 スクリプトの評価）→ playwright。**複数ページにまたがる操作（カート追加 → 遷移 → 削除など）は `playwright flow`**（1 セッション）。**`lighthouse_audit` / `take_screenshot` / `evaluate_script` はこのサーバも持つが使わない**（重複を作らない = 計測は lighthouse、操作は playwright）

## 実行（1 コマンド = 決まった並びの `tools/call`）

```sh
# network: navigate_page → list_network_requests（2 呼び出し）
bin/netloom devtools network  --url https://www.thch-vape.shop/ --out /tmp/dt/network.json
# console: navigate_page → list_console_messages（2）
bin/netloom devtools console  --url https://www.thch-vape.shop/ --out /tmp/dt/console.json
# snapshot: navigate_page → take_snapshot（2）。--format text で人が読む形
bin/netloom devtools snapshot --url https://www.thch-vape.shop/ --out /tmp/dt/snapshot.txt --format text
# trace: performance_start_trace → navigate_page → performance_stop_trace（3）
bin/netloom devtools trace    --url https://www.thch-vape.shop/ --out /tmp/dt/trace
# --analyze は 4 つ目の呼び出し（performance_analyze_insight）を足す: trace.json + insight.txt
bin/netloom devtools trace    --url https://www.thch-vape.shop/ --out /tmp/dt/trace --analyze
# network --match: マッチした要求の詳細を同一セッションで取得（呼び出し回数 = 2 + M、既定の上限 10）
#   --out はリストのまま、各詳細は <out>-detail-<requestId>.json に provider の文書そのまま（issue #52）
bin/netloom devtools network  --url https://www.thch-vape.shop/ --out /tmp/dt/network.json --match '/g/collect' --max-details 3
# make devtools-network DEVTOOLS_URL=https://www.thch-vape.shop/ DEVTOOLS_OUT=/tmp/dt/network.json [DEVTOOLS_MATCH='/g/collect'] [DEVTOOLS_MAX_DETAILS=3]

# 記録したカセットからオフライン再現（並びの順に照合。ネットも npx も Chrome も使わない）
bin/netloom devtools network --url https://www.thch-vape.shop/ --out /tmp/dt/replay.json --replay .cassettes/devtools-network.jsonl
```

- **`--out` は必須**（exit 2。答えはファイルで、stdout には出さない）。network / console / snapshot = 1 ファイル、**trace = DIR**（`trace.json` + `--analyze` なら `insight.txt`）。netloom が**新規を 0600 で先に作る**（既存の mode は不変）
- **`--format`** は network / console / snapshot で `json`（既定 = provider 自身の `structuredContent` をインデント 2 でそのまま）/ `text` / `verbatim`。**csv は無く、trace は `--format` を持たない**（ファイル名が形を述べる）
- **`--analyze`** は trace だけの語彙。2 引数（insight set / insight 名）は**トレースの要約が印字した最初の組**から読む（無ければ exit 1。id を発明しない）
- **`network --match REGEXP [--max-details N]`** はマッチした要求の詳細を同一セッションで取得する（**POST ボディ・要求 / 応答ヘッダを含む**）。呼び出し回数 = **2 + M**（M = min(マッチ数, `--max-details`)。既定 **10**）。`--out` はリストのまま、**各詳細は `<out>-detail-<requestId>.json` に 1 文書ずつ**（provider の文書そのまま。netloom は parse しない。詳細は常に `json` = `--format` はリストにだけ効く）。**reqid はセッション内の id** なのでリストしたセッションの中で取る（別コマンドの id では引けない = 実測 2026-10-20 に exit 1 で確認。`request` コマンドは削除）。マッチ 0 件でも exit 0（詳細ファイルが無いだけ）。`--match` は RE2 として読めればよく（無効な正規表現は exit 2）値の語彙は見ない。`requestFilePath` / `responseFilePath` は渡さない（`--out` と役割が重複 = 予約）
- **前提**: `node` / `npx`（無ければ 1 往復もせず exit 127）と **Chrome**（ブラウザはサーバーが自分で起動する。無ければツールのエラー = exit 1）
- **サーバーは `--no-page-id-routing` で起動する**（`pageIdRouting` の既定 true は全 page-scoped ツールの schema に必須の `pageId` を足し、渡さないと `navigate_page` が isError になる — 2026-10-19 の live 実測 = A.36 判断 D23。netloom は 1 コマンド = 1 ページ）

## 失敗の見分け

| exit | 何が起きたか | 直し方 |
|---|---|---|
| 0 | 並びが最後まで進み、答えを書いた | — |
| 1 | ツールの `isError` / JSON-RPC error / replay の拒否 / トレースが insight を述べない | stderr の 1 行（provider のメッセージ）を読む。**Chrome が無い場合もここ**（`Could not find Chrome` など。導入は呼び出し側）。**request で「Request not found」もここ**（id はセッション内の id — 別コマンドの id は引けない = 実測 2026-10-20） |
| 2 | 引数・語彙（`--url` / `--out` 欠落、`--request-id` 欠落・非数値、`--format csv`、trace の `--format`、`--analyze` を trace 以外に、request に `--url`、**契約にあった `--wait-until`**） | 引数を直す（**1 往復もしていない**）。`--wait-until` は 1.11.0 の `navigate_page` に受け口が無いので**語彙に入っていない** |
| 3 | I/O（`--out` / DIR が書けない） | パスを直す |
| 124 | `--timeout`（**コマンド全体** = 1 セッション + 並びの上限。既定 300 秒） | 窓を広げる |
| 127 | `npx` / `node` が PATH に無い（**1 回も起動しない。カセットも `--out` も作らない**） | Node を入れる / PATH を通す |

## 証跡の形

- **カセットに普通に残る**（MCP の往復）: **1 コマンド = 1 `initialize` + 呼び出し数ぶんの `tools/call`**（send は 1 + 1 + N、recv は N + 1。network / console / snapshot = N 2、trace = 3、`--analyze` = 4、request = 1）。`cassette show` で frame を数えられる
- **`--replay` は並びの順に照合**する（同じ request の記録が複数あれば「n 回目に n 番目」= 既存の規則）。**別の URL / 別の id の replay は exit 1**
- **`--out` のファイルも証跡**: provider の答え（`structuredContent` / 描画 / 生バイト）そのもの。netloom は parse しない（インデントだけ揃える）
- **カセットは未公開 URL とページの中身（要求・コンソール・DOM・トレース）を含む**: `.cassettes/`（Git 管理外）のみ・**コミットしない**。**request の答えは Cookie / Set-Cookie と POST ボディを含む**（ヘッダ値は既存規則で `[REDACTED]` に、**POST ボディ（GA4 の ecommerce パラメータ等）は残る**）— カセットはさらに慎重に扱う
- **live は親が実行**（Chrome を起動するので 1 回だけ。**2026-10-19 の 1 回目で `pageIdRouting` の欠陥（`navigate_page` が isError）を発見 → `--no-page-id-routing` で修正済み**（A.36 判断 D23）。修正後の再実行が残件。手順は設計 A.36 の「親の live 手順」と `docs/plan/20261019-devtools.md` §5）


---

# してはいけないこと

- netloom に**解釈・比較・正規化**を求める（プロキシは判定しない。Apify の items も X の投稿も GA4 の集計値も同じ）
- カセットを書き換える・削除する
- 取得値をそのまま publication に使う（採用は呼び出し側の pipeline とゲートを通す）
- `raw/` にカセットを置く
- provider（google-trends-mcp / Apify API / X API / GA4 Analytics Data API / OpenSEO の MCP エンドポイント）を直接実行する（証跡が残らない）
- `APIFY_TOKEN` / `X_BEARER_TOKEN` の実値をコマンドライン・メモ・カセットに書く
- GA4 の credential（トークンファイルの中身）を出力・貼り付け・コミットする（netloom は `GOOGLE_TOKEN_FILE` / `GOOGLE_*` から読むだけ。値は stdout / stderr / カセットに出ない）
- **X のカセットをコミットする・共有する**（投稿データを含む）
- **devtools のカセットをコミットする・共有する**（未公開 URL・ページの要求・コンソール・DOM・トレースを含む）
- **GA4 のカセットをコミットする・共有する**（プロパティの集計値を含む）
- **GSC のカセットをコミットする・共有する**（自分のサイトの検索語と数値を含む）
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN` の実値をコマンドライン・メモ・カセットに書く（netloom が環境変数から読む）
- `SEO_API_KEY` / `HTTP_BASIC_AUTH_USER` / `HTTP_BASIC_AUTH_PASS` の実値をコマンドライン・メモ・カセットに書く（netloom が環境変数から読む）
- **`GA4_API_KEY`（ga4-orders の `X-GA4-API-Key`）の実値をコマンドライン・メモ・カセットに書く**（netloom が環境変数から読む。`SEO_API_KEY` とは別の資格情報）
- **本番（`NEWS_ENV=prod`）への書き込みを `ALLOW_PROD_WRITE=1` なしで実行する**（exit 2 で止まる。書き込みだと知らずに出すのを避けるための門）
- **news / cache のカセットをコミット・共有する**（ショップのニュースを含む）
- **article のカセットをコミット・共有する**（未公開の原稿本文を含む）
- **contact / ga4-orders のカセットをコミット・共有する**（顧客の PII / 売上を含み、**レダクトされない**）
- **`X-GA4-API-Key` / `GA4_API_KEY` を ga4（GA4 Data API）の送信元と混同する**（別物。あちらは Analytics Data API を Google の refresh grant で読む）
- **openseo のカセットをコミット・共有する**（プロジェクト id と実キーワードのメトリクスを含む）
- **gmail のカセットをコミット・共有する**（宛先・件名・本文（と HTML）を含む）
- **gmail の live 送信を owner 承認なしに実行する**（実メールが飛ぶ。gmail の節）
- **`--allow-send`（make は `ALLOW_SEND=1`）なしで実メールを送ろうとする**（exit 2 で止まる。実メールが飛ぶと知らずに出すのを避けるための門。`ALLOW_PROD_WRITE=1` と同じ流儀）
- **gmail の credential（`~/.gmail-mcp/` の中身）を読む・出力する**（サーバーの領分。netloom は関知しない）
- **`PAGE_TOKEN` / `USER_TOKEN` の実値をコマンドライン・メモ・カセットに書く**（netloom が環境変数から読む。`Authorization: Bearer` として送る）
- **meta-page / meta-instagram のカセットをコミット・共有する**（投稿本文と指標を含む）
- **トークンファイル（`$HOME/.config/netloom/google-*.json`）の値を出力・貼り付け・コミットする**（credential そのもの。`netloom auth google` の stdout / stderr はパスとスコープだけ）
- **`netloom auth google` を CI・自動テスト・スクリプトから実行する**（対話専用。exit 2 で止まる。同意は人が 1 回だけ行う）
- **OpenSEO コンテナの起動・停止を netloom に期待する**（プロセス管理は呼び出し側。落ちていれば exit 1 で、その失敗もカセットに残る）
- **X の live request を owner 承認なしに実行する**（当面禁止）
- **`MYSQL_PASSWORD` / `MYSQL_USER` の実値をコマンドライン・メモ・カセットに書く**（netloom が環境変数から読む。接続の同一性にも password / user は入らない）
- **mysql のカセットをコミット・共有する**（ショップの行 = PII・売上を含みうる）
- **本番 DB への読み取りを owner の承認なしに実行する**（`--env prod` は呼び出し側の本番 env ファイルを使う。実測は DEV の読み取りだけ）
- **netloom に DB の書き込みを求める**（INSERT / UPDATE / DELETE / DDL / `CALL` は**作っていない**。exit 2 で止まる。ショップの書き込みは呼び出し側の資産）
- **ssh の鍵・パスフレーズを netloom に渡す**（ssh 自身が `~/.ssh/config` と agent を使う。netloom は credential を読まない）
- **lighthouse の計測値と psi / crux の数値を混ぜる・比べる**（**別測定系**。consumer の測定の正はローカル Lighthouse = `netloom lighthouse run`。psi / crux はローカル Lighthouse が使えないときの緊急手段）
- **netloom にブラウザをインストールさせる**（Chrome は Lighthouse が見つけたもの、Chromium は `npx playwright install chromium` = **呼び出し側の手順**。netloom は何も入れない）
- **netloom に Lighthouse の中央値・判定・DB 格納を求める**（netloom は生 JSON を置くだけ。解釈は呼び出し側）
- **`--cassette` / `--replay` を lighthouse / playwright に渡す**（exit 2。ローカル exec は往復の記録対象ではない — 証跡は `--out`）

# 研究リポジトリ（japan-cannabinoid-trends）への取り込み

netloom は **producer**。採用は JCT 側の staging declaration / collection pipeline
（`make stage` → `make adopt-all`）が行う。netloom は採用判定・publication・release をしない。

# まだ無いもの（欲しくなったら owner に相談）

- **mysql の書き込み**（INSERT / UPDATE / DELETE / DDL / `CALL`）: **作らないと決めている**（owner 決定 6。呼び出し側に残る）。`WITH … SELECT`（CTE の読み取り）も語彙外（必要になったら owner 判断）
- **mysql のアカウント分離（読み取り専用ユーザー）**: **推奨だが netloom の作業ではない**（DB 側 = consumer の運用判断。netloom の門は語彙 + `START TRANSACTION READ ONLY` の 2 層）
- **mysql の停止コマンド（`tunnel-stop`）**: 作っていない（トンネルは `ssh -N -f` でデタッチし、プロセスは呼び出し側のもの。§付録 A.23）
- **mysql の本番 live**: **未実行**（owner 承認が前提。手順は `docs/plan/20261019-mysql.md` §7）
- **apps-script の live は未実行**（書き込み 7 つと run-script は副作用 = owner 承認が前提。読み取りも、6 スコープのトークンが実在するか不明。手順は `docs/plan/20261019-apps-script.md` §7）。呼び出し側（thch-vape.shop の `.github/bin/gas-mcp-server-server.py` と `.mcp.json` の gas エントリ）の置き換えは**未処理**（設計 §11 N28。認証側の `gas-mcp-server-auth.py` は #11 で置き換え済み）
- **mysql の UNIX socket 接続 / far end が別ホストの系**: 未対応（TCP のみ。`internal/adapters/sources` の `mysqlRemoteAddr` 1 行が定義）
- `google-trends related-queries`（Phase 1.5）、`trending-now` / `interest-by-region`（予約）
- Apify の allow-list / 入力スキーマ検証 / コスト上限 / ポーリング / リトライ（**作らない**と決めている。必要なら呼び出し側で）
- X の allow-list / field 名の検証 / ページングの自動化 / リトライ / レート制限の待ち / 費用上限（**作らない**と決めている）
- X の予約コマンド: `x user` / `x user-tweets` / `x tweets`（必要になったら 1 コマンド = 1 endpoint として追加）
- X の Request-only evidence（応答本文・投稿 ID・`next_token` 原値を含まない証跡の分離）は**未決**（設計書 §11 N7。必要になったら owner に相談）
- GA4 の dimension / metric の allow-list（**作らない**と決めている。未知の名前は GA4 のエラーがそのまま出る。語彙は `get-metadata` で確認する）
- GA4 の Admin API（設定変更）と書き込みは netloom では**作らない**（読み取り専用スコープの access token を既存の refresh grant で取るだけ。設計書 §2.2）
- **GA4 の live 成功応答の形**: metadata は 2026-10-19 に実測済み（`dimensions` 375 / `metrics` 86 / `name`。dimension は `apiName` / `uiName` / `description` / `category`、metric は それに `type`）。**report（`dimensionHeaders` / `metricHeaders` / `rows`）の実応答は未観測** — 実 property id での live は owner の 1 回で判明する（手順は `docs/plan/20261018-ga4-support.md` の追補節）
- **seo / JCT の `ga4-analytics` skill は `mcp_ga4_*` を直接使う手順のまま** — 「GA4 の取得は netloom 経由（証跡が残る）」への手順更新は**呼び出し側の作業**（設計書 §11 N11）
- **GA4 の 0.4.0 以前の MCP カセットは新しい実装では再生できない**（frame の形が違う。証跡としては有効なので削除しない）
- **seo の `fetch_gsc_monthly.py` は直接 API を叩く手順のままかもしれない** — netloom 経由（証跡が残る）への載せ替えは**呼び出し側の作業**（設計書 §11 N12）
- GSC の予約コマンド: `gsc site`（`GET /sites/{site}`）/ `gsc inspect`（URL Inspection API。別サービスなので transport と base URL の設計から）。必要になったら 1 コマンド = 1 endpoint として追加
- GSC の vcrpy（YAML）カセットの読み書きは**作らない**（このマシンに既存カセットは 1 つも無いと実測で確認。設計書 §11 N4）
- GSC の live 成功応答の形（`rows[].keys` の並び、`clicks`/`ctr`/`position` の型、`responseAggregationType` の有無）は、**このマシンの credential の状態による**（実装メモ §9）
- GSC の `service account` / ADC（Application Default Credentials）の grant は**作らない**（refresh_token grant のみ。設計書 付録 A.12）
- **news / cache の dev ホストは env `EC_DEV_BASE_URL` から読む**（**6 送信元共通**。値はコードに無い。未設定なら `--env dev` は exit 2。issue #7）
- **news / cache の live は 2026-10-18 に consumer（thch-vape スレッド）が `--env dev` で実施済み**（全コマンド exit 0・live と `--replay` はバイト一致・`--env prod` の書き込みは exit 2・カセットに実値なし。付録 A.15）
- **article の live も 2026-10-18 に実施済み**（CRUD + 画像（thumbnail / image、メタ付き）すべて exit 0・replay 一致。付録 A.16）
- **contact の live は 2026-10-18 に実施済み**（CRUD すべて exit 0・replay 一致。付録 A.17）。**ga4-orders の読み取りは 405**（shop 側にルートが無い。shop#313 待ち）、**`create` は実在する `dtb_order.id` 用**（合成 id は実態と食い違う `skipped` が返る。付録 A.18）
- **contact / ga4-orders のカセットはレダクトしない**（付録 A.17 / A.18 の設計相談への回答 = owner 決定 1。`--redact-pii` や `payload_sha256` は作らない）
- **ga4-orders の一覧 / 詳細 / 更新 / 削除のルートは shop 側にまだ無い**（live 実測 2026-10-18: `GET /api/ga4/orders` = **405 `Allow: POST`**。shop は受信の POST だけを実装。ルートが足されれば netloom のコマンドはそのまま動き、405 もカセットに残る）
- **ga4-orders の `X-GA4-API-Key` は shop 側で `.env` の `SEO_API_KEY` と比較する実装**（live は `GA4_API_KEY = SEO_API_KEY` の同値で 401 を通過。2026-10-18 実測）
- **slug → id の解決・slug での一覧フィルタは作らない**（呼び出し側が `list` の `offset` を進める。設計書 付録 A.16）
- **大きな本文の切り詰めは作らない**（カセットが M7 の証跡。切り詰めると replay の本文一致が失われる。付録 A.16）
- slug から id を引くような解釈・一覧のページングの自動化・画像の形式 / サイズの検査・派生バリアントの生成は**作らない**（呼び出し側が `list` / `get` を組み合わせる。派生はデプロイ時のバッチ）
- **OpenSEO は実装済み**（`openseo` 5 コマンド。上の節。1 コマンド = 1 往復。domain-overview / serp-competitors は issue #10 で 2026-10-19 に追加、live と replay のバイト一致を実測）。**呼び出し側（seo-operations の `fetch_openseo_monthly.py`）の載せ替えは未処理** — 証跡付きの取得への切替は seo-operations の作業（設計書 §11 N16）
- **OpenSEO の Docker の起動・停止は呼び出し側の作業**（netloom はプロセスを管理しない。設計書 付録 A.19）
- OpenSEO の `initialize` の往復は**送らない**（実測で不要。1 コマンド = 1 往復を崩さない）
- 実行時に `tools/list` は呼ばない（schema は開発時に 1 回だけ確認して設計 付録 A.7 に記録）
- **gmail は実装済み**（`gmail send-email` の 1 コマンド。上の節。1 コマンド = 1 MCP 往復）。**live の実送信は 2026-10-24 に受入済み**（呼び出し側の再送 1 通で、`tools/call` に `mimeType: "multipart/alternative"` が載り、受信メールで HTML が描画されることを owner が目視確認 = issue #66。**以後の実送信も owner の承認ごと**。手順は `docs/plan/20261019-gmail.md` §7）。**呼び出し側（seo-operations の `daily_alert.py` / `test_gmail_mcp.py`）の載せ替えは未処理** — 証跡付きの送信への切替は seo-operations の作業（設計書 §11 N17）
- gmail の他のツール（`draft_email` / `read_email` / `search_emails` / `list_email_labels` / ラベル / フィルタ / 添付の 18 ツール）は**予約（作らない）**（必要になった時点で 1 コマンド = 1 ツール。設計書 付録 A.20）
- gmail の `cc` / `bcc` / 添付は**送らない**（`htmlBody` は `--html-body` を名指したときだけ同じ往復で送り、そのときは実サーバーの要件で `mimeType: multipart/alternative` も載る。issue #64 / #66。付録 A.20）
- **Meta Graph API の live は未実行**（このマシンに `PAGE_TOKEN` / `USER_TOKEN` / `PAGE_ID` / `IG_ACCOUNT_ID` が無い。手順は `docs/plan/20261019-meta-graph.md` §7）
- **Graph API が `Authorization: Bearer` を受け付けるかは未確認**（live の 401 で判明する。クエリ方式（`access_token`）+ URL レダクトへの切替は owner 判断。設計書 §11 N18）
- **Meta のページング自動化・リトライ・metric / fields の allow-list は作らない**（薄いプロキシ。次のページは応答の `paging.next` で呼び出し側が回す）
- **Meta の csv は作らない**（`--fields` が列名になるため表を固定できない。json / text / verbatim だけ）
- **bigquery のカセットをコミット・共有する**（クエリ結果 = 業務データを含む。`.cassettes/`（gitignore）にだけ置く。付録 A.25）
- **BigQuery へ `--dry-run` なしで大きいクエリを実行する**（課金が発生する。まず `DRY_RUN=1` でスキャン量を確認する）
- **calendar の live 書き込みを owner 承認なしに実行する**（create / update / delete はカレンダーに予定を作り / 直し / 消す。副作用 = gmail の送信と同じ扱い。付録 A.26）
- **calendar のカセットをコミット・共有する**（予定の本文・参加者・カレンダー名 = 業務・個人データを含む。`.cassettes/`（gitignore）にだけ置く）
- **`GOOGLE_CALENDAR_ID` の実値をコマンドライン・メモ・カセットに書く**（netloom が環境変数から読む。credential ではないのでカセットの URL には載る）
- **calendar のイベント本文を netloom に検証させる**（`--input` は JSON であることだけを見る — フィールドの語彙検証は無い。不正な本文は provider のエラーが返る）
- **apps-script の live 書き込みと run-script を owner 承認なしに実行する**（create-project / update-project-content / create-version / create-deployment / update-deployment / delete-deployment は Projects に影響し、**run-script は任意の関数を実行する** — メール送信・シート書き込み等が起こりうる。gmail の送信と同じ扱い。付録 A.27）
- **apps-script のカセットをコミット・共有する**（ソースコード・デプロイメント・プロセス = 業務データを含む。`.cassettes/`（gitignore）にだけ置く）
- **apps-script の `--files` / `--parameters` を netloom に検証させる**（JSON であることだけを見る — 語彙検証は無い。不正な本文は provider のエラーが返る）
- **`update-project-content` を「部分更新」と思い込む**（**全ファイル置換** — 配列に含めたファイルだけが残る。呼び出し側が全ファイルを含める）
- **`PAGESPEED_API_KEY` / `CRUX_API_KEY` の実値をコマンドライン・メモ・カセットに書く**（netloom が環境変数から query の `key` として読む。実行例は env ファイル経由にする — シェル履歴と ps に残る）
- **psi / crux のカセットをコミット・共有する**（**URL に query キーが残る**（意図的 = replay 照合のため）+ 測定結果を含む。`.cassettes/`（gitignore）か呼び出し側の記録置き場にだけ置く）
- **PSI の live を owner 承認なしに実行する**（**キーの quota を消費する**。リトライを繰り返すと当日中に枯渇する（429））
- **netloom に PSI のキャッシュ回避を期待する**（netloom は URL をそのまま送る。新鮮な測定は呼び出し側が URL にダミーのクエリを付ける（例: `?psrun=N`））
- **psi / crux の値を netloom に判定・比較・正規化させる**（score は 0–1 のまま、histogram はそのまま。text 要約は「述べられたものを並べる」だけ。**ローカル Lighthouse との数値比較も呼び出し側の仕事**）
- **consumer の測定系（ローカル Lighthouse）を psi / crux で置き換える・Before/After に混ぜる**（psi / crux は**非公開 API** = 明示指示があるときだけ。issue #24 / 設計書 付録 A.29）
- **`YOUTUBE_API_KEY` の実値をコマンドライン・メモ・カセットに書く**（netloom が環境変数から query の `key` として読む。実行例は env ファイル経由にする — シェル履歴と ps に残る）
- **youtube のカセットをコミット・共有する**（**URL に query キーが残る**（意図的 = replay 照合のため）+ 検索語と動画 id を含む。`.cassettes/`（gitignore）か呼び出し側の記録置き場にだけ置く）
- **youtube の quota 管理を netloom に期待する**（`search.list` は 100 units/回。netloom はレート制限の待ち・リトライを作らない — 残量の管理と再実行は呼び出し側）
- **youtube のページングを netloom に期待する**（1 コマンド = 1 往復。次のページは応答の `nextPageToken` を `--page-token` に渡して呼び出し側が回す）
- **bigquery に書き込みを実行させようとする**（門が exit 2 で止める。書き込みは呼び出し側のツールに残る）
- **`auth google` の live の同意は未実行**（2026-10-19 時点。ブラウザ同意は owner が 1 回だけ実行する。手順は `docs/plan/20261019-google-auth.md` §9）。`.github/bin` の 3 本（`ga4_auth.py` / `google_calendar_auth.py` / `gas-mcp-server-auth.py`）の置き換えと、追跡下トークン JSON の追跡解除は**呼び出し側（thch-vape.shop）の作業**（設計書 §11 N19）
- **psi / crux の live は未実行**（2026-10-19 時点。**owner 承認が前提 — PSI は quota を消費する**。手順は `docs/plan/20261019-psi-crux.md` §5。実キーでの応答形（loadingExperience の有無、quota エラーの本文、CrUX のレート制限）はその 1 回で判明する）
- **呼び出し側（seo-operations）の置き換えはしない（決定）**（owner 決定 2026-10-18 = ローカル Lighthouse を正とし、psi / crux では置き換えない。PSI / CrUX は別測定系として `data/psi/cassettes/`・`data/crux/cassettes/` に証跡を残す運用を seo-operations が決める。issue #24 / 設計書 付録 A.29・§11 N29）
- **crux history の `--metrics` は無い**（issue のフラグ集合のまま。必要になったら 1 フラグ追加。設計書 §11 N29 予約）
- **psi / crux の csv は作らない**（応答が深い入れ子（Lighthouse result / histogram）で、列の選択が netloom の解釈になる。meta / calendar と同じ判断。json / text / verbatim のみ）
- **youtube の csv は作らない**（応答の `items[]` が深い入れ子（snippet / id / statistics / contentDetails）で、列の選択が netloom の解釈になる。psi / crux と同じ判断。json / text / verbatim のみ）
- **youtube の live は親が実行**（2026-10-19 時点。search.list 1 本 + videos.list 1 本 ≒ 110 units。手順は `docs/plan/20261019-youtube.md` §5。実キーでの応答形（quota エラーの本文、`items` 構造の揺れ、`nextPageToken` の形）はその 1 回で判明する。設計書 §11 N31）
- **youtube の予約コマンド（作らない。必要になったら 1 コマンド = 1 endpoint）**: `channels.list` / `playlistItems.list`（id → チャンネル補完）、search の `order` / `videoCaption` 等の追加 pass-through、`part` の自由指定（現状はコマンド固定。設計書 付録 A.31 判断 D3 / §11 N31）
- **zenodo のカセットをコミット・共有する**（record / deposition の本文を持つ。`.cassettes/`（gitignore）か呼び出し側の記録置き場にだけ置く）
- **`deposition-publish` を `--allow-publish` なしで live 実行しようとする**（exit 2 で止まる。**公開 DOI は取り消せない**ので、承認を明示する門。`--allow-prod-write` / `--allow-send` と同じ流儀）
- **upload のカセットに実ファイルの中身を期待する・残す**（カセットには field / sha256 / size だけ。バイトもファイル名も残らない — replay は digest で照合する。設計書 付録 A.32 判断 D21）
- **zenodo に下書きの門（確認フラグ）を期待する**（create / update / delete / upload / file delete / newversion は**公開側の副作用ではない**ので門が無い。門は不可逆な publish だけ。設計書 付録 A.32 判断 D19）
- **zenodo に公開済み deposition の編集・削除を通させる**（Zenodo が拒否する — それが provider の答え。netloom は判定せず exit 1 で返す）
- **zenodo の `--id` / `--file-id` を推測させる**（netloom は record / deposition / file の一覧を持たない。DOI を id にするときは**API の path が取る形**で書く — `/` は path の区切りになる）
- **zenodo の live（特に publish / delete）を勝手に実行する**（`ZENODO_TOKEN` の手配と **publish / delete は owner の承認**が前提。手順は `docs/plan/20261019-zenodo.md`。実測で record の member / versions の封筒 / sort・size の受け付け / deposition の `state` / 書き込みの応答形が判明する）
- **呼び出し側（japan-cannabinoid-trends）の置き換えは未処理**（旧スクリプト `scripts/collect-youtube-japanese-keywords.sh` 等の置き換え範囲は JCT が決める。**絶対日付の年次スライスは Apify actor では代替不可**なので、DDD の棚卸しの「置換不可（C）」は `youtube search` で解消しうる。設計書 §11 N31）
- **同意フローのトークン更新（refresh だけを行うモード）は作らない**（データコマンドが毎回交換するので不要。`auth google` は同意 1 回。設計書 付録 A.22）

# 正本（仕様を確認したいとき）

- 設計書 `docs/design/netloom-development-design.md`（CLI と出力形式は付録 A。Apify は §5.1 / §7 / 付録 A.9、X は §5.1 / §7 / 付録 A.10、GA4 は §5.1 / §7 / 付録 A.11、GSC は §5.1 / §7 / 付録 A.12、news / cache は §5.1 / §7 / 付録 A.15、article は付録 A.16、contact は §5.1 / §7 / 付録 A.17、ga4-orders は §5.1 / §7 / 付録 A.18、openseo は §5.1 / §7 / 付録 A.19、gmail は §5.1 / §7 / 付録 A.20）
- 実装メモ `docs/plan/20261017-mvp-implementation-notes.md`（実測した応答形と判断。GA4 は §8、GSC は §9）
- Apify の計画・レビュー・QA: `docs/plan/20261017-apify-support.md`
- X API v2 の計画・レビュー・QA: `docs/plan/20261018-x-api-support.md`
- GA4 の計画・レビュー・QA: `docs/plan/20261018-ga4-support.md`
- GSC の計画・レビュー・QA: `docs/plan/20261018-gsc-support.md`
- news / cache / article の計画・レビュー・QA（issue #2 / #5。live の手順は §7 / §8）: `docs/plan/20261019-news-api.md`
- contact / ga4-orders の計画・レビュー・QA（issue #3 / #4。live の手順は §7）: `docs/plan/20261019-contact-ga4-orders.md`
- openseo の計画・レビュー・QA（issue #1 第 2 弾 / #6。live の実測は §7 / §8。**issue #10 の 2 コマンドは追補節**）: `docs/plan/20261019-openseo.md`
- gmail の計画・レビュー・QA（issue #1 第 2 弾 / #6。live は読み取りのみ実測、送信の手順は §7）: `docs/plan/20261019-gmail.md`
- meta-page / meta-instagram（Meta Graph API）の計画・レビュー・QA（issue #1 第 2 弾。live の手順は §7 / 未確認は §9）: `docs/plan/20261019-meta-graph.md`
- Google OAuth 認証（`auth google`）の計画・レビュー・QA（issue #11。live の同意の手順は §9）: `docs/plan/20261019-google-auth.md`
- bigquery（BigQuery 読み取り専用クエリ）の計画・レビュー・QA（issue #19。**live は未実行** — owner 承認が前提。手順は §7）: `docs/plan/20261019-bigquery.md`
- calendar（Google Calendar）の計画・レビュー・QA（issue #20。**live は未実行** — owner 承認が前提。手順は §7）: `docs/plan/20261019-calendar.md`
- apps-script（Google Apps Script API 13 コマンド）の計画・レビュー・QA（issue #21。**live は未実行** — owner 承認が前提。手順は §7）: `docs/plan/20261019-apps-script.md`
- psi / crux（PageSpeed Insights API v5 と CrUX API）の計画・レビュー・QA（issue #23。**live は未実行** — owner 承認が前提（PSI は quota 消費）。手順は §5。**非公開 API 化（issue #24）の追補節を含む**）: `docs/plan/20261019-psi-crux.md`
- youtube（YouTube Data API v3）の計画・レビュー・QA（issue #29。**live は親が実行** — search.list 1 本 + videos.list 1 本 ≒ 110 units。手順は §5）: `docs/plan/20261019-youtube.md`

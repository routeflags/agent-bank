#!/usr/bin/env python3
# GitHub 調達スキルの初期シード CSV 生成（計画書 documents/plans/dev/20261106_seed_personas_github_skills.md の T1〜T3）。
#
# 使い方:
#   python3 script/generate_github_seed_csvs.py
#
# - social-media-operations の catalog.jsonl から license_status=verified かつ
#   MIT / Apache-2.0 の行だけを対象にする（ambiguous / missing は絶対に含めない）。
# - raw の SKILL.md を SHA 連番ディレクトリ配下から探索し、カタログの sha256 と照合する。
#   不一致・欠落があればその skill を除外リストに入れ、CSV に含めない。
# - 出力: db/import/seed_github_users_20261106.csv（23 件）、
#          db/import/seed_github_listings_20261106.csv（照合通過分）
# - タイトル（機能名のみ）・日本語説明・カテゴリの対応表は下の SKILLS が正本。
# - social-media-operations 側には一切書き込まない（読み取りのみ）。
import csv
import hashlib
import io
import json
import os
import re
import sys

BASE = "/Users/bookair18/OS/home/Codes/github.com/routeflags/social-media-operations/.delta/worktrees/22ec60bgzdx6/social-media-operations/data/github"
CATALOG = os.path.join(BASE, "processed/catalog.jsonl")
RAW = os.path.join(BASE, "raw")
OUT_USERS = "db/import/seed_github_users_20261106.csv"
OUT_LISTINGS = "db/import/seed_github_listings_20261106.csv"

LICENSE_LABEL = {"MIT": "MIT License", "Apache-2.0": "Apache License 2.0"}

# (repo_full_name, skill_path) -> (title, description_ja, category_url)
# タイトルは機能名のみ（ペルソナ名は付けない）・65 文字以内。
# カテゴリは agent-bank の category.url。対応表は計画書 §4 のまま。
SKILLS = [
    (("DietrichGebert/ponytail", "skills/ponytail/SKILL.md"), "無駄を削る実装",
     "どんな開発タスクにも最小の変更で完全に応える、手抜き上手な熟練ペルソナ。過剰設計の相談相手にも。", "category2"),
    (("DietrichGebert/ponytail", ".openclaw/skills/ponytail-audit/SKILL.md"), "リポジトリ品質監査",
     "バグ・セキュリティ・負荷・テスト不足・削除候補まで、リポジトリ全体を重要度順に監査するペルソナ。", "category2"),
    (("DietrichGebert/ponytail", ".openclaw/skills/ponytail-debt/SKILL.md"), "技術的負債の台帳",
     "コメントに埋もれた後回しを一つの負債台帳に集約し、忘れられない記録に変えるペルソナ。", "category2"),
    (("DietrichGebert/ponytail", ".openclaw/skills/ponytail-gain/SKILL.md"), "改善効果のスコアボード",
     "コード削減・コスト・速度の改善効果を一枚のスコアボードで示す、成果報告ペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/api-and-interface-design/SKILL.md"), "API・境界設計",
     "REST や GraphQL の設計、モジュール間の境界決めなど、壊れにくい公開インターフェースを導くペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/browser-testing-with-devtools/SKILL.md"), "ブラウザ実機テスト",
     "実ブラウザでの表示確認・エラー・通信・性能を手順化し、動く証拠で検証するペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/ci-cd-and-automation/SKILL.md"), "CI/CD構築",
     "ビルドからデプロイまでの流れと品質ゲートの自動化を段取りするペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/code-review-and-quality/SKILL.md"), "多軸コードレビュー",
     "合流前の差分を多角的に審査し、主観抜きの指摘で品質を守るペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/code-simplification/SKILL.md"), "コード整理整頓",
     "動くコードを壊さず読みやすく整える、可読性ファーストの整理ペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/constraint-driven-development/SKILL.md"), "品質基準の契約化",
     "品質の物差しを文書化し、基準のなし崩しを検知して守らせるペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/context-engineering/SKILL.md"), "エージェント文脈設計",
     "作業開始時や品質低下時に、エージェントへの文脈の渡し方を整えるペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/debugging-and-error-recovery/SKILL.md"), "根本原因デバッグ",
     "テスト失敗や障害を当てずっぽうでなく、体系的に原因へ遡るデバッグペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/deprecation-and-migration/SKILL.md"), "廃止・移行計画",
     "古い仕組みの廃止や利用者移行、無停止での置き換えまで段取りするペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/documentation-and-adrs/SKILL.md"), "ADR・設計記録",
     "設計判断の背景を記録に残し、未来の自分と仲間に伝わる文書を作るペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/doubt-driven-development/SKILL.md"), "敵対的設計検証",
     "重要な判断ほど別視点で徹底的に疑い、隠れた失敗要因を事前に暴くペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/frontend-ui-engineering/SKILL.md"), "UI実装職人",
     "使いやすさに配慮した画面や部品を、安っぽく見えない品質で作るペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/git-workflow-and-versioning/SKILL.md"), "Git運用・リリース",
     "作業の切り分けから変更提案、版数付け、変更履歴まで、共同作業の作法を整えるペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/idea-refine/SKILL.md"), "アイデア練り上げ",
     "まだ粗いアイデアを広げて絞り、前提の危うさを検証して企画に磨くペルソナ。", "category18"),
    (("addyosmani/agent-skills", "skills/incremental-implementation/SKILL.md"), "薄切り実装",
     "大きな変更を検証可能な薄い切片に分け、着実に積み上げる進め方のペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/interview-me/SKILL.md"), "意図の引き出し",
     "曖昧な依頼に一問ずつ切り込み、本当に作りたいものを引き出す聞き上手ペルソナ。", "category18"),
    (("addyosmani/agent-skills", "skills/observability-and-instrumentation/SKILL.md"), "可観測性・計装",
     "記録・指標・追跡を仕込み、本番の挙動を証拠つきで見える化するペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/performance-optimization/SKILL.md"), "性能最適化",
     "画面表示からデータ取得まで、計測を根拠にボトルネックを潰す高速化ペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/planning-and-task-breakdown/SKILL.md"), "タスク分解",
     "仕様を実装可能な順序つき作業に割り振り、見積もりと並行作業を見通すペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/security-and-hardening/SKILL.md"), "脆弱性対策",
     "入力処理・認証・外部連携を安全性の観点で点検し、堅牢化するペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/shipping-and-launch/SKILL.md"), "本番公開準備",
     "公開前チェックリストから段階公開、巻き戻し計画まで用意する本番デビューの伴走ペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/source-driven-development/SKILL.md"), "公式文書準拠実装",
     "公式文書を根拠に作り方を選ばせ、古い定石の混入を防ぐペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/spec-driven-development/SKILL.md"), "仕様先行開発",
     "手を動かす前に仕様を固め、曖昧さを要件文書に変える土台づくりペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/test-driven-development/SKILL.md"), "テスト駆動開発",
     "失敗・成功・整理の循環で、動く証拠と共に作るテスト駆動ペルソナ。", "category2"),
    (("addyosmani/agent-skills", "skills/using-agent-skills/SKILL.md"), "スキル案内人",
     "作業内容に合うスキルを見つけ出し、使い分けを案内する目録ペルソナ。", "category18"),
    (("paperclipai/paperclip", ".agents/skills/add-product-e2e-eval/SKILL.md"), "E2E評価追加",
     "実行環境の全体検証の流れや判定器の追加・拡張を手順化するペルソナ。", "category2"),
    (("nolanx-ai/nolanx.ai", "skills/sd2-pe/SKILL.md"), "Seedance動画生成",
     "画像・動画の参照指定から15秒動画の台本設計まで、映像生成を導くペルソナ。", "category11"),
    (("spinabot/brigade", "skills/sag/SKILL.md"), "英語TTSナレーション",
     "英文を読み上げる音声ナレーションのペルソナ。聞き取りやすい発音で文章を届ける。", "category13"),
    (("Bitterbot-AI/bitterbot-desktop", "skills/sag/SKILL.md"), "英語TTSナレーション",
     "英文を読み上げる音声ナレーションのペルソナ。聞き取りやすい発音で文章を届ける。", "category13"),
    (("xiaotianfotos/OPC", "opc-cli/SKILL.md"), "AI創作ツールチェーン",
     "音声合成・字幕・作曲から画像・動画生成までこなす、多機能AI創作ツールを使いこなすペルソナ。", "category12"),
    (("openclaw/openclaw", ".agents/skills/autoreview/SKILL.md"), "構造化コードレビュー",
     "共有のレビュー手順に沿って構造的にコードを点検するペルソナ。", "category2"),
    (("openclaw/openclaw", ".agents/skills/openclaw-debugging/SKILL.md"), "OpenClaw障害解析",
     "記録と証拠から原因を特定し、闇雲な修正に入らせない障害対応ペルソナ。", "category2"),
    (("openclaw/openclaw", ".agents/skills/openclaw-parallels-smoke/SKILL.md"), "マルチOS動作検証",
     "複数OSでの導入・起動・更新チェックを段取りし、結果を読み解く検証ペルソナ。", "category2"),
    (("openclaw/openclaw", ".agents/skills/openclaw-qa-testing/SKILL.md"), "QAシナリオ実行",
     "検証シナリオの実行・監視・拡張と、証跡の読み解きを担うペルソナ。", "category2"),
    (("openclaw/openclaw", ".agents/skills/openclaw-refactor-docs/SKILL.md"), "文書リファクタ",
     "既存文書の内容を保ったまま構成を整え、検証まで行う整理ペルソナ。", "category2"),
    (("openclaw/openclaw", ".agents/skills/release-openclaw-ci/SKILL.md"), "リリースCI監視",
     "公開作業の実行監視から不具合切り分け、公開前の最終確認まで見守るペルソナ。", "category2"),
    (("garrytan/gstack", "browser-skills/hackernews-frontpage/SKILL.md"), "HN話題収集",
     "技術系掲示板の上位話題を見出し・反応数つきで集める情報収集ペルソナ。", "risati"),
    (("garrytan/gstack", "design-consultation/SKILL.md"), "デザイン相談",
     "製品理解から市場調査、配色・書体・余白まで、デザイン全体の相談に乗るペルソナ。", "dezain"),
    (("lionelsimai/claude-skills-collection", "skills/ai-tutoring-system/SKILL.md"), "適応学習設計",
     "学習者に合わせて調整する個別指導の仕組みを設計する教育ペルソナ。", "jiao-yu-xue-xi"),
    (("morluto/rea", ".agents/skills/rea-analysis-optimization/SKILL.md"), "解析高速化",
     "解析処理の待ち時間や資源消費を抑えつつ正確さを保つ、チューニングのペルソナ。", "category2"),
    (("morluto/rea", ".agents/skills/rea-changelog-update/SKILL.md"), "リリースノート作成",
     "変更履歴から要点を拾い、感謝つきの発表文に整える発信ペルソナ。", "category2"),
    (("morluto/rea", ".agents/skills/rea-ci-tests-audit/SKILL.md"), "CI・テスト監査",
     "テストの見せかけの成功や遅さを洗い出し、自動検証の健康状態を診断するペルソナ。", "category2"),
    (("morluto/rea", ".agents/skills/rea-tool-design/SKILL.md"), "調査ツール設計",
     "調査ツールの仕様や取り決めを見直し、改善案を練る設計ペルソナ。", "category2"),
    (("morluto/rea", ".agents/skills/reverse-engineer-anything/SKILL.md"), "リバースエンジニアリング",
     "成果物や実行時の証拠から仕組みを読み解き、再構築へ導く解析ペルソナ。", "category2"),
    (("yaojingang/yao-meta-skill", "SKILL.md"), "スキル設計指南",
     "業務手順から再利用できるスキルを設計・改善・評価する、職人育成ペルソナ。", "category2"),
    (("InsiderX-Pro/video-translator", "SKILL.md"), "動画翻訳・吹替",
     "動画ファイルやURLを他言語に翻訳・吹き替えし、試聴リンクで返す翻訳ペルソナ。", "fan-yi"),
    (("sickn33/agentic-awesome-skills", "skills/photopea-embedded-editor/SKILL.md"), "Photopea組込開発",
     "Webアプリへの画像編集機能の組み込みから編集作業の自動化まで導く開発ペルソナ。", "category10"),
    (("pockebot/openpocket", "skills/capcut-edit/SKILL.md"), "CapCut動画編集",
     "動画編集アプリでのカット・テロップ・写真補正を段取り通りに進める編集ペルソナ。", "category11"),
    (("QwenLM/Qwen-MM-Plugins", "src/capabilities/api/skill/SKILL.md"), "画像音声の読解",
     "画像の質問応答・文字起こし・物体特定から音声の書き起こしまで、メディア内容の読解を担うペルソナ。", "detafen-xi1"),
    (("shiwenwen/hope-agent", "skills/ha-logs/SKILL.md"), "ログ・利用分析",
     "端末内の記録を直接調べて不具合原因や利用状況を突き止める、読み取り専用の分析ペルソナ。", "detafen-xi1"),
    (("Mindrally/skills", "data-analyst/SKILL.md"), "pandasデータ分析",
     "表計算から可視化まで、再現性のある分析手順で導くデータ分析ペルソナ。", "detafen-xi1"),
    (("nyldn/claude-octopus", "skills/flow-discover/SKILL.md"), "複合AIリサーチ",
     "複数のAIを使い分けて幅広く調べ、結果を束ねる調査ペルソナ。", "risati"),
    (("suboss87/FDEOps", "skills/debrief/SKILL.md"), "会議メモ整理",
     "会議メモや議事録から決定事項と次の行動を抜き出し、根拠つきでまとめるペルソナ。", "category20"),
    (("retlehs/quien", "SKILL.md"), "ドメイン・SEO調査",
     "サイトの登録情報から設定・表示速度・利用技術まで調べる調査ペルソナ。", "maketeingu"),
    (("seo-skills/seo-audit-skill", "SKILL.md"), "SEOサイト監査",
     "多数の検査規則でサイトを採点し、改修前後の差分まで示す監査ペルソナ。", "maketeingu"),
    (("sanyuan0704/sanyuan-skills", "skills/sigma/SKILL.md"), "1対1家庭教師",
     "対話と視覚資料で理解度に合わせて進む、1対1の個別指導ペルソナ。", "jiao-yu-xue-xi"),
]

HEX40 = re.compile(r"^[0-9a-f]{40}$")


def index_raw_files():
    """raw 配下の全ファイルを (owner, repo, sha, skill_path) -> フルパスに索引化する。"""
    index = {}
    for root, _dirs, files in os.walk(RAW):
        for name in files:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, RAW)
            parts = rel.split(os.sep)
            sha_i = next((i for i, p in enumerate(parts) if HEX40.match(p)), None)
            if sha_i is None or sha_i < 3 or sha_i + 1 >= len(parts):
                continue
            owner, repo, sha = parts[sha_i - 2], parts[sha_i - 1], parts[sha_i]
            skill_path = "/".join(parts[sha_i + 1:])
            index[(owner, repo, sha, skill_path)] = full
    return index


def main():
    catalog_rows = [json.loads(line) for line in open(CATALOG, encoding="utf-8") if line.strip()]
    eligible = [r for r in catalog_rows
                if r.get("license_status") == "verified" and r.get("license_spdx") in ("MIT", "Apache-2.0")]
    leaked = [r for r in catalog_rows
              if (r.get("license_status"), r.get("license_spdx")) not in (("verified", "MIT"), ("verified", "Apache-2.0"))]
    # 対象外（ambiguous / missing）が混入していないことの宣言的確認
    assert all(r not in eligible for r in leaked)
    print(f"カタログ総行数={len(catalog_rows)} 対象(verified MIT/Apache-2.0)={len(eligible)} 対象外={len(leaked)}")
    assert len(eligible) == 60, f"対象が60件でない: {len(eligible)}"

    table = {(repo, path): (title, desc, cat) for (repo, path), title, desc, cat in SKILLS}
    assert len(table) == 60, f"日本語化テーブルが60件でない: {len(table)}"

    index = index_raw_files()
    ok, excluded = [], []
    for r in eligible:
        owner, repo = r["repo_full_name"].split("/", 1)
        key = (owner, repo, r["commit_sha"], r["skill_path"])
        full = index.get(key)
        if full is None:
            excluded.append((r, "rawファイル欠落"))
            continue
        digest = hashlib.sha256(open(full, "rb").read()).hexdigest()
        if digest != r["sha256"]:
            excluded.append((r, f"sha256不一致 {digest} != {r['sha256']}"))
            continue
        entry = table.get((r["repo_full_name"], r["skill_path"]))
        if entry is None:
            excluded.append((r, "日本語化テーブル未登録"))
            continue
        ok.append((r, full, entry))

    print(f"sha256照合: 一致={len(ok)} 除外={len(excluded)}")
    for r, reason in excluded:
        print(f"  除外: {r['repo_full_name']} {r['skill_path']} 理由={reason}")
    if excluded:
        sys.exit(f"除外が {len(excluded)} 件あるため中断（計画書T1: 除外は登録しない）")

    # 出品者 23 名（リポジトリオーナー）。連絡先メアドは使わず合成アドレス。
    owners = sorted({r["repo_full_name"].split("/", 1)[0] for r, _, _ in ok})
    print(f"オーナー数={len(owners)}")
    assert len(owners) == 23, f"オーナーが23名でない: {len(owners)}"

    def slug(owner):
        return owner.lower()

    def username(owner):
        return owner.lower().replace("-", "_")

    with open(OUT_USERS, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["email", "given_name", "family_name", "display_name", "username", "locale", "is_admin", "password"])
        for owner in owners:
            assert re.fullmatch(r"[a-z0-9_]{3,20}", username(owner)), owner
            w.writerow([f"{slug(owner)}@agentbank.dev", owner, owner, owner, username(owner), "ja", "false", ""])

    with open(OUT_LISTINGS, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["title", "price_cents", "author_email", "description", "skill_markdown", "category", "open", "currency", "listing_shape"])
        for r, full, (title, desc_ja, category) in sorted(ok, key=lambda t: (t[0]["repo_full_name"], t[0]["skill_path"])):
            assert 2 <= len(title) <= 65, title
            license_label = LICENSE_LABEL[r["license_spdx"]]
            description = (
                f"{desc_ja}\n\n"
                f"出典: {r['repo_url']}（コミット {r['commit_sha']} 時点の SKILL.md 全文）\n"
                f"ライセンス: {license_label}（カタログ判定: verified）\n"
                f"取得: {r['retrieved_at']} / SHA256: {r['sha256']}（登録時に照合）"
            )
            assert len(description) <= 5000, title
            body = open(full, encoding="utf-8").read()
            owner = r["repo_full_name"].split("/", 1)[0]
            w.writerow([title, 1000, f"{slug(owner)}@agentbank.dev", description, body, category, "true", "JPY", "order_type"])

    print(f"出力: {OUT_USERS}（{len(owners)} 行+見出し） / {OUT_LISTINGS}（{len(ok)} 行+見出し）")


if __name__ == "__main__":
    main()

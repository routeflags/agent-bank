# コミュニティ翻訳（community_translations）の運用

## 仕組み

取引形状（トランザクションタイプ）の名前・ボタン文言は
`community_translations` テーブルにロケール別で保存される。
ビューは `t(shape.name_tr_key)` で解決し、**指定ロケールの行が無い場合は
fallback で en 行が表示される**。

そのため「取引の種類： Offering with online payment」のように、
ja コミュニティなのに英語が表示される。

## 発生原因

形状作成時（`TransactionTypeCreator#create_listing_shape`）に
`community.locales` の全ロケールで翻訳行を作るが、**当時 locales が `["en"]`
だった場合、ja 行は作られない**。後から locales に ja を追加しても既存形状の
翻訳は自動生成されない。

## 症状別の修正方法

### 既存形状に ja 翻訳を追加する（正規経路）

管理パネル → 出品設定 → 注文型（order type）編集画面を開き、
日本語ロケールの「名前」「ボタンラベル」を入力して保存する
（`ShapeService.update` が `community_translations` を更新する）。

### 一括で直す（多数の形状がある場合）

`community_translations` に en 行のみ存在するキーへ ja 行を INSERT する:

```sql
INSERT INTO community_translations (community_id, locale, translation_key, translation, created_at, updated_at)
SELECT st.community_id, 'ja', ct.translation_key,
       -- 日本語訳は形状ごとに置き換える
       CASE ct.translation
         WHEN 'Offering with online payment'    THEN 'オンライン決済あり'
         WHEN 'Offering without online payment' THEN 'オンライン決済なし'
         WHEN 'Request'                         THEN '問い合わせる'
         ELSE ct.translation
       END,
       NOW(), NOW()
FROM community_translations ct
JOIN listing_shapes st ON st.name_tr_key = ct.translation_key OR st.action_button_tr_key = ct.translation_key
WHERE ct.locale = 'en'
  AND NOT EXISTS (
    SELECT 1 FROM community_translations j
    WHERE j.translation_key = ct.translation_key AND j.locale = 'ja'
  );
```

### 新規形状を作った場合

`community.settings["locales"]` に `ja` が含まれていれば
作成時に自動で ja 翻訳が生成される。locales 設定を先に確認すること。

## 翻訳済みキー一覧（2026-10-09 時点・開発DB）

| translation_key（例） | en | ja |
|---|---|---|
| f3785120-… | Offering with online payment | オンライン決済あり |
| 287c9214-… | Offering without online payment | オンライン決済なし |
| 4c52eea9-… | Request | 問い合わせる |
| 4427c747-… | Request | 問い合わせる |

※ UUID は環境ごとに異なる。上記は開発DBの値。

## 確認方法

```bash
# 翻訳サービス経由で解決できるか
DISABLE_BOOTSNAP_COMPILE_CACHE=1 RAILS_ENV=development bundle exec rails runner '
  svc = TranslationService::API::API.translations
  key = ListingShape.find_by(name: "offering-with-online-payment").name_tr_key
  puts svc.get(Community.first.id, translation_keys: [key], locales: %w[ja en]).data.inspect'
```

ページ上では `/ja/listings/new` の「取引の種類： …」が日本語になることを確認する。

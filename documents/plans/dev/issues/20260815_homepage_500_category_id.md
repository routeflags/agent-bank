# Issue: トップページ 500 エラー — `category_id: Missing mandatory value`

## 優先度
🔴 高

## 対象
- 対象ファイル: `app/services/listing_index_service/api/listings.rb`, `app/utils/entity_utils.rb`, `app/services/listing_index_service/search/converters.rb`
- スクリーンショット: `screenshots/20260815/02_homepage_500_seed_data.png`

## エラー詳細

```
ArgumentError (Error(s) in
  /opt/app/app/services/listing_index_service/api/listings.rb:27:
  'block in ListingIndexService::API::Listings#search':
  listings[0].category_id: Missing mandatory value.,
  listings[1].category_id: Missing mandatory value., ...)
```

## 原因の調査結果

### エラーチェーン

```
HomepageController#index
  → find_listings
    → ListingIndexService::API::Listings#search
      → process_results (L40)
        → EntityUtils::EntityBuilder#build (L371)
          → listing_hash の各フィールドを検証
            → category_id: nil → "Missing mandatory value" エラー
```

### `EntityUtils::EntityBuilder` の検証ロジック

```ruby
# entity_utils.rb:371-379
def build
  result = {}
  @definitions.each do |key, definition|
    value = definition[:value]
    # ...
    if definition[:mandatory] && value.nil?
      errors << "#{key}: Missing mandatory value"
    end
    result[key] = value
  end
  raise(ArgumentError, "Error(s) in #{loc}: #{error_msg(result)}") if errors.any?
  result
end
```

### `ListingIndexService::API::Listings` の検証定義

```ruby
# listings.rb
entity_definition(:listing, {
  # ...
  :category_id => entity_fixer(:mandatory_integer),
  # ...
})
```

**`category_id` は `mandatory_integer` として定義されており、nil の場合にエラーになる。**

### DB の現状

```sql
SELECT id, title, category_id FROM listings WHERE deleted = FALSE;
-- ID=14, category_id=1 (修正済み)
-- ID=15, category_id=1 (修正済み)
-- ...
```

**今回の調査で `UPDATE listings SET category_id = 1 WHERE category_id IS NULL` を実行し、一時的に回避した。しかし本来は listing 作成時に `category_id` を必須にする必要がある。**

### なぜ `category_id` が nil になるのか

`Listing` モデルの `category_id` カラムは NOT NULL 制約がない:

```sql
-- db/structure.sql
`category_id` int(11) DEFAULT NULL
```

Sharetribe の正規フローでは `ListingsController#create` で `category_id` をセットするが、`rails runner` や `db:seed` で直接作成した場合に nil になり得る。

## 修正案

### A案（推奨）: `converters.rb` でデフォルト値を設定

```ruby
# converters.rb
category_id: l.category_id || 0,
```

### B案: マイグレーションで NOT NULL 制約を追加

```ruby
# db/migrate/XXXXXX_add_not_null_to_category_id.rb
class AddNotNullToCategoryId < ActiveRecord::Migration[6.1]
  def up
    Listing.where(category_id: nil).update_all(category_id: 0)
    change_column :listings, :category_id, :integer, null: false, default: 0
  end

  def down
    change_column :listings, :category_id, :integer, null: true
  end
end
```

### C案: `Listing` モデルにバリデーション追加

```ruby
# app/models/listing.rb
validates :category_id, presence: true
```

## 状態
一時的回避済み（`UPDATE listings SET category_id = 1`）。恒久修正は未実施。

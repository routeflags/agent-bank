# Issue: ログイン失敗 — `emails` テーブルにレコードが存在しない

## 優先度
🔴 高

## 対象
- 対象ファイル: `config/initializers/devise.rb`, `app/controllers/people_controller.rb`, `app/controllers/sessions_controller.rb`
- スクリーンショット: `screenshots/20260815/05_login_failed.png`

## 認証フローの調査結果

### Sharetribe のカスタム認証フロー

Sharetribe は Devise を使用するが、**標準の Devise を使わず、DatabaseAuthenticatable をモンキーパッチ**している。

```
SessionsController#create
  → authenticate_person! (Devise/Warden)
    → Devise::Strategies::DatabaseAuthenticatable#authenticate!
      → DatabaseAuthenticatableHelpers.resolve_person(login, password, community_id)
        → find_by_username_or_email(login, community_id)
          ├─ login に @ を含む → find_person_by_email() を優先
          │   └─ Person.joins("LEFT OUTER JOIN emails ON emails.person_id = people.id")
          │       .where("emails.address = :login AND ...")
          └─ @ を含まない → find_person_by_username() を優先
              └─ Person.where("people.username = :login AND ...")
```

### メールアドレスでログインする場合（今回のケース）

`admin2@capafy.com` のように `@` を含む login は `find_person_by_email` が呼ばれる:

```sql
SELECT people.*
FROM people
LEFT OUTER JOIN emails ON emails.person_id = people.id
WHERE (people.is_admin = '1' OR people.community_id = 6)
  AND emails.address = 'admin2@capafy.com'
```

**`emails` テーブルに `address = 'admin2@capafy.com'` のレコードがないため、LEFT OUTER JOIN で nil が返り、ユーザーが見つからない。**

### ユーザー名でログインする場合（回避策）

`admin2` のように `@` を含まない login は `find_person_by_username` が呼ばれる:

```sql
SELECT people.*
FROM people
WHERE (people.is_admin = '1' OR people.community_id = 6)
  AND people.username = 'admin2'
```

**これは `emails` テーブルを参照しないため、ログイン可能。**

### 正規のサインアップフローで `emails` レコードが作成されるタイミング

`PeopleController#new_person` (L271-298):

```ruby
def new_person(initial_params, current_community)
  # 1. Person オブジェクトをビルド
  person = build_devise_resource_from_person(params)

  # 2. Email オブジェクトを新規作成（まだ保存されない）
  email = Email.new(
    person: person,
    address: params[:email].downcase,
    send_notifications: true,
    community_id: current_community.id
  )

  # 3. Person に Email を関連付ける
  person.emails << email

  # 4. Person を保存（emails も一緒に保存される）
  person.save!

  # 5. メール確認処理
  if APP_CONFIG.skip_email_confirmation
    email.confirm!              # メール確認をスキップ
  else
    Email.send_confirmation(email, @current_community)  # 確認メール送信
  end
end
```

**結論: 正規のサインアップフローでは、`Person` 作成時に必ず `Email` も一緒に作成される。**

### 今回の問題が発生した原因

`rails runner` で `Person.new` → `person.save!` を直接実行した場合:

```ruby
# ❌ これだと emails レコードが作成されない
Person.new(email: 'test@test.com', password: 'Pass1!')
person.save!
```

`Person.new` は Devise の `DatabaseAuthenticatable` に `email` カラムを設定するが、`emails` テーブルにレコードは作成されない。Sharetribe は `emails` テーブルを認証の正としているため、メールアドレスでログインできない。

## 修正案

### A案（推奨）: ダミーデータ作成時に `emails` レコードも作成する

開発環境のダミーデータ作成スクリプトで、`Person` 作成時に必ず `Email` も作成する:

```ruby
person = Person.new(
  community_id: 6,
  username: 'admin2',
  email: 'admin2@capafy.com',
  given_name: 'Test',
  family_name: 'Admin'
)
person.password = 'TestPassword1!'
person.password_confirmation = 'TestPassword1!'
person.save!

# emails テーブルにレコードを作成（必須）
Email.create!(
  person: person,
  address: 'admin2@capafy.com',
  community_id: 6,
  confirmed_at: Time.current
)
```

### B案: `people.username` でログインする

Sharetribe の認証フローでは、`@` を含まないログインは `people.username` から検索する。`rails runner` でユーザーを作成した場合:

```bash
docker compose exec web bin/rails runner "
person = Person.last
puts 'Username: ' + person.username  # => 'admin2'
"
# ログイン画面に username を入力（メールアドレスではない）
```

### C案: 開発環境でメール確認をスキップする

`config/application.rb` に以下を追加:

```ruby
config.skip_email_confirmation = true
```

これで `Email.send_confirmation` が呼ばれないが、`emails` レコード自体は作成されるため、ログイン可能になる。

## 検証結果

```bash
# 修正後（Email レコードを作成）
Email.create!(person_id: person.id, address: person.email, community_id: 6, confirmed_at: Time.current)

# ログイン成功を確認
curl -X POST http://localhost:3000/en/sessions \
  -d "person[login]=admin2@capafy.com&person[password]=TestPassword1!" \
  -L -o /dev/null -w "%{http_code}"
# => 200 (リダイレクト後)
```

## 状態
未修正。開発環境のダミーデータ作成スクリプトの修正が必要。

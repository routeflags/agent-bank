# frozen_string_literal: true

# MCP（ローカル実行）用のパーソナルアクセストークン（Issue #141）。
#
# 平文トークンは保存せず、SHA-256 の digest だけを持つ。平文は発行時に
# 一度だけ呼び出し元へ返し、以降は digest の照合にだけ使う。
# 用途が違う既存の `auth_tokens`（unsubscribe / login 用）とは別テーブル。
class CreateAPITokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.string :person_id, limit: 22, null: false
      t.string :name, limit: 100
      t.string :token_digest, null: false
      t.json :scopes
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.integer :daily_cost_limit_cents, null: false, default: 500

      t.timestamps
    end

    add_index :api_tokens, :person_id
    add_index :api_tokens, :token_digest, unique: true
  end
end

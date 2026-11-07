# frozen_string_literal: true

require 'rails_helper'

RSpec.describe APIToken, type: :model do
  let(:community) { FactoryBot.create(:community) }
  let(:person) { FactoryBot.create(:person, community_id: community.id) }

  # 検証用の有効なトークンを作る。
  # @return [Array(APIToken, String)]
  def issue(scopes: ["read"], **attrs)
    token, raw_token = described_class.issue!(person: person, name: "テスト用", scopes: scopes)
    token.update!(attrs) if attrs.any?
    [token, raw_token]
  end

  describe ".issue!" do
    it "レコードと平文トークンを返す" do
      token, raw_token = issue

      expect(token).to be_persisted
      expect(raw_token).to be_a(String)
      expect(raw_token).to be_present
    end

    it "DB には digest だけを保存し、平文は保存しない" do
      token, raw_token = issue

      expect(token.reload.token_digest).to eq(Digest::SHA256.hexdigest(raw_token))
      expect(described_class.find_by(token_digest: raw_token)).to be_nil
      expect(token.attributes.values.map(&:to_s)).not_to include(raw_token)
    end

    it "既存の digest と衝突しない平文を毎回発行する" do
      _token1, raw_token1 = issue
      _token2, raw_token2 = issue

      expect(raw_token1).not_to eq(raw_token2)
    end

    it "scopes を省略すると read だけが付く" do
      token, = described_class.issue!(person: person, name: "テスト用")

      expect(token.scope_list).to eq(["read"])
    end

    it "指定した scopes を保存する" do
      token, = issue(scopes: ["read", "run"])

      expect(token.reload.scope_list).to contain_exactly("read", "run")
    end

    it "日次コスト上限の既定値は 500 セント" do
      token, = issue

      expect(token.daily_cost_limit_cents).to eq(500)
    end

    it "不明なスコープは受け付けない" do
      expect {
        described_class.issue!(person: person, name: "テスト用", scopes: ["admin"])
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "名前が空なら受け付けない" do
      expect {
        described_class.issue!(person: person, name: "")
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "有効期限を指定できる" do
      expires_at = 30.days.from_now
      token, = issue(expires_at: expires_at)

      expect(token.reload.expires_at).to be_within(1.second).of(expires_at)
    end
  end

  describe ".authenticate" do
    it "未失効・期限内の平文トークンからレコードを引く" do
      token, raw_token = issue

      expect(described_class.authenticate(raw_token)).to eq(token)
    end

    it "一致しない平文には nil を返す" do
      issue

      expect(described_class.authenticate("not-a-real-token")).to be_nil
    end

    it "空・nil には nil を返す" do
      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("")).to be_nil
    end

    it "失効済みトークンには nil を返す" do
      token, raw_token = issue
      token.revoke!

      expect(described_class.authenticate(raw_token)).to be_nil
    end

    it "期限切れトークンには nil を返す" do
      _token, raw_token = issue(expires_at: 1.minute.ago)

      expect(described_class.authenticate(raw_token)).to be_nil
    end

    it "期限内のトークンは認証できる" do
      token, raw_token = issue(expires_at: 1.minute.from_now)

      expect(described_class.authenticate(raw_token)).to eq(token)
    end
  end

  describe "#allows?" do
    it "read トークンは read だけを許可する" do
      token, = issue(scopes: ["read"])

      expect(token.allows?(:read)).to be true
      expect(token.allows?(:run)).to be false
    end

    it "run トークンは run と read を許可する" do
      token, = issue(scopes: ["run"])

      expect(token.allows?(:run)).to be true
      expect(token.allows?(:read)).to be true
    end

    it "スコープ名は文字列でも判定できる" do
      token, = issue(scopes: ["read"])

      expect(token.allows?("read")).to be true
      expect(token.allows?("unknown")).to be false
    end
  end

  describe "#revoke!" do
    it "失効日時を記録する" do
      token, = issue

      expect { token.revoke! }.to change { token.revoked_at }.from(nil)
      expect(token.reload.revoked?).to be true
      expect(token.active?).to be false
    end

    it "既に失効済みなら日時を変えない（冪等）" do
      token, = issue(revoked_at: 10.minutes.ago)
      before_revoked_at = token.revoked_at

      expect { token.revoke! }.not_to raise_error
      expect(token.reload.revoked_at).to be_within(1.second).of(before_revoked_at)
    end
  end

  describe "#expired?" do
    it "有効期限が未設定なら false" do
      token, = issue

      expect(token.expired?).to be false
    end

    it "有効期限を過ぎたら true" do
      token, = issue(expires_at: 1.second.ago)

      expect(token.expired?).to be true
    end
  end

  describe "#touch_last_used!" do
    it "last_used_at を更新し、updated_at は動かさない" do
      token, = issue
      before_updated_at = token.updated_at

      token.touch_last_used!
      token.reload

      expect(token.last_used_at).to be_present
      expect(token.updated_at).to eq(before_updated_at)
    end
  end
end

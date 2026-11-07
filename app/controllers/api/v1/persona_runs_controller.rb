# frozen_string_literal: true

# ペルソナを 1 リクエストで実行する API（Issue #144）。
#
# MCP サーバー（#143）の run_persona ツールが使う。認証は API 共通 concern
# （#142）で、要求 scope は run（read を包含する）。
#
# 実行はブラウザのチャットと同じ `PersonaExecutorJob` を **同期実行** する。
# Delayed::Job に enqueue しないのは、ローカル開発ではワーカー（Delayed::Job）
# を動かさない方針（AGENTS.md）のため。応答は Action Cable のチャンクを待たず、
# ジョブ完了後に保存済みの assistant メッセージを読んで返す。
#
# タイムアウト: 独自の `Timeout.timeout` は使わない。#104 の残高クリップで
# 出力上限が決まり、上限までのストリームで自然に終わるため、時間で打ち切ると
# 「生成済みの応答を捨てて課金だけ残る」経路を作りかねない。
#
# 課金はジョブ 1 回につき `UsageRecord` 1 行（`BillingService` が wallet から
# 引く）。このコントローラはリトライしない（二重課金を避ける）。
#
# 応答:
#   200 {content, usage: {total_tokens, cost_cents}, balance_cents, session_id}
#   402 insufficient_balance（topup_url 付き）
#   404 persona_not_found / session_not_found
#   422 invalid_request
#   429 concurrent_run（同じ資格情報で実行中）
#   502 run_failed（AI プロバイダー未設定・上流エラーなどで応答を作れなかった）
#
# `usage.cost_cents` は `UsageRecord#cost_cents`（AI モデルの原価）。利用者への
# 請求額は `UsageRecord#charge_cents` で、値が違う（請求は出品の単価×トークン数、
# 原価はモデルの $/1k から計算）。応答契約は #144 の決定どおり cost_cents だけを
# 載せ、請求額は `balance_cents` の変化で見る。
class API::V1::PersonaRunsController < ApplicationController
  include APIAuthenticatable

  # 課金を伴う実行。
  api_requires_scope :run

  # 同時実行の排他に使う MySQL 名前付きロックの接頭辞。
  # Bearer はトークン単位、Cookie 認証（トークンが無い）は人単位で 1 本にする。
  RUN_LOCK_TOKEN_PREFIX = "api_run_token"
  RUN_LOCK_PERSON_PREFIX = "api_run_person"

  # `max_tokens` の形が不正であることを表す番兵値。
  INVALID = :invalid

  # POST /api/v1/personas/:id/run
  #
  # @param message [String] 送る発話（必須・空文字不可）
  # @param max_tokens [Integer] 出力トークンの上限（省略可。上限のクリップは
  #   ジョブ側の #104 の規則に任せる）
  # @param session_id [Integer] 継続するセッション（省略時は新規）
  def create
    message = params[:message].to_s.strip
    max_tokens = parse_max_tokens

    if message.empty?
      return render_error(:unprocessable_entity, "invalid_request", message: "message は必須です")
    end

    if max_tokens == INVALID
      return render_error(:unprocessable_entity, "invalid_request",
                          message: "max_tokens は正の整数で指定してください")
    end

    listing = visible_personas.find_by(id: params[:id])
    return render_error(:not_found, "persona_not_found") if listing.nil?

    session = resume_session(listing)
    return render_error(:not_found, "session_not_found") if session == :not_found

    with_run_lock { execute(listing, session, message, max_tokens) }
  end

  private

  # `max_tokens` は省略可（未指定ならジョブがモデル上限と残高から決める）。
  # 指定する場合は正の整数。上限のクリップはジョブ側（#104）に任せ、ここでは
  # 形だけ見る。
  #
  # @return [Integer, nil, Symbol] 正の整数 / 未指定は nil / 不正は INVALID
  def parse_max_tokens
    raw = params[:max_tokens]
    return nil if raw.blank?

    value = Integer(raw.to_s, 10)
    value.positive? ? value : INVALID
  rescue ArgumentError, TypeError
    INVALID
  end

  # 認証済みの人の所属マーケットプレイスの、公開中の出品だけ。
  # 判定は #145 の `PersonasController#visible_listings` と同じ規則
  # （community + `Listing.currently_open`）で、API が見せる範囲を揃える。
  def visible_personas
    Listing.where(community_id: api_community.id).currently_open
  end

  # 継続するセッション。`session_id` が無ければ nil（呼び出し側で新規作成）。
  # 他人のセッションや別の出品のセッションは、存在を漏らさず 404 にする。
  #
  # @return [ChatSession, nil, :not_found]
  def resume_session(listing)
    return nil if params[:session_id].blank?

    session = ChatSession.find_by(
      id: params[:session_id],
      person_id: current_user.id,
      listing_id: listing.id
    )
    return session if session

    Rails.logger.warn(
      "[persona_runs] session を使えません session_id=#{params[:session_id]} " \
      "person=#{current_user.id} listing=#{listing.id}"
    )
    :not_found
  end

  # 残高ゲート → セッションとユーザーメッセージ → 同期実行 → 結果。
  def execute(listing, session, message, max_tokens)
    wallet = current_user.wallet
    if wallet.nil? || wallet.below_threshold?(PersonaExecutorJob::MIN_BALANCE_CENTS)
      return render_insufficient_balance
    end

    session ||= start_session(listing)
    user_message = append_user_message(session, message, max_tokens)

    job = PersonaExecutorJob.new(session.id, user_message.id, user_message.content)
    job.perform

    assistant_message = last_assistant_message_after(session, user_message)
    return render_run_failure(session, user_message) if assistant_message.nil?

    log_completed(session, assistant_message, job.usage_record)

    render json: {
      content: assistant_message.content,
      usage: usage_payload(job.usage_record),
      balance_cents: wallet.reload.balance_cents.to_f,
      session_id: session.id
    }
  end

  # 実行前の残高確認。ジョブも同じ値で再確認するが、そこまで進むと
  # セッションとメッセージだけが残るため、入口で止める（#51 と同じ閾値）。
  def render_insufficient_balance
    render_error(:payment_required, "insufficient_balance", topup_url: topup_url)
  end

  # アシスタントの応答が作られなかった場合。ジョブは残高不足やプロバイダー
  # エラーで例外を投げずに終わり、理由を system メッセージとして残す
  # （PersonaExecutorJob#store_error_message）。その error_type で振り分ける。
  def render_run_failure(session, user_message)
    error_message = session.chat_messages
      .where(role: "system")
      .where("seq > ?", user_message.seq)
      .order(:seq)
      .last
    metadata = error_message&.metadata
    error_type = metadata.is_a?(Hash) ? metadata["error_type"] : nil

    return render_insufficient_balance if error_type == "insufficient_balance"

    render_error(
      :bad_gateway,
      "run_failed",
      message: error_message&.content || "応答を作成できませんでした",
      error_type: error_type
    )
  end

  # ジョブはセッションの最後に assistant メッセージを 1 件作る。今回の発話より
  # 後の seq に限ることで、セッションを再利用したときも今回の応答を取る。
  def last_assistant_message_after(session, user_message)
    session.chat_messages
      .where(role: "assistant")
      .where("seq > ?", user_message.seq)
      .order(:seq)
      .last
  end

  # `usage_records` は chat_session_id を持たないため、ジョブが作成した
  # `UsageRecord` をそのまま受け取る（同期実行なのでインスタンスが手元にある）。
  def usage_payload(usage_record)
    {
      total_tokens: usage_record.total_tokens,
      cost_cents: usage_record.cost_cents.to_f
    }
  end

  def start_session(listing)
    ChatSession.create!(
      person_id: current_user.id,
      listing_id: listing.id,
      billing_model: ChatSession.billing_model_for(person: current_user, listing: listing),
      started_at: Time.current,
      channel: ChatSession::CHANNEL_MCP
    )
  end

  # ユーザーメッセージを作る。実行設定はブラウザのチャット
  # （PersonaChatChannel）と同じ形で metadata に保存し、ジョブの
  # `resolve_max_tokens` / `ChatCompletionsBuilder` に拾わせる。
  #
  # `token_limit` が nil のときは「上限の指定なし」で、モデル上限と残高の
  # 小さい方に決まる（#104 / #105 の解決順はそのまま）。
  def append_user_message(session, message, max_tokens)
    user_message = session.chat_messages.create!(
      content: message,
      sender_type: "Person",
      sender_id: current_user.id,
      role: "user",
      seq: session.chat_messages.maximum(:seq)&.next || 1,
      metadata: {
        "settings" => {
          "token_limit" => max_tokens,
          "output_length" => "standard",
          "tone" => nil
        }
      }
    )

    # 履歴の見出しはブラウザのチャットと同じ扱い（最初の発話から）。
    session.update!(title: message.truncate(30)) if session.title.blank?

    user_message
  end

  # 同じ資格情報での同時実行を 1 本に制限する。
  #
  # MySQL の名前付きロックは接続（セッション）単位なので、取得と解放を同じ
  # 接続で行う必要がある。`with_connection` で接続を確保したままジョブを実行し、
  # `ensure` で必ず解放する。
  def with_run_lock
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      lock_name = run_lock_name

      unless acquire_lock(connection, lock_name)
        next render_error(:too_many_requests, "concurrent_run")
      end

      begin
        yield
      ensure
        connection.select_value("SELECT RELEASE_LOCK(#{connection.quote(lock_name)})")
      end
    end
  end

  # @return [Boolean] 取得できたら true
  def acquire_lock(connection, lock_name)
    connection.select_value("SELECT GET_LOCK(#{connection.quote(lock_name)}, 0)").to_i == 1
  end

  def run_lock_name
    if current_api_token
      "#{RUN_LOCK_TOKEN_PREFIX}:#{current_api_token.id}"
    else
      "#{RUN_LOCK_PERSON_PREFIX}:#{current_user.id}"
    end
  end

  # チャージ導線。ウォレット残高とチャージボタンはマイページ（people#show）に
  # あるため、そこを指す。API はロケールを解決しないのでパスだけを返す
  # （クライアントは自分のホストに繋げてよい）。
  def topup_url
    person_path(current_user)
  end

  # @param status [Symbol] HTTP ステータス
  # @param code [String] 機械が読むエラーコード
  # @param message [String, nil] 人向けの説明（省略可）
  # @param extra [Hash] 追加のキー（topup_url / error_type など）
  def render_error(status, code, message: nil, **extra)
    render json: { error: code, message: message, **extra }.compact,
           status: status
  end

  def log_completed(session, assistant_message, usage_record)
    Rails.logger.info(
      "[persona_runs] session=#{session.id} message=#{assistant_message.id} " \
      "channel=#{session.channel} tokens=#{usage_record&.total_tokens} " \
      "cost_cents=#{usage_record&.cost_cents} person=#{current_user.id}"
    )
  end
end

class SettingsController < ApplicationController

  before_action :except => :unsubscribe do |controller|
    controller.ensure_logged_in t("layouts.notifications.you_must_log_in_to_view_your_settings")
  end

  skip_before_action :verify_authenticity_token, only: :unsubscribe

  before_action EnsureCanAccessPerson.new(:person_id, error_message_key: "layouts.notifications.you_are_not_authorized_to_view_this_content"), except: [:unsubscribe, :show, :mcp_shortcut]
  before_action EnsureCanAccessPerson.new(:person_id, allow_admin: true, error_message_key: "layouts.notifications.you_are_not_authorized_to_view_this_content"), only: :show

  def show
    @selected_left_navi_link = "profile"
    @service = Persons::SettingsService.new(community: @current_community, params: params, current_user: @current_user)
    @service.add_location_to_person
    flash.now[:notice] = t("settings.profile.image_is_processing") if @service.image_is_processing?
  end

  def account
    target_user = Person.find_by!(username: params[:person_id], community_id: @current_community.id)
    @selected_left_navi_link = "account"
    target_user.emails.build
    has_unfinished = Transaction.unfinished_for_person(target_user).any?
    only_admin = @current_community.is_person_only_admin(target_user)

    render locals: {has_unfinished: has_unfinished, target_user: target_user, only_admin: only_admin}
  end

  def notifications
    target_user = Person.find_by!(username: params[:person_id], community_id: @current_community.id)
    @selected_left_navi_link = "notifications"
    render locals: {target_user: target_user}
  end

  def unsubscribe
    target_user = find_person_to_unsubscribe(@current_user, params[:auth])

    if target_user &&
       target_user.username == params[:person_id] &&
       params[:email_type].present? &&
       (request.get? || (request.post? && params["List-Unsubscribe"] == "One-Click"))
      if params[:email_type] == "community_updates"
        target_user.unsubscribe_from_community_updates
      elsif [Person::EMAIL_NOTIFICATION_TYPES, Person::EMAIL_NEWSLETTER_TYPES].flatten.include?(params[:email_type])
        target_user.preferences[params[:email_type]] = false
        target_user.save!
      else
        render :unsubscribe, :status => :bad_request, locals: {target_user: target_user, unsubscribe_successful: false} and return
      end
      render :unsubscribe, locals: {target_user: target_user, unsubscribe_successful: true}
    else
      render :unsubscribe, :status => :unauthorized, locals: {target_user: target_user, unsubscribe_successful: false}
    end
  end

  def listings
    @selected_left_navi_link = "listings"
    @presenter = Listing::ListPresenter.new(@current_community, @current_user, params, false)
  end

  def transactions
    @selected_left_navi_link = "transactions"
    # Issue #69: 出品スキルの第三者利用履歴。表示対象ユーザー（params[:person_id]。
    # 管理者が他人のページを見る場合も同じ一覧）の出品に紐づく chat_sessions を
    # 集計する。自分自身の利用（chat_sessions.person_id = 出品者本人）は除外する。
    # 集計クエリ: chat_sessions JOIN listings ON listings.id = chat_sessions.listing_id
    #   WHERE listings.author_id = 表示対象ユーザー
    #     AND listings.community_id = 当コミュニティ
    #     AND chat_sessions.person_id <> 表示対象ユーザー
    #   ORDER BY chat_sessions.created_at DESC
    # 既存の Admin::TransactionsService（Transaction 一覧）は他画面でも使うため
    # 壊さず、この画面から参照を外すだけにする。
    @target_user = Person.find_by!(username: params[:person_id], community_id: @current_community.id)
    @skill_usage_sessions = ChatSession.joins(:listing)
                                       .where(listings: { author_id: @target_user.id, community_id: @current_community.id })
                                       .where.not(person_id: @target_user.id)
                                       .includes(:listing, :person, :chat_messages)
                                       .order(created_at: :desc)
                                       .paginate(page: params[:page], per_page: 20)
  end

  # MCP 接続（Issue #146）。
  #
  # 発行・一覧・失効を 1 画面で完結させる。平文トークンは発行レスポンスに
  # だけ埋め、flash / session には載せない（リロードで消えることが要件）。
  #
  # トークンはつねに `current_user` のものだけを扱う。URL の person_id は
  # 設定画面の左ナビ（settings_links_for）を揃えるために受けているだけで、
  # 他人の person_id は EnsureCanAccessPerson が弾く。
  def mcp
    @selected_left_navi_link = "mcp"
    @api_tokens = current_user.api_tokens.order(created_at: :desc)
  end

  # `/settings/mcp` の短縮 URL 用。本人の画面へ送る。
  def mcp_shortcut
    redirect_to mcp_person_settings_path(current_user)
  end

  # POST /:person_id/settings/mcp_token
  #
  # 発行はサーバー側で行う（JS で API を叩かない）。エラーは同じ画面に
  # 描画して返し、入力し直せるようにする。
  def create_mcp_token
    @selected_left_navi_link = "mcp"
    name = params[:name].to_s.strip
    @token_errors = mcp_token_name_errors(name)

    if @token_errors.empty?
      @api_token, @raw_token = APIToken.issue!(person: current_user, name: name, scopes: mcp_token_scopes)
      @mcp_client_config = mcp_client_config(@raw_token)
      # 平文を含むレスポンスをブラウザの履歴・キャッシュに残さない。
      response.headers["Cache-Control"] = "no-store"
    end

    @api_tokens = current_user.api_tokens.order(created_at: :desc)
    render :mcp, status: (@token_errors.empty? ? :ok : :unprocessable_entity)
  end

  # DELETE /:person_id/settings/mcp_token
  #
  # 失効は取り消せない。他人のトークン ID を渡すと 404（存在を漏らさない）。
  def destroy_mcp_token
    token = current_user.api_tokens.find_by(id: params[:token_id])
    return head :not_found unless token

    token.revoke!
    redirect_to mcp_person_settings_path(current_user), notice: t("lamprey.mcp.revoked_notice", name: token.name)
  end

  private

  # 名前の検証はコントローラで行う（モデルのエラーメッセージは英語のため、
  # 日本語画面では lamprey.mcp.errors の文言を出す）。
  def mcp_token_name_errors(name)
    return [t("lamprey.mcp.errors.name_blank")] if name.blank?
    return [t("lamprey.mcp.errors.name_too_long", max: APIToken::MAX_NAME_LENGTH)] if name.length > APIToken::MAX_NAME_LENGTH

    []
  end

  # チェックボックス未選択なら read だけを付ける（画面の既定と一致させる）。
  # 不明な値は捨てる。
  def mcp_token_scopes
    selected = Array(params[:scopes]).map { |scope| scope.to_s.strip } & APIToken::SCOPES
    selected.presence || ["read"]
  end

  # Claude Desktop 用の設定スニペット（claude_desktop_config.json の雛形）。
  # 平文トークンをそのまま埋め込むので、発行直後のレスポンスでしか呼ばない。
  def mcp_client_config(raw_token)
    {
      "mcpServers" => {
        "agentbank" => {
          "command" => "npx",
          "args" => ["-y", "@agentbank/mcp"],
          "env" => {
            "AGENTBANK_TOKEN" => raw_token,
            "AGENTBANK_BASE_URL" => request.base_url
          }
        }
      }
    }
  end

  def find_person_to_unsubscribe(current_user, auth_token)
    current_user || Maybe(AuthToken.find_by_token(auth_token)).person.or_else { nil }
  end

end

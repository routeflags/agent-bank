module Admin2::Users
  # MCP 用パーソナルアクセストークンの管理画面（Issue #147）。
  #
  # MCP クライアントに渡したトークンを、管理者が一覧で確認し、必要なら
  # 失効させる。平文も digest も出さない（本人向けの /api/v1/tokens と同じ方針）。
  #
  # 認可は Admin2::AdminBaseController の `ensure_is_admin` に乗せる。
  # 表示・失効の対象はログイン中の管理画面の会員（@current_community.members）
  # が持つトークンだけに絞り、他のマーケットプレイスのトークンを ID 指定で
  # 失効させられないようにする。
  class APITokensController < Admin2::AdminBaseController
    PER_PAGE = 50

    # GET /admin/users/api-tokens
    def index
      @tokens = community_tokens
                .includes(:person)
                .order(created_at: :desc)
                .paginate(page: params[:page], per_page: PER_PAGE)
    end

    # POST /admin/users/api-tokens/:id/revoke
    #
    # 失効は冪等（`APIToken#revoke!`）。既に失効済みならそのまま戻る。
    def revoke
      token = community_tokens.find_by(id: params[:id])
      return head :not_found if token.nil?

      token.revoke!
      flash[:notice] = t('admin2.api_tokens.revoked', name: token.name)
      redirect_to admin2_users_api_tokens_path
    end

    private

    # このマーケットプレイスの会員が持つトークン。
    #
    # サブクエリにしているのは、`includes(:person)` と併用しても結合で
    # 行数が増えない（N+1 を避ける先読みがそのまま効く）ようにするため。
    #
    # @return [ActiveRecord::Relation<APIToken>]
    def community_tokens
      APIToken.where(person_id: @current_community.members.select(:id))
    end
  end
end

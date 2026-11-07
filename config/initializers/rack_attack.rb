class Rack::Attack

  ### 管理画面（/admin）の専用制限（Issue #120） ###

  # 管理画面は操作量が少ないので、全体制限（req/ip）より厳しくしておく。
  # ログイン試行（session/ip、sessions/login）とは独立したキーで数えるため、
  # 管理画面への大量アクセスがログイン制限を消費することはない。
  ADMIN_THROTTLE_LIMIT = 60
  ADMIN_THROTTLE_PERIOD = 5.minutes

  # ロケール接頭辞（/ja/admin など）を許容した上で、先頭セグメントが admin かを見る。
  # /admin2（旧 URL のリダイレクト）や /administrators のような類似パスは対象外。
  LOCALE_SEGMENT = /\A[a-z]{2}(?:[-_][A-Za-z]{2,4})?\z/

  def self.admin_path?(path)
    segments = path.to_s.split("/").reject(&:empty?)
    segments.shift if segments.first&.match?(LOCALE_SEGMENT)
    segments.first == "admin"
  end

  ### API のトークン単位の制限（Issue #142） ###

  # 1 トークンあたり 60 req / 5min。Cookie 認証（Bearer なし）のリクエストは
  # 同じ制限を IP 単位で数える。キーに生トークンを残さないため、digest を使う。
  API_TOKEN_LIMIT = 60
  API_TOKEN_PERIOD = 5.minutes

  # /api/v1 配下か（API ルートはロケール接頭辞の外にある）。
  API_PATH_PATTERN = %r{\A/api/v1(?:/|\z)}

  ### 実行 API のトークン単位の制限（Issue #147） ###

  # `POST /api/v1/personas/:id/run` は AI 呼び出しと課金を伴うため、
  # /api/v1 全体（60 req / 5min）とは別に、トークンあたり 20 req / 5min で数える。
  # キーは `api_throttle_key`（`token:<digest>`、Bearer が無ければ `ip:<ip>`）を
  # 再利用し、throttle 名（`api/run`）だけ分ける。独立したキーなので、実行以外の
  # 参照系リクエストが実行の枠を消費しない。
  API_RUN_LIMIT = 20
  API_RUN_PERIOD = 5.minutes

  # 実行 API のパス。ロケール接頭辞は付かない（他の API と同じ）。
  API_RUN_PATH_PATTERN = %r{\A/api/v1/personas/[^/]+/run\z}

  # 実行 API のリクエストか（POST のみ）。
  def self.api_run_path?(req)
    req.post? && API_RUN_PATH_PATTERN.match?(req.path.to_s)
  end

  # `Authorization: Bearer <token>`。ActionController のトークン認証と同じく
  # `Token <token>` 形式も受ける。
  AUTHORIZATION_PATTERN = /\A(?:Bearer|Token)\s+(\S+)\z/i

  def self.api_path?(path)
    API_PATH_PATTERN.match?(path.to_s)
  end

  # Authorization ヘッダの生トークン（無ければ nil）。
  def self.bearer_token(req)
    match = AUTHORIZATION_PATTERN.match(req.get_header("HTTP_AUTHORIZATION").to_s.strip)
    match && match[1]
  end

  # throttle のキー。生トークンはキーにもログにも残さず digest にする。
  def self.api_throttle_key(req)
    raw_token = bearer_token(req)
    return "token:#{APIToken.digest(raw_token)}" if raw_token.present?

    "ip:#{req.env['action_dispatch.remote_ip']}"
  end

  ### Configure Cache ###

  # If you don't want to use Rails.cache (Rack::Attack's default), then
  # configure it here.
  #
  # Note: The store is only used for throttling (not blacklisting and
  # whitelisting). It must implement .increment and .write like
  # ActiveSupport::Cache::Store

  # Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Throttle Spammy Clients ###

  # If any single client IP is making tons of requests, then they're
  # probably malicious or a poorly-configured scraper. Either way, they
  # don't deserve to hog all of the app server's CPU. Cut them off!
  #
  # Note: If you're serving assets through rack, those requests may be
  # counted by rack-attack and this throttle may be activated too
  # quickly. If so, enable the condition to exclude them from tracking.

  # Throttle all requests by IP (60rpm)
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:req/ip:#{req.ip}"
  throttle('req/ip', :limit => 300, :period => 5.minutes) do |req|
    req.env['action_dispatch.remote_ip'].to_s # unless req.path.start_with?('/assets')
  end

  # Throttle admin area requests by IP (60 / 5min)
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:admin/ip:#{req.ip}"
  throttle('admin/ip',
           :limit => Rack::Attack::ADMIN_THROTTLE_LIMIT,
           :period => Rack::Attack::ADMIN_THROTTLE_PERIOD) do |req|
    req.env['action_dispatch.remote_ip'].to_s if Rack::Attack.admin_path?(req.path)
  end

  # Throttle POST /api/v1/personas/:id/run by token digest (20 / 5min)
  # Key: "rack::attack:#{Time.now.to_i/:period}:api/run:#{digest or ip}"
  #
  # `api/token` より先に定義する。rack-attack は登録順に評価し、最初に
  # 超えた throttle の名前を 429 の本文（scope）に使うため、実行 API を
  # 両方の枠で同時に超えたときも `scope: "run"` で返せるようにする。
  throttle('api/run',
           :limit => Rack::Attack::API_RUN_LIMIT,
           :period => Rack::Attack::API_RUN_PERIOD) do |req|
    Rack::Attack.api_throttle_key(req) if Rack::Attack.api_run_path?(req)
  end

  # Throttle /api/v1 by token digest (60 / 5min), falling back to IP
  # Key: "rack::attack:#{Time.now.to_i/:period}:api/token:#{digest or ip}"
  throttle('api/token',
           :limit => Rack::Attack::API_TOKEN_LIMIT,
           :period => Rack::Attack::API_TOKEN_PERIOD) do |req|
    Rack::Attack.api_throttle_key(req) if Rack::Attack.api_path?(req.path)
  end

  ### Prevent Brute-Force Login Attacks ###

  # The most common brute-force login attack is a brute-force password
  # attack where an attacker simply tries a large number of emails and
  # passwords to see if any credentials match.
  #
  # Another common method of attack is to use a swarm of computers with
  # different IPs to try brute-forcing a password for a specific account.

  # Throttle POST requests to /login by IP address
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:session/ip:#{req.ip}"
  throttle('session/ip', :limit => 10, :period => 20.seconds) do |req|
    if req.path.end_with?('/sessions') && req.post?
      req.env['action_dispatch.remote_ip'].to_s
    end
  end


  # Throttle POST requests to /sessions by person[login] param
  #
  # Key: "rack::attack:#{Time.now.to_i/:period}:sessions/login:#{req.params['person']['login]']}"
  #
  # Note: This creates a problem where a malicious user could intentionally
  # throttle logins for another user and force their login requests to be
  # denied, but that's not very common and shouldn't happen to you. (Knock
  # on wood!)
  throttle("sessions/login", :limit => 10, :period => 20.seconds) do |req|
    if req.path.end_with?('/sessions') && req.post?
      # return the email if present, nil otherwise
      req.params['person']['login'].presence
    end
  end

  # Blocklist from Rails cache. See
  # https://github.com/kickstarter/rack-attack/wiki/Advanced-Configuration
  # Our implementation relies on redis cache for O(1) complexity in checking blocks
  if Rails.cache.is_a?(::ActiveSupport::Cache::RedisCacheStore)
    Rack::Attack.blocklist('block') do |req|
      # if variable `block <ip>` exists in cache store, then we'll block the request
      #
      # `Rails.cache.redis` は redis-cache-store の版によって素の Redis か
      # ConnectionPool を返す（Issue #99）。Pool の場合は `with` で接続を借りる。
      # 以前は常に Redis を前提にしていたため、本番で
      # `undefined method 'sismember' for ConnectionPool` となり全リクエストが
      # 500 になっていた。
      ip = req.env['action_dispatch.remote_ip'].to_s
      redis = Rails.cache.redis
      if redis.respond_to?(:with)
        redis.with { |conn| conn.sismember('blocked', ip) }
      else
        redis.sismember('blocked', ip)
      end
    end
  end

  ### Custom Throttle Response ###

  # 429 のボディ。API（/api/v1）だけ JSON で返し、管理画面・ログインは
  # rack-attack 既定の text/plain のまま（Issue #142）。
  # 実行 API の枠（`api/run`）で止めたときだけ `scope: "run"` を足し、
  # /api/v1 全体の枠と区別できるようにする（Issue #147）。
  # 旧 `throttled_response` は rack-attack 6 で deprecated なので使わない。
  self.throttled_responder = lambda do |req|
    if Rack::Attack.api_path?(req.path)
      body = { error: 'rate_limited' }
      body[:scope] = 'run' if req.env['rack.attack.matched'].to_s == 'api/run'
      [429, { 'content-type' => 'application/json' }, [body.to_json]]
    else
      Rack::Attack::Configuration::DEFAULT_THROTTLED_RESPONDER.call(req)
    end
  end

  ActiveSupport::Notifications.subscribe(/rack_attack/) do |name, start, finish, request_id, req|
    data = {name: name,
            start: start,
            finish: finish,
            request_id: request_id,
            request_ip: req[:request].env['action_dispatch.remote_ip'].to_s,
            matched: req[:request].env['rack.attack.matched'],
            match_type: req[:request].env['rack.attack.match_type'],
            match_data: req[:request].env['rack.attack.match_data'],
            user_agent: req[:request].env['HTTP_USER_AGENT'],
            referer: req[:request].env['SERVER_NAME']
    }
    Rails.logger.info(data.to_json)
  end

  # The rack-attack gem's Railtie inserts this middleware into the stack
  # unconditionally, so APP_CONFIG.use_rack_attack (which only controls the
  # insert_after in config/application.rb) cannot actually turn it off.
  # Leaving the throttle active in test made full cucumber runs flaky: dozens
  # of @javascript scenarios log in from 127.0.0.1, blowing past the
  # "sessions/login" limit (10 / 20s) and getting Rack::Attack's default
  # 429 "Retry later" response — which headless Chrome renders as a dead page.
  self.enabled = false if Rails.env.test?

end

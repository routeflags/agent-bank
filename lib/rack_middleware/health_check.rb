# frozen_string_literal: true

# Liveness + readiness probe for orchestrators (Convox, Docker Compose).
#
# - GET /_health returns 200 "OK" when the process is running AND the
#   primary database is reachable.
# - Returns 503 "UNAVAILABLE" when the database cannot be reached, so the
#   orchestrator stops routing traffic to the container.
#
# The path intentionally bypasses the rest of the middleware stack
# (SSL redirect, marketplace lookup): it must answer over plain HTTP
# even when `always_use_ssl` is true.
# See spec/requests/https_redirects_spec.rb.
class HealthCheck
  def initialize(app)
    @app = app
  end

  def call(env)
    req = ::Rack::Request.new(env)

    if req.path == "/_health"
      database_reachable? ? ok : unavailable
    else
      @app.call(env)
    end
  end

  private

  def ok
    [200, { "Content-Type" => "text/plain" }, ["OK"]]
  end

  def unavailable
    [503, { "Content-Type" => "text/plain" }, ["UNAVAILABLE"]]
  end

  # A real roundtrip (SELECT 1), not just a checked-out connection,
  # so a stale pool or a dead server is reported as unavailable.
  # Any failure degrades to 503; it must never raise out of the probe.
  def database_reachable?
    return true unless defined?(ActiveRecord::Base)

    ActiveRecord::Base.connection.select_value("SELECT 1")
    true
  rescue StandardError
    false
  end
end

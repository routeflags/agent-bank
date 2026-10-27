#!/bin/bash

set -e

# Expect to be passed either 'web' or 'worker' as parameter
APP_MODE="${1-web}"

# DB migration before process start (production Compose / Convox).
#
# Order: runs AFTER secure-environment decryption (script/entrypoint.sh)
# so credentials from ENV are available, and BEFORE the web/worker
# process starts serving or consuming jobs.
#
# Conditions:
# - Skipped when MAINTENANCE_MODE=true (the app intentionally does not serve).
# - Runs only when RUN_DB_MIGRATE=true. Default is false, i.e. historical
#   behavior (start immediately without migrating) is preserved.
# - compose.production.yaml sets RUN_DB_MIGRATE=true on `web` only;
#   `worker` shares the same database, so migrating once from `web`
#   is enough (db:migrate is idempotent, running it twice concurrently
#   is only wasteful). `shredder` never migrates.
run_db_migrate() {
    if [[ "$MAINTENANCE_MODE" == "true" ]]; then
        return 0
    fi
    if [[ "${RUN_DB_MIGRATE:-false}" == "true" ]]; then
        bundle exec rake db:migrate
    fi
}

case "$APP_MODE" in
    web)
        if [[ "$MAINTENANCE_MODE" == "true" ]] ; then
            exec /usr/sbin/nginx -p /opt/app -c config/nginx_maintenance.conf
        else
            rm -f tmp/pids/server.pid

            run_db_migrate

            exec bundle exec passenger \
                 start \
                 -p "${PORT-3000}" \
                 --log-file "/dev/stdout" \
                 --min-instances "${PASSENGER_MIN_INSTANCES-1}" \
                 --max-pool-size "${PASSENGER_MAX_POOL_SIZE-1}"
        fi
        ;;
    worker)
        if [[ "$MAINTENANCE_MODE" == "true" ]] ; then
            # Do nothing
            exec sleep 86400
        else
            run_db_migrate

            exec bundle exec rake jobs:work
        fi
        ;;
    shredder)
        if [[ "$MAINTENANCE_MODE" == "true" || "$ENABLE_SHREDDER" != "true" ]] ; then
            # Do nothing
            exec sleep 86400
        else
            exec bundle exec rake sharetribe:marketplace:run_shredder["${SHREDDER_SLEEP_TIME-1.5},${SHREDDER_QUERY_SLEEP_TIME-0.2}"]
        fi
        ;;
    *)
        echo "Unknown process type. Must be either 'web', 'worker' or 'shredder'!"
        exit 1
        ;;
esac

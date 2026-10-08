# frozen_string_literal: true

# Puma configuration — agent-bank
#
# IMPORTANT: daemonized runs (`rails server -d` / `make server-bg`) chdir to
# "/" by default, which breaks relative-path writers — notably i18n-js, which
# exports translations into "public/..." on each request and crashes with
# Errno::EROFS when the process CWD is not the app root. Pin the working
# directory to the app root (CWD at config-load time = wherever the server
# command was started from, i.e. the repository root).
directory Dir.pwd

threads_count = Integer(ENV.fetch("RAILS_MAX_THREADS", 5))
threads threads_count, threads_count

#!/bin/bash
# Wrapper for @playwright/mcp that forces nodenv to use 24.13.1
export NODENV_VERSION=24.13.1
exec /Users/bookair18/.anyenv/envs/nodenv/versions/24.13.1/bin/npx -y @playwright/mcp@latest "$@"

#!/bin/bash
# Wrapper for @upstash/context7-mcp that forces nodenv to use 24.13.1
export NODENV_VERSION=24.13.1
exec /Users/bookair18/.anyenv/envs/nodenv/versions/24.13.1/bin/npx -y @upstash/context7-mcp@latest "$@"

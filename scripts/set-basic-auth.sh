#!/usr/bin/env bash
# Set the basic auth credentials used for routes with auth = true.
# Prompts for a password and writes TF_VAR_basic_auth_htpasswd to .env,
# replacing any existing value.
#
# Usage: scripts/set-basic-auth.sh [username]   (default: admin)
set -euo pipefail

user="${1:-admin}"
env_file="$(cd "$(dirname "$0")/.." && pwd)/.env"

# APR1 (MD5) hash; Traefik also accepts bcrypt from `htpasswd -nB` if installed.
hash="$(openssl passwd -apr1)"

touch "$env_file"
grep -v '^export TF_VAR_basic_auth_htpasswd=' "$env_file" > "$env_file.tmp" || true
printf "export TF_VAR_basic_auth_htpasswd='%s:%s'\n" "$user" "$hash" >> "$env_file.tmp"
mv "$env_file.tmp" "$env_file"
chmod 600 "$env_file"

echo "Set basic auth for '$user' in $env_file"

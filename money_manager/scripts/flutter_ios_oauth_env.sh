#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="${ROOT_DIR}/ios/Flutter/GoogleAuth.local.xcconfig"

required_vars=(
  GOOGLE_CLIENT_ID
  GOOGLE_SERVER_CLIENT_ID
  GOOGLE_REVERSED_CLIENT_ID
)

missing=()
for name in "${required_vars[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("${name}")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf 'missing required environment variables: %s\n' "${missing[*]}" >&2
  exit 1
fi

cat > "${OUT_FILE}" <<EOF
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_SERVER_CLIENT_ID=${GOOGLE_SERVER_CLIENT_ID}
GOOGLE_REVERSED_CLIENT_ID=${GOOGLE_REVERSED_CLIENT_ID}
EOF

exec flutter run -d "${FLUTTER_DEVICE:-iPhone 17 Pro}" \
  --dart-define=API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:8080}" \
  --dart-define=API_AUTH_MODE="${API_AUTH_MODE:-oauth}" \
  --dart-define=GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID}" \
  --dart-define=GOOGLE_SERVER_CLIENT_ID="${GOOGLE_SERVER_CLIENT_ID}" \
  "$@"

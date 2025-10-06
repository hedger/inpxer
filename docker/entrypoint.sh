#!/bin/sh
set -e

APP_USER="app"
APP_GROUP="app"
APP_UID="10000"
APP_GID="10000"
INDEX_DIR="/data/index"

# Ensure user and group exist (in case image user IDs change)
if ! getent group "$APP_GROUP" >/dev/null 2>&1; then
  addgroup -S -g "$APP_GID" "$APP_GROUP" 2>/dev/null || true
fi
if ! id -u "$APP_USER" >/dev/null 2>&1; then
  adduser -S -D -H -u "$APP_UID" -G "$APP_GROUP" "$APP_USER" 2>/dev/null || true
fi

# Create index directory and ensure write access for app user
mkdir -p "$INDEX_DIR"
# If mounted dir is owned by root (or another user), fix ownership/permissions
# Use chown only if not already owned to minimize cost
CURRENT_OWNER_UID=$(stat -c %u "$INDEX_DIR" 2>/dev/null || stat -f %u "$INDEX_DIR")
CURRENT_OWNER_GID=$(stat -c %g "$INDEX_DIR" 2>/dev/null || stat -f %g "$INDEX_DIR")
if [ "$CURRENT_OWNER_UID" != "$APP_UID" ] || [ "$CURRENT_OWNER_GID" != "$APP_GID" ]; then
  chown -R "$APP_USER":"$APP_GROUP" "$INDEX_DIR" || true
fi
chmod -R u+rwX,g+rwX "$INDEX_DIR" || true

# Drop privileges and exec
if [ "$1" = "serve" ] || [ "$1" = "inpxer" ]; then
  exec su-exec "$APP_USER":"$APP_GROUP" /bin/inpxer "$@"
fi

# If user provided a custom command, run it as app user
exec su-exec "$APP_USER":"$APP_GROUP" "$@"

#!/bin/sh
set -e

APP_USER="app"
APP_GROUP="app"
APP_UID="10000"
APP_GID="10000"
INDEX_DIR="/data/index"

# Expect path to .inpx provided via INPX_FILE env variable
INPX_FILE="${INPX_FILE:-}"
PARTIAL_IMPORT="${PARTIAL_IMPORT:-false}"
KEEP_DELETED="${KEEP_DELETED:-false}"

# Helpers
log() { echo "[entrypoint] $*"; }
warn() { echo "[entrypoint][warn] $*" >&2; }
err() { echo "[entrypoint][error] $*" >&2; }
die() { err "$*"; exit 1; }

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

# Index preparation: if INPX_FILE is set, ensure index exists and matches
needs_index=false
if [ -n "$INPX_FILE" ]; then
  if [ ! -f "$INPX_FILE" ]; then
    die "INPX_FILE is set but not found: $INPX_FILE"
  fi

  # Read version from .inpx (zip) version.info; try unzip -p, fallback to busybox unzip
  INPX_VERSION=$(unzip -p "$INPX_FILE" version.info 2>/dev/null | tr -d '\r' | sed -n '1p' | tr -d '[:space:]' || true)
  if [ -z "$INPX_VERSION" ]; then
    warn "Could not read version.info from $INPX_FILE; proceeding without version check"
  fi

  # Check stored index version marker
  INDEX_VERSION_FILE="$INDEX_DIR/.inpx-version"
  if [ ! -d "$INDEX_DIR/bleve" ] || ( [ ! -d "$INDEX_DIR/badger" ] && [ ! -d "$INDEX_DIR/bolt" ] ); then
    needs_index=true
  elif [ -n "$INPX_VERSION" ]; then
    if [ ! -f "$INDEX_VERSION_FILE" ]; then
      needs_index=true
    else
      CURRENT_INDEX_VERSION=$(cat "$INDEX_VERSION_FILE" 2>/dev/null | tr -d '\r\n[:space:]')
      if [ "$CURRENT_INDEX_VERSION" != "$INPX_VERSION" ]; then
        needs_index=true
      fi
    fi
  fi

  if [ "$needs_index" = true ]; then
    log "Preparing index at $INDEX_DIR from $INPX_FILE (version: ${INPX_VERSION:-unknown})"
    # Run reindex as app user but ensure we own the dir
    chown -R "$APP_USER":"$APP_GROUP" "$INDEX_DIR" || true
    # Import will remove old index by default (unless partial), matching README
    su-exec "$APP_USER":"$APP_GROUP" /bin/inpxer import "$INPX_FILE" \
      $( [ "$KEEP_DELETED" = true ] && echo "--keep-deleted" ) \
      $( [ "$PARTIAL_IMPORT" = true ] && echo "--partial" )
    # Markers (.inpx-version, .inpx-updated) are written by the importer itself
  else
    log "Existing index at $INDEX_DIR is up-to-date (version: ${INPX_VERSION:-unknown})"
  fi
else
  warn "INPX_FILE is not set; assuming index already exists at $INDEX_DIR"
fi

# Drop privileges and exec server
if [ "$1" = "serve" ] || [ "$1" = "inpxer" ] || [ -z "$1" ]; then
  exec su-exec "$APP_USER":"$APP_GROUP" /bin/inpxer serve
fi

# If user provided a custom command, run it as app user
exec su-exec "$APP_USER":"$APP_GROUP" "$@"

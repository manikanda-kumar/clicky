#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: install_app_bundle.sh --app-path /path/to/App.app --install-dir /target/directory [--replace]
USAGE
}

APP_PATH=""
INSTALL_DIR=""
REPLACE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-path)
      APP_PATH="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$APP_PATH" || -z "$INSTALL_DIR" ]]; then
  echo "Missing required arguments." >&2
  usage
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

/bin/mkdir -p "$INSTALL_DIR"

APP_BUNDLE_NAME="$(basename "$APP_PATH")"
INSTALLED_APP_PATH="$INSTALL_DIR/$APP_BUNDLE_NAME"

if [[ -e "$INSTALLED_APP_PATH" ]]; then
  if [[ $REPLACE -eq 1 ]]; then
    /bin/rm -rf "$INSTALLED_APP_PATH"
  else
    echo "App already exists at: $INSTALLED_APP_PATH" >&2
    echo "Pass --replace to overwrite it." >&2
    exit 1
  fi
fi

/usr/bin/ditto "$APP_PATH" "$INSTALLED_APP_PATH"

echo "Installed app: $INSTALLED_APP_PATH"

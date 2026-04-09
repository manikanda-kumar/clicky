#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: resolve_built_app_path.sh --products-dir /path/to/Build/Products/Debug [--preferred-name Name]
USAGE
}

PRODUCTS_DIR=""
PREFERRED_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --products-dir)
      PRODUCTS_DIR="$2"
      shift 2
      ;;
    --preferred-name)
      PREFERRED_NAME="$2"
      shift 2
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

if [[ -z "$PRODUCTS_DIR" ]]; then
  echo "Missing --products-dir" >&2
  usage
  exit 1
fi

if [[ ! -d "$PRODUCTS_DIR" ]]; then
  echo "Products directory not found: $PRODUCTS_DIR" >&2
  exit 1
fi

if [[ -n "$PREFERRED_NAME" && -d "$PRODUCTS_DIR/$PREFERRED_NAME.app" ]]; then
  printf "%s\n" "$PRODUCTS_DIR/$PREFERRED_NAME.app"
  exit 0
fi

while IFS= read -r app_path; do
  app_name="$(basename "$app_path")"
  if [[ "$app_name" == *Runner.app ]]; then
    continue
  fi

  printf "%s\n" "$app_path"
  exit 0
done < <(find "$PRODUCTS_DIR" -maxdepth 1 -type d -name '*.app' | sort)

echo "No app bundle found in: $PRODUCTS_DIR" >&2
exit 1

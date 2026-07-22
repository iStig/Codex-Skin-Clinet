#!/bin/bash

# Dynamically load one pure image as the active theme.
# Hot-applies when CDP is already open (fast).

set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd -P)/common-macos.sh"

IMAGE=""
THEME_NAME=""
FROM_LIBRARY=""
APPLY_NOW="true"
APPEARANCE="auto"
SAFE_AREA="auto"
TASK_MODE="auto"
FOCUS_X=""
FOCUS_Y=""
SOURCE_URL=""
SOURCE_AUTHOR=""
SOURCE_LICENSE=""
SOURCE_PROVIDER="Wikimedia Commons"
SAVE_ONLY="false"
THEME_ID=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --file) IMAGE="${2:-}"; shift 2 ;;
    --from-library) FROM_LIBRARY="${2:-}"; shift 2 ;;
    --name) THEME_NAME="${2:-}"; shift 2 ;;
    --appearance) APPEARANCE="${2:-}"; shift 2 ;;
    --safe-area) SAFE_AREA="${2:-}"; shift 2 ;;
    --task-mode) TASK_MODE="${2:-}"; shift 2 ;;
    --focus-x) FOCUS_X="${2:-}"; shift 2 ;;
    --focus-y) FOCUS_Y="${2:-}"; shift 2 ;;
    --source-url) SOURCE_URL="${2:-}"; shift 2 ;;
    --source-author) SOURCE_AUTHOR="${2:-}"; shift 2 ;;
    --source-license) SOURCE_LICENSE="${2:-}"; shift 2 ;;
    --source-provider) SOURCE_PROVIDER="${2:-}"; shift 2 ;;
    --save-only) SAVE_ONLY="true"; shift ;;
    --theme-id) THEME_ID="${2:-}"; shift 2 ;;
    --no-apply) APPLY_NOW="false"; shift ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

if [ "$SAVE_ONLY" = "true" ]; then
  case "$THEME_ID" in ''|*[!A-Za-z0-9_-]*) fail "Save-only themes require a safe --theme-id." ;; esac
  [ "${#THEME_ID}" -le 80 ] || fail "Theme id is too long."
fi

case "$APPEARANCE" in auto|light|dark) ;; *) fail "Invalid appearance: $APPEARANCE" ;; esac
case "$SAFE_AREA" in auto|left|right|center|none) ;; *) fail "Invalid safe area: $SAFE_AREA" ;; esac
case "$TASK_MODE" in auto|ambient|banner|off) ;; *) fail "Invalid task mode: $TASK_MODE" ;; esac

ensure_state_root
IMAGES_DIR="$STATE_ROOT/images"
THEMES_ROOT="$STATE_ROOT/themes"
/bin/mkdir -p "$IMAGES_DIR" "$THEMES_ROOT" "$THEME_DIR"

if [ -n "$FROM_LIBRARY" ]; then
  [ "$(/usr/bin/basename "$FROM_LIBRARY")" = "$FROM_LIBRARY" ] \
    || fail "Library image must be a filename, not a path."
  case "$FROM_LIBRARY" in
    *$'\n'*|*$'\r'*|*'|'*|*'"'*|*'\'*) fail "Unsafe library image filename." ;;
  esac
  IMAGE="$IMAGES_DIR/$FROM_LIBRARY"
fi

[ -n "$IMAGE" ] || fail "Pass --file <image> or --from-library <name-in-images-dir>"
[ -f "$IMAGE" ] || fail "Image not found: $IMAGE"

case "$IMAGE" in
  *.png|*.PNG|*.jpg|*.JPG|*.jpeg|*.JPEG|*.webp|*.WEBP|*.heic|*.HEIC|*.tif|*.tiff|*.TIF|*.TIFF) ;;
  *) fail "Unsupported image type: $IMAGE" ;;
esac

SOURCE_BYTES="$(/usr/bin/stat -f '%z' "$IMAGE")"
[ "$SOURCE_BYTES" -le 52428800 ] || fail "Image larger than 50 MB."

if [ -z "$THEME_NAME" ]; then
  base="$(/usr/bin/basename "$IMAGE")"
  THEME_NAME="${base%.*}"
fi
[ -n "$THEME_NAME" ] || THEME_NAME="我的主题"

theme_id="img-$(/bin/date '+%Y%m%d%H%M%S')-$$"

progress() {
  printf '%s\n' "$*" >&2
  notify_user "$*"
}

progress "Loading image..."

# Fast Node for write-theme (avoid full codesign when possible)
ensure_node_runtime

image_name="background.jpg"
target_dir="$THEME_DIR"
staging_dir=""
if [ "$SAVE_ONLY" = "true" ]; then
  staging_dir="$THEMES_ROOT/.theme-import.$$.${RANDOM}"
  /bin/mkdir -m 700 "$staging_dir"
  target_dir="$staging_dir"
fi
temporary="$target_dir/.background.$$.tmp.jpg"
prepared="$target_dir/$image_name"
cleanup_temporary() {
  /bin/rm -f "$temporary"
  [ -z "$staging_dir" ] || /bin/rm -rf "$staging_dir"
}
trap cleanup_temporary EXIT

# Prefer copying already-JPEG; sips only when needed (large PNG conversion is the slow part)
ext="$(printf '%s' "$IMAGE" | /usr/bin/tr '[:upper:]' '[:lower:]')"
case "$ext" in
  *.jpg|*.jpeg)
    if [ "$SOURCE_BYTES" -le 16777216 ]; then
      /bin/cp -f "$IMAGE" "$temporary"
    else
      /usr/bin/sips -s format jpeg -s formatOptions 82 -Z 2400 "$IMAGE" --out "$temporary" >/dev/null \
        || fail "Could not normalize large JPEG image."
    fi
    ;;
  *)
    /usr/bin/sips -s format jpeg -s formatOptions 82 -Z 2400 "$IMAGE" --out "$temporary" >/dev/null \
      || fail "Could not convert image. Use PNG/JPEG/HEIC/TIFF/WebP."
    [ -s "$temporary" ] || fail "Converted image is empty."
    ;;
esac
[ -s "$temporary" ] || fail "Prepared image is empty."
PREPARED_BYTES="$(/usr/bin/stat -f '%z' "$temporary")"
[ "$PREPARED_BYTES" -le 16777216 ] || fail "Prepared image larger than 16 MB."
/bin/chmod 600 "$temporary"
/bin/mv -f "$temporary" "$prepared"

theme_args=(
  custom
  --output-dir "$target_dir"
  --image "$image_name"
  --name "$THEME_NAME"
  --tagline "Make something wonderful."
  --quote "MAKE SOMETHING WONDERFUL"
  --appearance "$APPEARANCE"
  --safe-area "$SAFE_AREA"
  --task-mode "$TASK_MODE"
)
[ -n "$FOCUS_X" ] && theme_args+=(--focus-x "$FOCUS_X")
[ -n "$FOCUS_Y" ] && theme_args+=(--focus-y "$FOCUS_Y")
[ -n "$SOURCE_URL" ] && theme_args+=(--source-url "$SOURCE_URL")
[ -n "$SOURCE_URL" ] && theme_args+=(--source-provider "$SOURCE_PROVIDER")
[ -n "$SOURCE_AUTHOR" ] && theme_args+=(--source-author "$SOURCE_AUTHOR")
[ -n "$SOURCE_LICENSE" ] && theme_args+=(--source-license "$SOURCE_LICENSE")
"$NODE" "$SCRIPT_DIR/write-theme.mjs" "${theme_args[@]}" >/dev/null

if [ "$SAVE_ONLY" = "true" ]; then
  final_dir="$THEMES_ROOT/$THEME_ID"
  if [ -e "$final_dir" ]; then
    progress "Already downloaded: ${THEME_NAME}"
    exit 0
  fi
  /bin/mv "$staging_dir" "$final_dir"
  staging_dir=""
  /bin/chmod 600 "$final_dir/"* 2>/dev/null || true
  trap - EXIT
  progress "Downloaded: ${THEME_NAME}"
  exit 0
fi

/usr/bin/find "$THEME_DIR" -maxdepth 1 -type f -name 'background.*' ! -name "$image_name" -delete
trap - EXIT

lib_dir="$THEMES_ROOT/$theme_id"
/bin/mkdir -p "$lib_dir"
/bin/cp -f "$THEME_DIR/$image_name" "$THEME_DIR/theme.json" "$lib_dir/"
/bin/chmod 600 "$lib_dir/"* 2>/dev/null || true

dest_lib_img="$IMAGES_DIR/$(/usr/bin/basename "$IMAGE")"
src_dir="$(cd "$(dirname "$IMAGE")" && pwd -P)"
img_dir="$(cd "$IMAGES_DIR" && pwd -P)"
if [ "$src_dir/$(/usr/bin/basename "$IMAGE")" != "$img_dir/$(/usr/bin/basename "$IMAGE")" ]; then
  /bin/cp -f "$IMAGE" "$dest_lib_img" 2>/dev/null || true
fi

if [ "$APPLY_NOW" != "true" ]; then
  progress "Ready: ${THEME_NAME} (not applied)"
  exit 0
fi

PORT=9341
if [ -f "$STATE_PATH" ]; then
  saved="$(state_field port 2>/dev/null || true)"
  [ -n "${saved:-}" ] && PORT="$saved"
fi

progress "Hot reapply..."
if hot_reapply_theme "$PORT" 8000; then
  progress "Done: ${THEME_NAME}"
  exit 0
fi

progress "CDP not ready, full start..."
if "$SCRIPT_DIR/start-dream-skin-macos.sh" --port "$PORT" --restart-existing; then
  progress "Done: ${THEME_NAME}"
  exit 0
fi

alert_user "Image saved but inject failed. Click Apply Skin."
exit 1

#!/usr/bin/env bash

#
# import-firewall-image.sh
#
# Download + convert a firewall vendor image to QCOW2, and upload it to
# a Scaleway S3-compatible Object Storage bucket.
#
# Usage:
#   ./import-firewall-image.sh \
#     --src-url <URL>             (or --src-path <local file>)
#     --src-format <format>       one of: qcow2|raw|bz2|xz|gz|iso|vmdk
#     --obj-key <key>             object key in the bucket (e.g. opnsense-26.7.qcow2)
#     --bucket <bucket-name>
#     --endpoint <s3-endpoint>
#     --access-key <aws-access-key>
#     --secret-key <aws-secret-key>
#     --region <region>
#     [--force-download]          force re-download even if file exists
#     [--force-upload]            force re-upload even if object exists
#
# Exit codes:
#   0  success
#   1  generic failure
#   2  qemu-img not found
#   3  aws CLI not found
#
set -euo pipefail

force_download=false
force_upload=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src-url)      src_url="$2";       shift 2;;
    --src-path)     src_path="$2";      shift 2;;
    --src-format)   src_format="$2";    shift 2;;
    --obj-key)      obj_key="$2";       shift 2;;
    --bucket)       bucket="$2";        shift 2;;
    --endpoint)     s3_endpoint="$2";   shift 2;;
    --access-key)   access_key="$2";    shift 2;;
    --secret-key)   secret_key="$2";    shift 2;;
    --region)       region="$2";        shift 2;;
    --force-download) force_download=true; shift;;
    --force-upload)   force_upload=true;   shift;;
    -h|--help)
      echo "Usage: $0 --src-url|--src-path <path> --src-format <fmt> --obj-key <key> --bucket <bucket> --endpoint <ep> --access-key <ak> --secret-key <sk> --region <region>"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required tools
# ---------------------------------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI is required but not found." >&2
  exit 3
fi

# qemu-img is only needed for non-qcow2 sources (src_format defaults to raw)
if [[ "${src_format:-raw}" != "qcow2" ]]; then
  if ! command -v qemu-img >/dev/null 2>&1; then
    echo "ERROR: qemu-img is required to convert ${src_format} -> qcow2 but not found." >&2
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# Validate required args
# ---------------------------------------------------------------------------
[[ -z "${src_url:-}" && -z "${src_path:-}" ]] && { echo "ERROR: either --src-url or --src-path is required." >&2; exit 1; }
[[ -z "${obj_key:-}" ]] && { echo "ERROR: --obj-key is required." >&2; exit 1; }
[[ -z "${bucket:-}" ]] && { echo "ERROR: --bucket is required." >&2; exit 1; }
[[ -z "${s3_endpoint:-}" ]] && { echo "ERROR: --endpoint is required." >&2; exit 1; }
[[ -z "${access_key:-}" ]] && { echo "ERROR: --access-key is required." >&2; exit 1; }
[[ -z "${secret_key:-}" ]] && { echo "ERROR: --secret-key is required." >&2; exit 1; }

src_format="${src_format:-raw}"

# ---------------------------------------------------------------------------
# Shared cache dir (downloads only) + per-process workdir (decompress/convert)
# The workdir is PID-unique so concurrent module invocations (e.g. two
# firewall_image modules) never collide on the same qcow2 output path --
# qemu-img takes an exclusive "resize" lock on its output file.
# ---------------------------------------------------------------------------
CACHE_DIR="/tmp/firewall-image"
WORK_DIR="$CACHE_DIR/$$"
mkdir -p "$CACHE_DIR" "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# 1. Resolve and/or download source
# ---------------------------------------------------------------------------
if [[ -n "${src_path:-}" ]]; then
  SRC="$src_path"
elif [[ -n "${src_url:-}" ]]; then
  SRC="$CACHE_DIR/$(basename "${src_url%%\?*}")"
  if $force_download || [[ ! -s "$SRC" ]]; then
    # Download to a unique temp path first, then atomically move into the
    # shared cache so concurrent runs never see a partially-written file.
    echo "Downloading $src_url -> $SRC ..."
    tmp_src="$WORK_DIR/$(basename "${src_url%%\?*}")"
    curl -fL "$src_url" -o "$tmp_src"
    mv -f "$tmp_src" "$SRC"
  else
    echo "Using cached file: $SRC"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Decompress if needed (bz2, xz, gz)
# ---------------------------------------------------------------------------
SRC_RAW="$SRC"
case "$src_format" in
  bz2)
    if [[ "$SRC" == *.bz2 ]]; then
      SRC_RAW="$WORK_DIR/$(basename "${SRC%.bz2}")"
      if [[ ! -s "$SRC_RAW" ]]; then
        echo "Decompressing $SRC -> $SRC_RAW ..."
        bunzip2 -kf "$SRC" -c > "$SRC_RAW"
      fi
    fi
    ;;
  xz)
    if [[ "$SRC" == *.xz ]]; then
      SRC_RAW="$WORK_DIR/$(basename "${SRC%.xz}")"
      if [[ ! -s "$SRC_RAW" ]]; then
        echo "Decompressing $SRC -> $SRC_RAW ..."
        unxz -kf "$SRC" -c > "$SRC_RAW"
      fi
    fi
    ;;
  gz)
    if [[ "$SRC" == *.gz ]]; then
      SRC_RAW="$WORK_DIR/$(basename "${SRC%.gz}")"
      if [[ ! -s "$SRC_RAW" ]]; then
        echo "Decompressing $SRC -> $SRC_RAW ..."
        gunzip -kf "$SRC" -c > "$SRC_RAW"
      fi
    fi
    ;;
esac

# ---------------------------------------------------------------------------
# 3. Convert to QCOW2 if needed
# ---------------------------------------------------------------------------
QCOW="$WORK_DIR/$obj_key"

if [[ "$src_format" == "qcow2" ]]; then
  if [[ "$SRC" != "$QCOW" ]]; then
    echo "Copying $SRC -> $QCOW ..."
    cp "$SRC" "$QCOW"
  fi
else
  echo "Converting $SRC_RAW -> $QCOW ..."
  qemu-img convert -O qcow2 "$SRC_RAW" "$QCOW"
fi

# ---------------------------------------------------------------------------
# 4. Upload to S3 (skip if object already exists unless --force-upload)
# ---------------------------------------------------------------------------
export AWS_ACCESS_KEY_ID="$access_key"
export AWS_SECRET_ACCESS_KEY="$secret_key"
export AWS_ENDPOINT_URL="$s3_endpoint"
export AWS_REGION="$region"
export AWS_DEFAULT_REGION="$region"

if ! $force_upload; then
  if aws s3api head-object --bucket "$bucket" --key "$obj_key" 2>/dev/null; then
    echo "Object s3://$bucket/$obj_key already exists -- skipping upload."
    exit 0
  fi
fi

echo "Uploading $QCOW -> s3://$bucket/$obj_key ..."
aws s3 cp "$QCOW" "s3://$bucket/$obj_key" --only-show-errors
echo "Upload complete: s3://$bucket/$obj_key"
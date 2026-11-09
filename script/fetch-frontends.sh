#!/bin/bash

set -euo pipefail

ROOT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")"
TEMPLATES_FILE="$ROOT_DIR/service/singleton/frontend-templates.yaml"

# 失败重试次数 (CI runner 访问 GitHub release 资源偶发限流/抖动)
MAX_ATTEMPTS="${FETCH_FRONTEND_ATTEMPTS:-3}"

# 下载并校验 zip: 必须是有效 zip 且大于最小字节数
download_zip() {
  local url="$1"
  local out="$2"
  local attempt=1

  while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    echo "Downloading (attempt $attempt/$MAX_ATTEMPTS): $url"
    if curl -fL --retry 2 --retry-delay 3 --connect-timeout 20 --max-time 300 -o "$out" "$url"; then
      local size
      size=$(wc -c <"$out")
      # 有效 zip 至少要有 ZIP 尾记录, 这里用 unzip -t 做实质校验
      if [ "$size" -gt 1024 ] && unzip -tq "$out" >/dev/null 2>&1; then
        echo "OK: $out ($size bytes)"
        return 0
      fi
      echo "WARNING: downloaded file is not a valid zip ($size bytes)" >&2
      head -c 300 "$out" >&2 || true
      echo >&2
    else
      echo "WARNING: curl failed (attempt $attempt)" >&2
    fi

    rm -f "$out"
    attempt=$((attempt + 1))
    [ "$attempt" -le "$MAX_ATTEMPTS" ] && sleep 5
  done

  echo "ERROR: failed to download a valid zip after $MAX_ATTEMPTS attempts: $url" >&2
  return 1
}

download_and_extract() {
  local repository="$1"
  local version="$2"
  local targetDir="$3"
  local TMP_DIR

  TMP_DIR="$(mktemp -d)"

  echo "Downloading from repository: $repository, version: $version"

  pushd "$TMP_DIR" || exit

  download_zip "$repository/releases/download/$version/dist.zip" "dist.zip"

  [ -e "$targetDir" ] && rm -r "$targetDir"
  unzip -q dist.zip
  mv dist "$targetDir"

  rm "dist.zip"
  popd || exit
}

count=$(yq eval '. | length' "$TEMPLATES_FILE")

for i in $(seq 0 $(("$count"-1))); do
  path=$(yq -r ".[$i].path" "$TEMPLATES_FILE")
  repository=$(yq -r ".[$i].repository" "$TEMPLATES_FILE")
  version=$(yq -r ".[$i].version" "$TEMPLATES_FILE")

  if [[ -n $path && -n $repository && -n $version ]]; then
    download_and_extract "$repository" "$version" "$ROOT_DIR/cmd/dashboard/$path"
  fi
done

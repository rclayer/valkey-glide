#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
export GLIDE_VERSION=2.5.3

protoc_version=36.2
system_name="$(uname -s)"
machine="$(uname -m)"
case "$system_name/$machine" in
  Linux/x86_64) protoc_asset="protoc-${protoc_version}-linux-x86_64.zip" ;;
  Linux/aarch64|Linux/arm64) protoc_asset="protoc-${protoc_version}-linux-aarch_64.zip" ;;
  Darwin/arm64|Darwin/aarch64) protoc_asset="protoc-${protoc_version}-osx-aarch_64.zip" ;;
  *) echo "Unsupported build host: ${system_name}/${machine}" >&2; exit 1 ;;
esac

work_dir=/tmp/valkey-glide-cp315
protoc_dir="${work_dir}/local"
mkdir -p "$protoc_dir"
curl --fail --location --silent --show-error \
  "https://github.com/protocolbuffers/protobuf/releases/download/v${protoc_version}/${protoc_asset}" \
  --output /tmp/protoc-cp315.zip
unzip -oq /tmp/protoc-cp315.zip -d "$protoc_dir"
export PATH="${protoc_dir}/bin:${PATH}"
if [[ "$system_name" == "Linux" ]]; then
  ln -sf "${protoc_dir}/bin/protoc" /usr/local/bin/protoc
fi
if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "${protoc_dir}/bin" >> "$GITHUB_PATH"
fi

if [[ -x /opt/python/cp315-cp315/bin/python3.15 ]]; then
  python=/opt/python/cp315-cp315/bin/python3.15
else
  python="$(command -v python3.15)"
fi

venv_dir="${work_dir}/build-venv"
"$python" -m venv "$venv_dir"
# shellcheck disable=SC1091
source "$venv_dir/bin/activate"
python -m pip install --disable-pip-version-check "maturin==1.14.1" mypy-protobuf protobuf

proto_source="$repo_root/glide-core/src/protobuf"
shared_package="$repo_root/python/glide-shared/glide_shared"
protoc \
  "-Iprotobuf=${proto_source}" \
  "--plugin=protoc-gen-mypy=${venv_dir}/bin/protoc-gen-mypy" \
  "--python_out=${shared_package}" \
  "--mypy_out=${shared_package}" \
  "$proto_source"/*.proto

maturin develop --release --locked --manifest-path "$repo_root/python/glide-shared/Cargo.toml"
cargo build --release --locked --manifest-path "$repo_root/ffi/Cargo.toml"

case "$system_name" in
  Linux) ffi_library="$repo_root/ffi/target/release/libglide_ffi.so" ;;
  Darwin) ffi_library="$repo_root/ffi/target/release/libglide_ffi.dylib" ;;
esac
cp "$ffi_library" "$shared_package/"

vendored_shared="$repo_root/python/glide-async/python/glide_shared"
rm -rf "$vendored_shared"
cp -R "$shared_package" "$vendored_shared"

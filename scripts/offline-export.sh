#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -m) == x86_64 ]] || { echo "This bundle is AMD64-only." >&2; exit 1; }
[[ ! -e offline-bundle ]] || { echo "offline-bundle already exists; inspect or move it before exporting again." >&2; exit 1; }
# Element's official v1.12.33 GitHub release metadata publishes this archive digest.
readonly ELEMENT_SHA256_EXPECTED=04e180516430381d5f5e528ea345a435784bba26f76a84f106a623febd3fcd67
if [[ -n ${ELEMENT_SHA256:-} && $ELEMENT_SHA256 != "$ELEMENT_SHA256_EXPECTED" ]]; then
  echo "ELEMENT_SHA256 does not match the trusted v1.12.33 release digest." >&2
  exit 1
fi
ELEMENT_SHA256=$ELEMENT_SHA256_EXPECTED
python3 scripts/render-config.py
bundle_dir=$(mktemp -d .offline-bundle.XXXXXX)
trap 'rm -rf "$bundle_dir"' EXIT
mkdir -p "$bundle_dir/images" "$bundle_dir/static/element"
images=(postgres:17.11-alpine3.24 matrixdotorg/synapse:v1.161.0 nginx:1.30.6-alpine3.24-slim ghcr.io/etkecc/ketesa:v1.5.1-subpath-admin@sha256:315dc260791fb9bccbb1f63ce396c4bd34a47d9ac8027612af93858745d71f95)
case ${INCLUDE_CALLS:-0} in
  0) ;;
  1) images+=(coturn/coturn:4.6.3-r3) ;;
  *) echo "INCLUDE_CALLS must be 0 or 1." >&2; exit 1 ;;
esac
for image in "${images[@]}"; do
  docker pull --platform linux/amd64 "$image"
  [[ $(docker image inspect "$image" --format '{{.Architecture}}') == amd64 ]] || { echo "$image is not AMD64" >&2; exit 1; }
done
docker save -o "$bundle_dir/images/runtime-images.tar" "${images[@]}"
curl --fail --location --proto '=https' --tlsv1.2 -o /tmp/element-web-v1.12.33.tar.gz "https://github.com/element-hq/element-web/releases/download/v1.12.33/element-v1.12.33.tar.gz"
echo "$ELEMENT_SHA256  /tmp/element-web-v1.12.33.tar.gz" | sha256sum -c -
tar -xzf /tmp/element-web-v1.12.33.tar.gz -C "$bundle_dir/static/element" --strip-components=1
cp data/element/config.json "$bundle_dir/static/element/config.json"
cp compose.yaml .env.example "$bundle_dir/"
tar -czf "$bundle_dir/config-templates.tgz" config scripts Makefile README.md README.fa.md .gitignore
docker image inspect "${images[@]}" --format '{{range .RepoDigests}}{{println .}}{{end}}' > "$bundle_dir/image-digests.txt"
(cd "$bundle_dir" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
mv "$bundle_dir" offline-bundle
trap - EXIT
echo "Offline bundle ready. Do not add data/, secrets/, TLS material, or .env. On target: sha256sum -c SHA256SUMS; docker load -i images/runtime-images.tar; copy static/element to data/element."

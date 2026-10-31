#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $(uname -m) == x86_64 ]] || { echo "This bundle is AMD64-only." >&2; exit 1; }
[[ ! -e offline-bundle ]] || { echo "offline-bundle already exists; inspect or move it before exporting again." >&2; exit 1; }
[[ ${ELEMENT_SHA256:-} =~ ^[a-fA-F0-9]{64}$ ]] || { echo "Set ELEMENT_SHA256 to the independently verified SHA-256 for Element Web v1.12.33." >&2; exit 1; }
python3 scripts/render-config.py
mkdir -p offline-bundle/images offline-bundle/static/element
images=(postgres:17.11-alpine3.24 matrixdotorg/synapse:v1.161.0 nginx:1.30.6-alpine3.24-slim)
for image in "${images[@]}"; do
  docker pull --platform linux/amd64 "$image"
  [[ $(docker image inspect "$image" --format '{{.Architecture}}') == amd64 ]] || { echo "$image is not AMD64" >&2; exit 1; }
done
docker save -o offline-bundle/images/runtime-images.tar "${images[@]}"
curl --fail --location --proto '=https' --tlsv1.2 -o /tmp/element-web-v1.12.33.tar.gz "https://github.com/element-hq/element-web/releases/download/v1.12.33/element-v1.12.33.tar.gz"
echo "$ELEMENT_SHA256  /tmp/element-web-v1.12.33.tar.gz" | sha256sum -c -
tar -xzf /tmp/element-web-v1.12.33.tar.gz -C offline-bundle/static/element --strip-components=1
cp data/element/config.json offline-bundle/static/element/config.json
cp compose.yaml .env.example offline-bundle/
tar -czf offline-bundle/config-templates.tgz config scripts README.md .gitignore
docker image inspect "${images[@]}" --format '{{range .RepoDigests}}{{println .}}{{end}}' > offline-bundle/image-digests.txt
(cd offline-bundle && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
echo "Offline bundle ready. Do not add data/, secrets/, TLS material, or .env. On target: sha256sum -c SHA256SUMS; docker load -i images/runtime-images.tar; copy static/element to data/element."

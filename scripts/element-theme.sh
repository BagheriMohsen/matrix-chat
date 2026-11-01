#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

element_dir=${1:-data/element}
[[ -f "$element_dir/index.html" ]] || { echo "Missing Element index: $element_dir/index.html" >&2; exit 1; }

install -d "$element_dir/custom/vazirmatn"
install -m 644 config/element/vazirmatn.css "$element_dir/custom/vazirmatn.css"
install -m 644 config/element/vazirmatn/Vazirmatn-Regular.woff2 "$element_dir/custom/vazirmatn/Vazirmatn-Regular.woff2"
install -m 644 config/element/vazirmatn/Vazirmatn-Medium.woff2 "$element_dir/custom/vazirmatn/Vazirmatn-Medium.woff2"
install -m 644 config/element/vazirmatn/Vazirmatn-Bold.woff2 "$element_dir/custom/vazirmatn/Vazirmatn-Bold.woff2"
install -m 644 config/element/vazirmatn/OFL.txt "$element_dir/custom/vazirmatn/OFL.txt"

python3 - "$element_dir/index.html" <<'PY'
from pathlib import Path
import sys

index = Path(sys.argv[1])
marker = '    <!-- Matrix Chat Vazirmatn override -->\n    <link rel="stylesheet" href="custom/vazirmatn.css">\n'
content = index.read_text()
if marker not in content:
    if "</head>" not in content:
        raise SystemExit("Element index has no closing head tag")
    content = content.replace("</head>", marker + "  </head>", 1)
    index.write_text(content)
PY

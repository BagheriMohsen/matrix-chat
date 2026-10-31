#!/usr/bin/env python3
"""Render deployment-specific configuration from the small .env contract."""

import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / ".env"
DOMAIN = re.compile(r"(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(?:\.(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?))*$")
HOST = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?")
SIZE = re.compile(r"[1-9][0-9]*(?:[KMG])?")
ADMIN_PATH = re.compile(r"/(?:[A-Za-z0-9._~-]+(?:/[A-Za-z0-9._~-]+)*)?")


def fail(message):
    raise SystemExit(f"Configuration error: {message}")


def read_env():
    if not ENV_FILE.is_file():
        fail("copy .env.example to .env first")
    values = {}
    for line_number, raw in enumerate(ENV_FILE.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line or line.startswith("export "):
            fail(f".env line {line_number} must be KEY=VALUE")
        key, value = line.split("=", 1)
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            fail(f"invalid variable name on .env line {line_number}")
        if key in values:
            fail(f"duplicate {key} in .env")
        values[key] = value
    return values


def required(values, key):
    value = values.get(key, "")
    if not value:
        fail(f"{key} is required")
    return value


def validate(values):
    server_name = required(values, "MATRIX_SERVER_NAME")
    if not DOMAIN.fullmatch(server_name):
        fail("MATRIX_SERVER_NAME must be a lowercase DNS name without a port")
    public_url = required(values, "PUBLIC_BASE_URL")
    parsed = urlparse(public_url)
    if parsed.scheme != "https" or parsed.netloc != server_name or parsed.path not in ("", "/") or parsed.params or parsed.query or parsed.fragment:
        fail("PUBLIC_BASE_URL must be https://MATRIX_SERVER_NAME with no path, port, query, or fragment")
    for key in ("POSTGRES_DB", "POSTGRES_USER"):
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,62}", required(values, key)):
            fail(f"{key} must be a PostgreSQL identifier")
    password = required(values, "POSTGRES_PASSWORD")
    if password == "replace-with-a-long-random-password" or any(c in password for c in "\n\r"):
        fail("POSTGRES_PASSWORD must be replaced and contain no newline")
    for key in ("MAX_UPLOAD_SIZE", "MEDIA_UPLOAD_LIMIT_24H", "MEDIA_UPLOAD_LIMIT_7D"):
        if not SIZE.fullmatch(required(values, key)):
            fail(f"{key} must be a positive Synapse size, such as 20M")
    host = required(values, "LOCAL_HOST")
    if not HOST.fullmatch(host):
        fail("LOCAL_HOST must be a hostname or IPv4 address")
    for key in ("LOCAL_ELEMENT_PORT", "LOCAL_ADMIN_PORT"):
        try:
            port = int(required(values, key))
        except ValueError:
            fail(f"{key} must be a port number")
        if not 1024 <= port <= 65535:
            fail(f"{key} must be between 1024 and 65535")
    path = required(values, "ADMIN_PATH")
    if not ADMIN_PATH.fullmatch(path):
        fail("ADMIN_PATH must be / or an absolute path without a trailing slash")
    return server_name, public_url.rstrip("/"), host, path


def nginx_size(size):
    return size.lower()


def write_template(source, destination, replacements):
    text = (ROOT / source).read_text()
    for key, value in replacements.items():
        text = text.replace(f"__{key}__", value)
    if re.search(r"__[A-Z0-9_]+__", text):
        fail(f"unrendered placeholder in {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text)


def main():
    values = read_env()
    server_name, public_url, host, admin_path = validate(values)
    arguments = sys.argv[1:]
    if arguments:
        if len(arguments) == 2 and arguments[0] == "--get" and arguments[1] in values:
            print(values[arguments[1]])
            return
        if arguments != ["--homeserver"]:
            raise SystemExit("Usage: render-config.py [--homeserver] | --get VARIABLE")
    local_element_url = f"http://{host}:{values['LOCAL_ELEMENT_PORT']}"
    local_admin_url = f"http://{host}:{values['LOCAL_ADMIN_PORT']}"
    if admin_path == "/":
        admin_location = "  location / { proxy_pass http://synapse-admin:80; }"
    else:
        admin_location = (
            f"  location = {admin_path} {{ return 301 {admin_path}/; }}\n"
            f"  location ^~ {admin_path}/ {{\n"
            f"    rewrite ^{admin_path}/(.*)$ /$1 break;\n"
            "    proxy_pass http://synapse-admin:80;\n"
            "    proxy_set_header Host $host;\n"
            "    proxy_set_header X-Real-IP $remote_addr;\n"
            "    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n"
            "    proxy_set_header X-Forwarded-Proto $scheme;\n"
            "  }"
        )
    common = {
        "MATRIX_SERVER_NAME": server_name,
        "PUBLIC_BASE_URL": public_url,
        "LOCAL_HOST": host,
        "LOCAL_ELEMENT_URL": local_element_url,
        "LOCAL_ADMIN_URL": local_admin_url,
        "MAX_UPLOAD_SIZE_NGINX": nginx_size(values["MAX_UPLOAD_SIZE"]),
        "ADMIN_UI_LOCATION": admin_location,
    }
    write_template("config/nginx/site.conf", ROOT / "data/nginx/site.conf", common)
    write_template("config/nginx/site.local.conf", ROOT / "data/nginx/site.local.conf", common)
    write_template("config/element/config.json", ROOT / "data/element/config.json", common)
    write_template("config/element/config.local.json", ROOT / "data/element/config.local.json", common)
    write_template("config/admin/config.local.json", ROOT / "data/admin/config.json", common)

    if arguments == ["--homeserver"]:
        synapse = dict(common)
        synapse.update({
            "MATRIX_SERVER_NAME_JSON": json.dumps(server_name),
            "PUBLIC_BASE_URL_SLASH_JSON": json.dumps(public_url + "/"),
            "POSTGRES_DB": json.dumps(values["POSTGRES_DB"]),
            "POSTGRES_USER": json.dumps(values["POSTGRES_USER"]),
            "POSTGRES_PASSWORD": json.dumps(values["POSTGRES_PASSWORD"]),
            "MAX_UPLOAD_SIZE": values["MAX_UPLOAD_SIZE"],
            "MEDIA_UPLOAD_LIMIT_24H": values["MEDIA_UPLOAD_LIMIT_24H"],
            "MEDIA_UPLOAD_LIMIT_7D": values["MEDIA_UPLOAD_LIMIT_7D"],
            "SIGNING_KEY_PATH_JSON": json.dumps(f"/data/{server_name}.signing.key"),
            "LOG_CONFIG_PATH_JSON": json.dumps(f"/data/{server_name}.log.config"),
        })
        write_template("config/synapse/homeserver.yaml.template", ROOT / "data/synapse/homeserver.yaml", synapse)


if __name__ == "__main__":
    main()

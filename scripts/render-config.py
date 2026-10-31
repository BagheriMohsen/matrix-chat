#!/usr/bin/env python3
"""Render deployment-specific configuration from the small .env contract."""

import json
import ipaddress
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
    local_ports = {}
    for key in ("LOCAL_ELEMENT_PORT", "LOCAL_ADMIN_PORT"):
        try:
            local_ports[key] = int(required(values, key))
        except ValueError:
            fail(f"{key} must be a port number")
        if not 1024 <= local_ports[key] <= 65535:
            fail(f"{key} must be between 1024 and 65535")
    if local_ports["LOCAL_ELEMENT_PORT"] == local_ports["LOCAL_ADMIN_PORT"]:
        fail("LOCAL_ELEMENT_PORT and LOCAL_ADMIN_PORT must differ")
    path = required(values, "ADMIN_PATH")
    if not ADMIN_PATH.fullmatch(path):
        fail("ADMIN_PATH must be / or an absolute path without a trailing slash")
    turn_enabled = values.get("TURN_ENABLED", "0")
    if turn_enabled not in {"0", "1"}:
        fail("TURN_ENABLED must be 0 or 1")
    turn = {"enabled": turn_enabled == "1"}
    if turn["enabled"]:
        turn_host = required(values, "TURN_HOST")
        if not DOMAIN.fullmatch(turn_host) or turn_host != server_name:
            fail("TURN_HOST must equal MATRIX_SERVER_NAME so the existing TLS certificate is valid")
        try:
            external_ip = ipaddress.ip_address(required(values, "TURN_EXTERNAL_IP"))
        except ValueError:
            fail("TURN_EXTERNAL_IP must be a public IPv4 address")
        if external_ip.version != 4 or not external_ip.is_global:
            fail("TURN_EXTERNAL_IP must be a public IPv4 address")
        ports = {}
        for key in ("TURN_PORT", "TURN_TLS_PORT", "TURN_MIN_PORT", "TURN_MAX_PORT"):
            try:
                ports[key] = int(required(values, key))
            except ValueError:
                fail(f"{key} must be a port number")
            if not 1024 <= ports[key] <= 65535:
                fail(f"{key} must be between 1024 and 65535")
        if ports["TURN_PORT"] == ports["TURN_TLS_PORT"]:
            fail("TURN_PORT and TURN_TLS_PORT must differ")
        if ports["TURN_MIN_PORT"] > ports["TURN_MAX_PORT"]:
            fail("TURN_MIN_PORT must not exceed TURN_MAX_PORT")
        if ports["TURN_MIN_PORT"] <= ports["TURN_PORT"] <= ports["TURN_MAX_PORT"] or ports["TURN_MIN_PORT"] <= ports["TURN_TLS_PORT"] <= ports["TURN_MAX_PORT"]:
            fail("TURN relay range must not contain TURN_PORT or TURN_TLS_PORT")
        secret = required(values, "TURN_SHARED_SECRET")
        if not re.fullmatch(r"[A-Za-z0-9._~+/=-]{32,}", secret):
            fail("TURN_SHARED_SECRET must be at least 32 safe characters")
        turn.update({"host": turn_host, "external_ip": str(external_ip), "secret": secret, **ports})
    return server_name, public_url.rstrip("/"), host, path, turn


def turn_synapse_config(turn):
    if not turn["enabled"]:
        return ""
    host = turn["host"]
    return (
        "# BEGIN managed TURN configuration\n"
        "turn_uris:\n"
        f"  - turn:{host}:{turn['TURN_PORT']}?transport=udp\n"
        f"  - turn:{host}:{turn['TURN_PORT']}?transport=tcp\n"
        f"  - turns:{host}:{turn['TURN_TLS_PORT']}?transport=tcp\n"
        f"turn_shared_secret: {json.dumps(turn['secret'])}\n"
        "turn_user_lifetime: 1h\n"
        "turn_allow_guests: false\n"
        "# END managed TURN configuration\n"
    )


def nginx_size(size):
    return size.lower()


def retention_config():
    return """# BEGIN managed retention configuration
# Rooms without m.room.retention retain messages indefinitely.
retention:
  enabled: true
  allowed_lifetime_min: 1d
  allowed_lifetime_max: 90d
# END managed retention configuration

"""


def room_permissions_config():
    return """# BEGIN managed room permissions configuration
# Matrix room power levels, rather than server-admin status, authorize invites.
block_non_admin_invites: false
# END managed room permissions configuration

"""


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
    server_name, public_url, host, admin_path, turn = validate(values)
    arguments = sys.argv[1:]
    if arguments:
        if len(arguments) == 2 and arguments[0] == "--get" and arguments[1] in values:
            print(values[arguments[1]])
            return
        if arguments not in (["--homeserver"], ["--turn-synapse"]):
            raise SystemExit("Usage: render-config.py [--homeserver|--turn-synapse] | --get VARIABLE")
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
        "VOIP_UI_ENABLED": "true" if turn["enabled"] else "false",
    }
    write_template("config/nginx/site.conf", ROOT / "data/nginx/site.conf", common)
    write_template("config/nginx/site.local.conf", ROOT / "data/nginx/site.local.conf", common)
    write_template("config/element/config.json", ROOT / "data/element/config.json", common)
    write_template("config/element/config.local.json", ROOT / "data/element/config.local.json", common)
    write_template("config/admin/config.local.json", ROOT / "data/admin/config.json", common)
    if turn["enabled"]:
        turn_destination = ROOT / "data/coturn/turnserver.conf"
        write_template("config/coturn/turnserver.conf.template", turn_destination, {
            "TURN_HOST": turn["host"],
            "TURN_PORT": str(turn["TURN_PORT"]),
            "TURN_TLS_PORT": str(turn["TURN_TLS_PORT"]),
            "TURN_EXTERNAL_IP": turn["external_ip"],
            "TURN_MIN_PORT": str(turn["TURN_MIN_PORT"]),
            "TURN_MAX_PORT": str(turn["TURN_MAX_PORT"]),
            "TURN_SHARED_SECRET": turn["secret"],
        })
        turn_destination.parent.chmod(0o700)
        turn_destination.chmod(0o600)

    if arguments == ["--turn-synapse"]:
        homeserver = ROOT / "data/synapse/homeserver.yaml"
        if not homeserver.is_file():
            fail("initialize Synapse before updating TURN configuration")
        content = homeserver.read_text()
        for name in ("retention", "room permissions", "TURN"):
            content = re.sub(
                rf"(?ms)^# BEGIN managed {name} configuration\n.*?^# END managed {name} configuration\n?",
                "",
                content,
            )
        content = re.sub(r"(?m)^block_non_admin_invites: (?:true|false)\n?", "", content)
        anchor = re.search(r"(?m)^signing_key_path:", content)
        if not anchor:
            fail("could not find signing_key_path in homeserver.yaml")
        content = content[:anchor.start()] + retention_config() + room_permissions_config() + turn_synapse_config(turn) + content[anchor.start():]
        homeserver.write_text(content)
        homeserver.chmod(0o600)
        return

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
            "RETENTION_CONFIG": retention_config(),
            "ROOM_PERMISSIONS_CONFIG": room_permissions_config(),
            "SIGNING_KEY_PATH_JSON": json.dumps(f"/data/{server_name}.signing.key"),
            "LOG_CONFIG_PATH_JSON": json.dumps(f"/data/{server_name}.log.config"),
            "TURN_CONFIG": turn_synapse_config(turn),
        })
        write_template("config/synapse/homeserver.yaml.template", ROOT / "data/synapse/homeserver.yaml", synapse)


if __name__ == "__main__":
    main()

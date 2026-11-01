#!/usr/bin/env python3
"""Small, authenticated Matrix administration metrics dashboard."""

import html
import json
import os
import secrets
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


SYNAPSE_URL = os.environ.get("SYNAPSE_URL", "http://synapse:8008").rstrip("/")
SESSION_TTL = int(os.environ.get("ANALYTICS_SESSION_TTL", "3600"))
DATA_DIR = Path(os.environ.get("ANALYTICS_DATA_DIR", "/var/lib/analytics"))
SESSIONS = {}
SESSIONS_LOCK = threading.Lock()
SAMPLE_LOCK = threading.Lock()
LAST_CGROUP_USAGE = {}
LAST_HOST_CPU = None
LAST_SUMMARY = None
LAST_COLLECT_AT = 0


def request_json(path, token=None, body=None, timeout=8):
    payload = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(SYNAPSE_URL + path, data=payload)
    request.add_header("Accept", "application/json")
    if payload is not None:
        request.add_header("Content-Type", "application/json")
    if token:
        request.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def database():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DATA_DIR / "metrics.sqlite3")
    connection.execute("""CREATE TABLE IF NOT EXISTS snapshots (
        collected_at INTEGER PRIMARY KEY, users INTEGER NOT NULL, rooms INTEGER NOT NULL,
        active_5m INTEGER NOT NULL, active_1h INTEGER NOT NULL,
        active_24h INTEGER NOT NULL, active_7d INTEGER NOT NULL,
        media_files INTEGER, media_bytes INTEGER
    )""")
    return connection


def read_text(path):
    return Path(path).read_text()


def host_metrics():
    global LAST_HOST_CPU
    now = time.time()
    cpu_fields = [int(value) for value in read_text("/host/proc/stat").splitlines()[0].split()[1:]]
    total, idle = sum(cpu_fields), cpu_fields[3] + (cpu_fields[4] if len(cpu_fields) > 4 else 0)
    cpu_percent = None
    if LAST_HOST_CPU:
        previous_total, previous_idle, previous_at = LAST_HOST_CPU
        if total > previous_total and now > previous_at:
            cpu_percent = round(100 * (1 - (idle - previous_idle) / (total - previous_total)), 1)
    LAST_HOST_CPU = (total, idle, now)
    memory = {}
    for line in read_text("/host/proc/meminfo").splitlines():
        key, value = line.split(":", 1)
        memory[key] = int(value.strip().split()[0]) * 1024
    disk = os.statvfs("/host-root")
    return {
        "cpu_percent": cpu_percent,
        "ram_total": memory.get("MemTotal", 0),
        "ram_used": memory.get("MemTotal", 0) - memory.get("MemAvailable", 0),
        "disk_total": disk.f_blocks * disk.f_frsize,
        "disk_used": (disk.f_blocks - disk.f_bfree) * disk.f_frsize,
        "uptime_seconds": int(float(read_text("/host/proc/uptime").split()[0])),
    }


def container_metrics():
    """Read cgroup v2 resource files; Docker names are deliberately not requested."""
    now = time.time()
    result = []
    root = Path("/host/sys/fs/cgroup")
    for directory in root.rglob("docker-*.scope"):
        try:
            identifier = directory.name.removeprefix("docker-").removesuffix(".scope")
            usage = int((directory / "cpu.stat").read_text().split("usage_usec ", 1)[1].splitlines()[0])
            memory = int((directory / "memory.current").read_text())
        except (FileNotFoundError, IndexError, ValueError):
            continue
        previous = LAST_CGROUP_USAGE.get(identifier)
        cpu_percent = None
        if previous and now > previous[1]:
            cpu_percent = round((usage - previous[0]) / ((now - previous[1]) * 10000), 1)
        LAST_CGROUP_USAGE[identifier] = (usage, now)
        result.append({"id": identifier[:12], "cpu_percent": cpu_percent, "ram_bytes": memory})
    return sorted(result, key=lambda item: item["ram_bytes"], reverse=True)


def paged(path, token, key):
    items, marker = [], None
    for _ in range(100):
        separator = "&" if "?" in path else "?"
        page = request_json(path + (f"{separator}from={urllib.parse.quote(marker)}" if marker else ""), token)
        items.extend(page.get(key, []))
        marker = page.get("next_token")
        if not marker:
            return items
    raise RuntimeError("Synapse pagination exceeded 100 pages")


def collect(token):
    global LAST_SUMMARY, LAST_COLLECT_AT
    with SAMPLE_LOCK:
        if LAST_SUMMARY is not None and time.time() - LAST_COLLECT_AT < 300:
            return LAST_SUMMARY
    now_ms = int(time.time() * 1000)
    users = paged("/_synapse/admin/v2/users?limit=100", token, "users")
    rooms = paged("/_synapse/admin/v1/rooms?limit=100", token, "rooms")
    activity = {"5m": 0, "1h": 0, "24h": 0, "7d": 0}
    summaries = []
    for user in users:
        seen = user.get("last_seen_ts")
        if isinstance(seen, int):
            age = now_ms - seen
            for label, limit in (("5m", 300000), ("1h", 3600000), ("24h", 86400000), ("7d", 604800000)):
                if age <= limit:
                    activity[label] += 1
            summaries.append({"user_id": user.get("name", ""), "last_seen_ts": seen, "deactivated": bool(user.get("deactivated"))})
    media_files = media_bytes = None
    try:
        media = paged("/_synapse/admin/v1/statistics/users/media?limit=100", token, "users")
        media_files = sum(int(item.get("media_count", 0)) for item in media)
        media_bytes = sum(int(item.get("media_length", 0)) for item in media)
    except (urllib.error.HTTPError, urllib.error.URLError, RuntimeError, ValueError):
        pass
    summary = {"users": len(users), "rooms": len(rooms), "activity": activity,
               "media_files": media_files, "media_bytes": media_bytes,
               "user_activity": sorted(summaries, key=lambda item: item["last_seen_ts"], reverse=True)[:100]}
    with SAMPLE_LOCK:
        connection = database()
        connection.execute("INSERT OR REPLACE INTO snapshots VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                           (int(time.time()), summary["users"], summary["rooms"], activity["5m"], activity["1h"],
                            activity["24h"], activity["7d"], media_files, media_bytes))
        connection.commit()
        history = connection.execute("SELECT * FROM snapshots WHERE collected_at > ? ORDER BY collected_at", (int(time.time()) - 30 * 86400,)).fetchall()
        connection.close()
        summary["history"] = [{"at": row[0], "users": row[1], "rooms": row[2], "active_24h": row[5], "media_bytes": row[8]} for row in history]
        LAST_SUMMARY, LAST_COLLECT_AT = summary, time.time()
    return summary


def session(handler):
    cookie = SimpleCookie(handler.headers.get("Cookie"))
    sid = cookie.get("analytics_session")
    if not sid:
        return None
    with SESSIONS_LOCK:
        value = SESSIONS.get(sid.value)
        if not value or value["expires"] < time.time():
            SESSIONS.pop(sid.value, None)
            return None
        return value


def page(title, body):
    return "<!doctype html><html><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>" + html.escape(title) + "</title><style>body{font:16px system-ui;max-width:1100px;margin:2rem auto;padding:0 1rem;background:#101418;color:#e9eef5}a{color:#8cc8ff}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:1rem}.card{background:#19212a;padding:1rem;border-radius:10px}table{width:100%;border-collapse:collapse}td,th{padding:.45rem;border-bottom:1px solid #334}button,input{padding:.6rem;margin:.3rem}canvas{width:100%;height:200px;background:#19212a;border-radius:10px}</style></head><body>" + body + "</body></html>"


class Handler(BaseHTTPRequestHandler):
    def session_cookie(self, value):
        secure = "; Secure" if self.headers.get("X-Forwarded-Proto") == "https" else ""
        return value + "; Path=/analytics; HttpOnly; SameSite=Strict" + secure

    def send_html(self, status, content):
        encoded = content.encode()
        self.send_response(status); self.send_header("Content-Type", "text/html; charset=utf-8"); self.send_header("Content-Length", str(len(encoded))); self.end_headers(); self.wfile.write(encoded)

    def do_GET(self):
        if self.path == "/health":
            self.send_response(204); self.end_headers(); return
        if self.path == "/analytics/" or self.path == "/analytics":
            if not session(self):
                self.send_html(HTTPStatus.UNAUTHORIZED, page("Analytics login", "<h1>Matrix Analytics</h1><form method=post action='/analytics/login'><input name=username placeholder='Admin username' required><input name=password type=password placeholder='Password' required><button>Sign in</button></form>")); return
            self.send_html(200, page("Matrix Analytics", "<h1>Matrix Analytics</h1><p>Live server-admin metrics. Last-seen is recent activity, not presence. <a href='/analytics/logout'>Sign out</a></p><div id=cards class=grid></div><h2>History (actual samples)</h2><canvas id=chart width=1000 height=200></canvas><h2>Containers</h2><div id=containers></div><h2>Recent account activity</h2><table id=users><tr><th>User</th><th>Last seen</th><th>State</th></tr></table><script>const b=n=>n==null?'Unavailable':n>1e9?(n/1e9).toFixed(2)+' GB':n>1e6?(n/1e6).toFixed(1)+' MB':n+' B';fetch('/analytics/api/summary').then(r=>r.ok?r.json():Promise.reject()).then(d=>{let c=[['Users',d.users],['Rooms',d.rooms],['Active 5m',d.activity['5m']],['Active 1h',d.activity['1h']],['Active 24h',d.activity['24h']],['Active 7d',d.activity['7d']],['Media',d.media_files==null?'Unavailable':d.media_files+' files'],['Host RAM',b(d.host.ram_used)+' / '+b(d.host.ram_total)],['Host disk',b(d.host.disk_used)+' / '+b(d.host.disk_total)],['Uptime',Math.floor(d.host.uptime_seconds/3600)+'h']];cards.innerHTML=c.map(x=>'<div class=card><b>'+x[0]+'</b><br>'+x[1]+'</div>').join('');containers.innerHTML='<table><tr><th>Container ID</th><th>CPU</th><th>RAM</th></tr>'+d.containers.map(x=>'<tr><td>'+x.id+'</td><td>'+(x.cpu_percent==null?'Sampling…':x.cpu_percent+'%')+'</td><td>'+b(x.ram_bytes)+'</td></tr>').join('')+'</table>';users.innerHTML+ d.user_activity.map(x=>'<tr><td>'+x.user_id+'</td><td>'+new Date(x.last_seen_ts).toLocaleString()+'</td><td>'+(x.deactivated?'Deactivated':'Active account')+'</td></tr>').join('');let p=d.history,ctx=chart.getContext('2d');if(p.length>1){let m=Math.max(...p.map(x=>x.active_24h),1);ctx.strokeStyle='#8cc8ff';ctx.beginPath();p.forEach((x,i)=>{let X=i*1000/(p.length-1),Y=190-x.active_24h/m*170;i?ctx.lineTo(X,Y):ctx.moveTo(X,Y)});ctx.stroke()}}).catch(()=>document.body.insertAdjacentHTML('beforeend','<p>Unable to load live metrics.</p>'))</script>")); return
        if self.path == "/analytics/api/summary":
            value = session(self)
            if not value:
                self.send_response(401); self.end_headers(); return
            try:
                data = collect(value["token"]); data["host"] = host_metrics(); data["containers"] = container_metrics()
                encoded = json.dumps(data).encode(); self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(encoded))); self.end_headers(); self.wfile.write(encoded)
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, RuntimeError, OSError, sqlite3.Error) as error:
                encoded = json.dumps({"error": "metrics unavailable", "detail": str(error)}).encode(); self.send_response(502); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(encoded))); self.end_headers(); self.wfile.write(encoded)
            return
        if self.path == "/analytics/logout":
            cookie = SimpleCookie(self.headers.get("Cookie")); sid = cookie.get("analytics_session")
            if sid:
                with SESSIONS_LOCK: SESSIONS.pop(sid.value, None)
            self.send_response(303); self.send_header("Set-Cookie", self.session_cookie("analytics_session=; Max-Age=0")); self.send_header("Location", "/analytics/"); self.end_headers(); return
        self.send_response(404); self.end_headers()

    def do_POST(self):
        if self.path != "/analytics/login": self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length", "0"))
        form = urllib.parse.parse_qs(self.rfile.read(min(length, 8192)).decode())
        username, password = form.get("username", [""])[0], form.get("password", [""])[0]
        try:
            login = request_json("/_matrix/client/v3/login", body={"type":"m.login.password","identifier":{"type":"m.id.user","user":username},"password":password})
            token = login["access_token"]
            request_json("/_synapse/admin/v2/users?limit=1", token)
        except (urllib.error.HTTPError, urllib.error.URLError, KeyError):
            self.send_html(HTTPStatus.FORBIDDEN, page("Access denied", "<p>Administrator authentication failed.</p><p><a href='/analytics/'>Try again</a></p>")); return
        sid = secrets.token_urlsafe(32)
        with SESSIONS_LOCK: SESSIONS[sid] = {"token": token, "expires": time.time() + SESSION_TTL}
        self.send_response(303); self.send_header("Set-Cookie", self.session_cookie(f"analytics_session={sid}; Max-Age={SESSION_TTL}")); self.send_header("Location", "/analytics/"); self.end_headers()

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer((os.environ.get("ANALYTICS_BIND", "0.0.0.0"), int(os.environ.get("ANALYTICS_PORT", "8080"))), Handler).serve_forever()

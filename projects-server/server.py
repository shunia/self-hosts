#!/usr/bin/env python3
import io
import json
import mimetypes
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlencode, urlparse

import segno


HOST = os.environ.get("PROJECTS_BIND_HOST", "0.0.0.0")
PORT = int(os.environ.get("PROJECTS_PORT", "8080"))
XRAY_DOMAIN = os.environ["XRAY_DOMAIN"]

PROJECTS_ROOT = Path("/srv/projects").resolve()
XRAY_ROOT = Path("/srv/xray").resolve()
XRAY_HTML = (XRAY_ROOT / "xray_qrcode.html").resolve()
XRAY_CONFIG = (XRAY_ROOT / "config.json").resolve()

CLIENT_PROFILES = [
    {
        "id": "generic",
        "name": "Generic Xray Client",
        "notes": "Most Xray-compatible clients can import this URI directly.",
        "fragment_template": "{domain} xhttp h2",
    },
    {
        "id": "v2rayng",
        "name": "v2rayNG (Android)",
        "notes": "Recommended on Android. Uses the same import URI as the generic profile.",
        "fragment_template": "v2rayNG {domain}",
    },
    {
        "id": "streisand",
        "name": "Streisand (iOS)",
        "notes": "iOS option. XHTTP support depends on the client version.",
        "fragment_template": "Streisand {domain}",
    },
    {
        "id": "happ",
        "name": "Happ (iOS)",
        "notes": "Alternative iOS option. Uses the same import URI as the generic profile.",
        "fragment_template": "Happ {domain}",
    },
]


def guess_type(path: Path) -> str:
    mime_type, _ = mimetypes.guess_type(str(path))
    return mime_type or "application/octet-stream"


def safe_static_path(request_path: str) -> Path | None:
    relative = request_path.lstrip("/") or "index.html"
    candidate = (PROJECTS_ROOT / relative).resolve()
    try:
        candidate.relative_to(PROJECTS_ROOT)
    except ValueError:
        return None
    if candidate.is_dir():
        candidate = candidate / "index.html"
    return candidate if candidate.is_file() else None


def load_xray_share() -> dict:
    with XRAY_CONFIG.open("r", encoding="utf-8") as handle:
        config = json.load(handle)

    inbound = next(
        inbound for inbound in config["inbounds"] if inbound.get("protocol") == "vless"
    )
    client = inbound["settings"]["clients"][0]
    stream_settings = inbound.get("streamSettings", {})
    network = stream_settings.get("network", "xhttp")
    if network == "xhttp":
        path = stream_settings.get("xhttpSettings", {}).get("path", "/")
    elif network == "ws":
        path = stream_settings.get("wsSettings", {}).get("path", "/")
    else:
        path = "/"

    return {
        "domain": XRAY_DOMAIN,
        "port": 443,
        "uuid": client["id"],
        "transport": network,
        "security": "tls",
        "sni": XRAY_DOMAIN,
        "alpn": "h2",
        "path": path,
        "mode": "auto",
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def build_uri(share: dict, profile: dict) -> str:
    params = [
        ("encryption", "none"),
        ("security", share["security"]),
        ("sni", share["sni"]),
        ("alpn", share["alpn"]),
        ("type", share["transport"]),
        ("path", share["path"]),
        ("mode", share["mode"]),
    ]
    query = urlencode(params, safe="/")
    fragment = quote(profile["fragment"])
    return (
        f"vless://{share['uuid']}@{share['domain']}:{share['port']}?"
        f"{query}#{fragment}"
    )


def build_payload() -> dict:
    share = load_xray_share()
    profiles = []
    for profile in CLIENT_PROFILES:
        item = dict(profile)
        item["fragment"] = item["fragment_template"].format(domain=share["domain"])
        item["uri"] = build_uri(share, item)
        profiles.append(item)
    return {
        "share": share,
        "profiles": profiles,
    }


def render_qr_svg(uri: str) -> str:
    code = segno.make(uri, error="m")
    buffer = io.BytesIO()
    code.save(
        buffer,
        kind="svg",
        scale=7,
        border=2,
        dark="#172033",
        light="#ffffff",
    )
    return buffer.getvalue().decode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "ProjectsHTTP/1.0"

    def do_GET(self) -> None:
        self.dispatch(send_body=True)

    def do_HEAD(self) -> None:
        self.dispatch(send_body=False)

    def dispatch(self, send_body: bool) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/__meta/xray-share.json":
            self.serve_json(build_payload(), send_body=send_body)
            return

        if parsed.path == "/__meta/xray-link.txt":
            self.serve_link(parsed.query, send_body=send_body)
            return

        if parsed.path == "/__meta/xray-qr.svg":
            self.serve_qr(parsed.query, send_body=send_body)
            return

        if parsed.path == "/xray_qrcode.html":
            self.serve_file(XRAY_HTML, cache=False, send_body=send_body)
            return

        path = safe_static_path(parsed.path)
        if path is None:
            self.send_error(404)
            return
        self.serve_file(path, cache=path.suffix not in {".html"}, send_body=send_body)

    def serve_json(self, payload: dict, send_body: bool) -> None:
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def serve_link(self, query: str, send_body: bool) -> None:
        payload = build_payload()
        profile = self.pick_profile(payload["profiles"], parse_qs(query).get("client", ["generic"])[0])
        body = profile["uri"].encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def serve_qr(self, query: str, send_body: bool) -> None:
        payload = build_payload()
        profile = self.pick_profile(payload["profiles"], parse_qs(query).get("client", ["generic"])[0])
        body = render_qr_svg(profile["uri"]).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "image/svg+xml; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    def serve_file(self, path: Path, cache: bool, send_body: bool) -> None:
        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", guess_type(path))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=3600" if cache else "no-store")
        self.end_headers()
        if send_body:
            self.wfile.write(body)

    @staticmethod
    def pick_profile(profiles: list[dict], client_id: str) -> dict:
        for profile in profiles:
            if profile["id"] == client_id:
                return profile
        return profiles[0]

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()

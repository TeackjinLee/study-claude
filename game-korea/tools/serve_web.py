#!/usr/bin/env python3
"""웹 빌드 로컬 확인: python3 tools/serve_web.py (종료: Ctrl+C)."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8060)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / "output" / "web"
    if not (root / "index.html").is_file():
        parser.error("웹 빌드가 없습니다. 먼저 Web 프리셋으로 내보내세요.")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), partial(Handler, directory=str(root)))
    print(f"http://localhost:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()

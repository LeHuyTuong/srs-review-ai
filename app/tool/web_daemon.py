# Double-forked static server for the Flutter web release build.
#
# A plain background job dies together with the DSH tool-call session; the
# double fork (fork -> setsid -> fork) detaches the grandchild so the server
# outlives it. PID lands in /tmp/srs_web_server.pid, output in
# /tmp/srs_web_server.log. Stop with:  kill $(cat /tmp/srs_web_server.pid)
#
#   cd app && python3 tool/web_daemon.py   ->  http://127.0.0.1:8443
import functools
import http.server
import os
import sys

PORT = 8443
APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Optional override: python3 tool/web_daemon.py /tmp/srs_web_snapshot
# Serving a snapshot copy keeps a stray build/copy from clobbering the live
# site mid-session.
SERVE_DIR = sys.argv[1] if len(sys.argv) > 1 else "build/web"

if __name__ == "__main__":
    first = os.fork()
    if first > 0:
        print("daemonizing...")
        sys.exit(0)
    os.setsid()
    second = os.fork()
    if second > 0:
        sys.exit(0)

    sys.stdout.flush()
    sys.stderr.flush()
    log = open("/tmp/srs_web_server.log", "ab", buffering=0)
    os.dup2(log.fileno(), 1)
    os.dup2(log.fileno(), 2)
    os.dup2(os.open(os.devnull, os.O_RDONLY), 0)
    with open("/tmp/srs_web_server.pid", "w") as f:
        f.write(str(os.getpid()))

    os.chdir(APP_DIR)
    http.server.SimpleHTTPRequestHandler.extensions_map[".wasm"] = (
        "application/wasm"
    )

    class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
        """Localhost dev server: never serve a stale build from cache — a
        cached main.dart.js from an older build shows a silent white screen."""

        def end_headers(self):
            self.send_header("Cache-Control", "no-store")
            super().end_headers()

    Handler = functools.partial(NoCacheHandler, directory=SERVE_DIR)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Serving {SERVE_DIR} at http://127.0.0.1:{PORT}", flush=True)
    server.serve_forever()

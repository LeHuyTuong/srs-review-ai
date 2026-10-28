# Static server for the Flutter web release build, with the WASM MIME type
# set so CanvasKit loads via streaming instantiation.
#
#   cd app && python3 tool/web_server.py   ->  http://127.0.0.1:8443
import functools
import http.server

http.server.SimpleHTTPRequestHandler.extensions_map[".wasm"] = "application/wasm"

Handler = functools.partial(
    http.server.SimpleHTTPRequestHandler, directory="build/web"
)

server = http.server.ThreadingHTTPServer(("127.0.0.1", 8443), Handler)
print("Serving build/web at http://127.0.0.1:8443")
server.serve_forever()

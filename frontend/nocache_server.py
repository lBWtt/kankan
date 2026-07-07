# 带 no-cache 头的静态服务器 — 避免浏览器强缓存 main.dart.js 导致"改了没变"。
# 用法: python nocache_server.py <port> <directory>
import http.server
import socketserver
import sys

port = int(sys.argv[1])
directory = sys.argv[2]


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=directory, **kwargs)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('127.0.0.1', port), NoCacheHandler) as httpd:
    print(f'no-cache server on {port} serving {directory}')
    httpd.serve_forever()

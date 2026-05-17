#!/usr/bin/env python3
"""hello-cc: minimal HTTP demo workload for rhel-cc-pattern"""
import http.server, socket, os

HTML = """<!DOCTYPE html>
<html>
<head><title>Hello Confidential Computing</title>
<style>
  body {{ font-family: monospace; background: #1a1a2e; color: #e0e0e0; padding: 40px; }}
  h1 {{ color: #00d4ff; }}
  td.label {{ color: #888; padding-right: 12px; }}
  td.value {{ color: #00ff88; }}
</style>
</head>
<body>
<h1>Hello Confidential Computing!</h1>
<table>
  <tr><td class="label">hostname:</td><td class="value">{hostname}</td></tr>
  <tr><td class="label">vm_type:</td><td class="value">{vm_type}</td></tr>
  <tr><td class="label">policy:</td><td class="value">{policy}</td></tr>
</table>
<p style="margin-top:30px;color:#555">
  rhel-cc-pattern &mdash;
  <a href="https://github.com/ariel-adam/rhel-cc-pattern" style="color:#555">
    github.com/ariel-adam/rhel-cc-pattern
  </a>
</p>
</body></html>
"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = HTML.format(
            hostname=socket.gethostname(),
            vm_type=os.environ.get("VM_TYPE", "unknown"),
            policy=os.environ.get("POLICY", "unknown"),
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8888))
    print(f"hello-cc serving on :{port}")
    http.server.HTTPServer(("", port), Handler).serve_forever()

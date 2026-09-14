"""Optional loopback interface. It does not run the checker."""
import argparse, pathlib, secrets, sys, json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/"operations"))
from operations_core import Desk, control
from operations_events import parent_alive

class DeskServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False
    def __init__(self, address, desk, assets):
        self.desk=desk; self.assets=assets; self.token=secrets.token_urlsafe(32)
        super().__init__(address, Handler)
        self.origin=f"http://127.0.0.1:{self.server_port}"; self.timeout=1

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def setup(self):
        super().setup(); self.connection.settimeout(5)
    def send(self, code, data, kind="application/json; charset=utf-8", attachment=False):
        if not isinstance(data, bytes): data=json.dumps(data).encode()
        self.send_response(code); self.send_header("Content-Type",kind); self.send_header("Content-Length",str(len(data)))
        self.send_header("Cache-Control","no-store"); self.send_header("X-Content-Type-Options","nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'")
        self.send_header("Referrer-Policy","no-referrer")
        if attachment: self.send_header("Content-Disposition", "attachment")
        self.end_headers(); self.wfile.write(data)
    def allowed(self, write=False):
        if self.headers.get("Host") != self.server.origin[7:]: return False
        if self.headers.get("Origin") not in (None, self.server.origin): return False
        if self.headers.get("Sec-Fetch-Site") == "cross-site": return False
        return not write or (self.headers.get("Origin") == self.server.origin and secrets.compare_digest(self.headers.get("X-Desk-Token", ""), self.server.token))
    def do_GET(self):
        if not self.allowed(): return self.send(403, {"error":"Local desk origin required"})
        parsed=urlparse(self.path)
        try:
            if parsed.path == "/api/snapshot": return self.send(200, {**self.server.desk.snapshot(), "token":self.server.token})
            if parsed.path == "/api/report":
                relative=parse_qs(parsed.query).get("path", [""])[0]
                data=self.server.desk.report(relative)
                binary=pathlib.Path(relative).suffix.lower() in {".pdf", ".docx", ".xlsx", ".pptx"}
                return self.send(200, data, "application/octet-stream" if binary else "text/plain; charset=utf-8", binary)
            asset={"/":"index.html", "/app.js":"app.js", "/style.css":"style.css"}.get(parsed.path)
            if not asset: return self.send(404, {"error":"Not found"})
            kind={"index.html":"text/html", "app.js":"text/javascript", "style.css":"text/css"}[asset]
            return self.send(200, (self.server.assets/asset).read_bytes(),kind+"; charset=utf-8")
        except (OSError, ValueError, KeyError, control.ControlError) as exc: return self.send(409, {"error":str(exc)})
    def do_POST(self):
        if not self.allowed(True): return self.send(403, {"error":"Same-origin desk action required"})
        try:
            length=int(self.headers.get("Content-Length", "0"))
            if length < 1 or length > 8192 or self.headers.get_content_type() != "application/json": raise ValueError("Bounded JSON body required")
            body=json.loads(self.rfile.read(length)); desk=self.server.desk
            if self.path == "/api/recover": result=desk.request(body["id"],body["fingerprint"])
            elif self.path == "/api/seen": result=desk.mark_seen(body["path"],body["sha256"])
            else: return self.send(404, {"error":"Not found"})
            return self.send(200,result)
        except (OSError, ValueError, KeyError, TypeError) as exc: return self.send(409,{"error":str(exc)})

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--root',required=True);parser.add_argument('--registry',required=True)
    parser.add_argument('--port',type=int,default=8765);parser.add_argument('--parent-pid',type=int,default=0)
    args=parser.parse_args()
    desk=Desk(args.root,args.registry)
    with (desk.registry/'interface.lock').open('a+b') as lock:
        if not lock.tell():lock.write(b'0');lock.flush()
        lock.seek(0)
        import msvcrt
        msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
        stop=desk.registry/'interface.stop'
        if stop.exists():stop.unlink()
        with DeskServer(('127.0.0.1',args.port),desk,pathlib.Path(__file__).parent/'assets') as server:
            print(server.origin,flush=True)
            while parent_alive(args.parent_pid) and not stop.exists():server.handle_request()

if __name__=='__main__':main()

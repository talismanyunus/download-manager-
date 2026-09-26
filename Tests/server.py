from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import time
DATA = bytes(range(256)) * 16384
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path == '/missing':
   self.send_error(404); return
  start = int(self.headers.get('Range','bytes=0-').split('=')[1].split('-')[0])
  self.send_response(206 if start else 200)
  self.send_header('Content-Length', str(len(DATA)-start))
  self.send_header('Accept-Ranges', 'bytes')
  self.send_header('ETag', '"fixture-v1"')
  self.send_header('Last-Modified', 'Wed, 01 Jan 2025 00:00:00 GMT')
  self.send_header('Content-Disposition', 'attachment; filename="fixture.bin"')
  if start: self.send_header('Content-Range', f'bytes {start}-{len(DATA)-1}/{len(DATA)}')
  self.end_headers()
  try:
   for i in range(start,len(DATA),32768):
    self.wfile.write(DATA[i:i+32768]); self.wfile.flush(); time.sleep(.015)
  except (BrokenPipeError,ConnectionResetError): pass
 def log_message(self,fmt,*args): pass
ThreadingHTTPServer(('127.0.0.1',18764),Handler).serve_forever()

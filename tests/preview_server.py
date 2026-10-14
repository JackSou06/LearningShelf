from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from pathlib import Path
import json,time
ROOT=Path(__file__).resolve().parents[1]/'web'
class Handler(SimpleHTTPRequestHandler):
 def __init__(self,*a,**k):super().__init__(*a,directory=str(ROOT),**k)
 def log_message(self,*a):pass
 def do_GET(self):
  if self.path=='/qa-test':
   html=(ROOT/'index.html').read_text().replace('<script src="platform.js"></script>','''<script>const realFetch=window.fetch;window.fetch=(url,opts)=>url==='https://api.openai.com/v1/responses'?realFetch('/qa-mock',opts):realFetch(url,opts);</script><script src="platform.js"></script>''')
   self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers();self.wfile.write(html.encode());return
  return super().do_GET()
 def do_POST(self):
  if self.path!='/qa-mock':self.send_error(404);return
  body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  assert body['store'] is False and body['truncation']=='disabled'
  context=body['input'][0]['content'][0]['text'];question=body['input'][1]['content'][0]['text']
  assert '## 本主題筆記' in context and '## 本主題過往 Q&A' in context
  if '慢速' in question:time.sleep(2)
  result={'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':'（本機介面測試回應）\n\n此回答用來驗證 Q&A 展開、上下文與保存，沒有呼叫 OpenAI。'}]}],'usage':{'input_tokens':123,'output_tokens':40}}
  self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers()
  try:self.wfile.write(json.dumps(result).encode())
  except BrokenPipeError:pass
ThreadingHTTPServer(('127.0.0.1',8877),Handler).serve_forever()

"""Standard-library local web dashboard (no external JS/CDN needed)."""
import argparse
import json
import sqlite3
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

HTML = r'''<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>SafeZone AI - لوحة المصنع</title><style>
* {box-sizing:border-box} body{font-family:system-ui,Tahoma,sans-serif;background:#0b1526;color:#e5edf8;margin:0;padding:24px}
main{max-width:1000px;margin:auto}h1{margin-bottom:0}p{color:#a9b8ce} .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:14px;margin:24px 0}
.card{background:#18263d;border:1px solid #2c3f5c;padding:20px;border-radius:16px}.num{font-size:36px;font-weight:800;display:block;margin-top:8px}
.red{color:#ff747a}.green{color:#5ce1a1}.yellow{color:#f8ca6b}table{width:100%;border-collapse:collapse;text-align:right;background:#142136;border-radius:12px;overflow:hidden}
th,td{border-bottom:1px solid #314058;padding:12px;font-size:14px}th{background:#1c304b} .scroller{overflow:auto}button{background:#2679d6;border:0;padding:9px 16px;border-radius:8px;color:white;cursor:pointer}
small{color:#a9b8ce} </style></head><body><main>
<h1>🛡️ SafeZone AI</h1><p>نظام مراقبة الالتزام بمتطلبات السلامة عند بوابات المصنع · بيانات فعلية من قاعدة الأحداث</p>
<div class="grid"><div class="card">إجمالي الدخول<span class="num" id="total">0</span></div>
<div class="card">ملتزم<span class="num green" id="ok">0</span></div>
<div class="card">مخالف<span class="num red" id="bad">0</span></div>
<div class="card">يحتاج مراجعة<span class="num yellow" id="unknown">0</span></div>
<div class="card">نسبة الالتزام في الحالات المحسومة<span class="num" id="rate">—</span></div></div>
<h2>الإحصائيات حسب المنطقة</h2><div class="scroller"><table><thead><tr><th>المنطقة</th><th>ملتزم</th><th>مخالف</th><th>مراجعة</th></tr></thead><tbody id="zones"></tbody></table></div>
<h2>أحدث أحداث الدخول</h2><div class="scroller"><table><thead><tr><th>الوقت (UTC)</th><th>الكاميرا</th><th>المنطقة</th><th>النتيجة</th><th>المعدات الناقصة</th></tr></thead><tbody id="events"></tbody></table></div>
<p><small>يتم تحديث البيانات كل 5 ثوانٍ. لا يتضمن النظام تعرّفاً على الوجوه أو هوية الموظفين. "غير مؤكد" ليس مخالفة.</small></p>
<button onclick="refresh()">تحديث الآن</button></main><script>
const statuses={compliant:'ملتزم',violation:'مخالف',unknown:'غير مؤكد'};
function cell(tr,txt){let td=document.createElement('td');td.textContent=String(txt);tr.appendChild(td)}
async function refresh(){try{let r=await fetch('/api/stats');let j=await r.json();
for (const [id,val] of Object.entries({total:j.total,ok:j.counts.compliant,bad:j.counts.violation,unknown:j.counts.unknown,rate:j.rate}))document.getElementById(id).textContent=val;
for(const [id,rows,cols] of [['zones',j.zones,['zone','compliant','violation','unknown']],['events',j.events,['time_utc','camera','zone','outcome','missing']]]){
 let body=document.getElementById(id);body.textContent='';for(let item of rows){let tr=document.createElement('tr');for(let col of cols)cell(tr,col==='outcome'?statuses[item[col]]??item[col]:item[col]);body.appendChild(tr)}
}
}catch(e){console.error(e)}} refresh();setInterval(refresh,5000);
</script></body></html>'''


def get_stats(path):
    if not Path(path).exists():
        return dict(total=0,counts=dict(compliant=0,violation=0,unknown=0),rate='—',zones=[],events=[])
    con=sqlite3.connect(path,timeout=10)
    try:
        counts=dict(compliant=0,violation=0,unknown=0)
        for outcome,n in con.execute('SELECT outcome,COUNT(*) FROM events GROUP BY outcome'):
            counts[outcome]=n
        resolved=counts['compliant']+counts['violation']
        zones={}
        for zone,outcome,n in con.execute('SELECT zone,outcome,COUNT(*) FROM events GROUP BY zone,outcome'):
            zones.setdefault(zone,dict(zone=zone,compliant=0,violation=0,unknown=0))[outcome]=n
        events=[dict(zip(('time_utc','camera','zone','outcome','missing'), row)) for row in
                con.execute('SELECT time_utc,camera,zone,outcome,missing FROM events ORDER BY id DESC LIMIT 20')]
        return dict(total=sum(counts.values()),counts=counts,rate=f'{counts["compliant"]/resolved*100:.1f}%' if resolved else '—',zones=list(zones.values()),events=events)
    except sqlite3.OperationalError:
        return dict(total=0,counts=dict(compliant=0,violation=0,unknown=0),rate='—',zones=[],events=[])
    finally:
        con.close()


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--database',default='safezone.db')
    p.add_argument('--port',type=int,default=8501)
    p.add_argument('--host',default='127.0.0.1',help='Local only by default')
    a=p.parse_args()
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            endpoint=urlparse(self.path).path
            if endpoint=='/api/stats':
                body=json.dumps(get_stats(a.database),ensure_ascii=False).encode('utf-8')
                ctype='application/json; charset=utf-8'
            elif endpoint=='/':
                body=HTML.encode('utf-8')
                ctype='text/html; charset=utf-8'
            else:
                self.send_error(404);return
            self.send_response(200)
            self.send_header('Content-Type',ctype)
            self.send_header('Cache-Control','no-store')
            self.send_header('Content-Length',str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    print(f'Dashboard: http://{a.host}:{a.port} | database={a.database}')
    ThreadingHTTPServer((a.host,a.port),Handler).serve_forever()


if __name__=='__main__':
    main()

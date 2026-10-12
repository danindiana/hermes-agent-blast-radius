#!/usr/bin/env bash
# Drive a Hermes-style sandbox container through a representative workload.
# Each step is its own `docker exec ... bash -c` (the way Hermes issues tool calls).
# usage: run_suite.sh <container> [results.tsv]
C=${1:?container}; OUT=${2:-/dev/stdout}
: > "$OUT"
step() { # name, command
  local name=$1; shift
  if timeout 240 docker exec "$C" bash -c "$*" >/tmp/suite.$$.log 2>&1; then
    printf '%s\tPASS\n' "$name" >> "$OUT"
  else
    printf '%s\tFAIL\t%s\n' "$name" "$(tail -c 300 /tmp/suite.$$.log | tr '\n\t' '  ')" >> "$OUT"
  fi
}
W=/workspace/suite_tmp
step shell_coreutils   "mkdir -p $W && cd $W && echo hello >a.txt && cp a.txt b.txt && mv b.txt c.txt && ls -la && cat c.txt | sort | uniq | wc -l && find . -type f | xargs ls -l && stat a.txt && ln -s a.txt l && readlink l && chmod 640 a.txt && touch -d '2020-01-01' a.txt && du -sh . && df -h . | tail -1 && env | wc -l && date && uname -a && ps aux | head -3 && sleep 0.2 && head -c 100000 /dev/urandom | base64 | gzip | gunzip | wc -c"
step text_tools       "cd $W && printf 'a b\nc d\n' >t && sed 's/a/z/' t && awk '{print \$2}' t && grep -r c . | head -2 && rg c . | head -2 && jq -n '{a:1}' && diff <(echo 1) <(echo 2); true"
step archive          "cd $W && tar czf x.tgz a.txt && tar xzf x.tgz -C /tmp && tar cJf x.txz a.txt && xz -dc x.txz | tar t && zip -q z.zip a.txt 2>/dev/null; unzip -l z.zip 2>/dev/null; gzip -k a.txt -f && gunzip -c a.txt.gz"
step git              "cd $W && rm -rf g && git init -q g && cd g && git config user.email a@b && git config user.name n && echo x>f && git add f && git commit -qm c && git log --oneline && git branch t && git checkout -q t && git diff HEAD~0 && git status --short"
step python_stdlib    "python3 -c 'import os,sys,json,sqlite3,threading,socket,subprocess,tempfile,hashlib,zlib,ssl,urllib.request,asyncio,multiprocessing,ctypes,mmap,select,signal,fcntl,pty,resource,shutil,logging,datetime,decimal,re,itertools;
print(sqlite3.connect(\":memory:\").execute(\"select 1\").fetchall())'"
step python_threads_mp "python3 - <<'PY'
import threading, multiprocessing as mp, subprocess, os, tempfile, mmap, signal, socket, asyncio, concurrent.futures as cf
def f(x): return x*x
with mp.Pool(2) as p: print(p.map(f, range(8)))
with cf.ThreadPoolExecutor(4) as ex: print(list(ex.map(f, range(8))))
print(subprocess.run(['echo','hi'],capture_output=True).stdout)
with tempfile.TemporaryDirectory() as d:
    fn=os.path.join(d,'m'); open(fn,'wb').write(b'0'*4096)
    with open(fn,'r+b') as fh: m=mmap.mmap(fh.fileno(),0); m[0]=65; m.close()
a,b=socket.socketpair(); a.send(b'x'); print(b.recv(1))
s=socket.socket(); s.bind(('127.0.0.1',0)); s.listen(); print(s.getsockname()[0])
async def g(): await asyncio.sleep(0.01); return 1
print(asyncio.run(g()))
signal.signal(signal.SIGUSR1, lambda *a: None); os.kill(os.getpid(), signal.SIGUSR1)
import pty; pid,fd=pty.fork()
if pid==0: os.execvp('echo',['echo','pty']) 
else: print(os.read(fd,100)); os.waitpid(pid,0)
PY"
step python_venv_pip  "cd $W && python3 -m venv v && v/bin/python -c 'import sys;print(sys.prefix)' && v/bin/pip --version"
step python_numpy_etc "python3 -c 'import numpy, PIL; print(numpy.arange(4).sum())' 2>&1 | tail -2"
step torch_cpu_gpu    "python3 -c 'import torch; x=torch.randn(512,512); print((x@x).sum().item()>-1e9); print(torch.cuda.is_available()); d=torch.device(\"cuda:1\") if torch.cuda.device_count()>1 else torch.device(\"cuda:0\"); y=torch.randn(2048,2048,device=d); print((y@y).sum().item()==(y@y).sum().item()); torch.cuda.synchronize()'"
step nvidia_smi       "nvidia-smi -L && nvidia-smi --query-gpu=name,memory.used --format=csv"
step nim_build_run    "cd $W && printf 'echo \"nim ok\", 1+1\n' > h.nim && nim c -r --hints:off --verbosity:0 h.nim"
step gcc_make         "cd $W && printf '#include <stdio.h>\n#include <pthread.h>\nint main(){puts(\"c ok\");return 0;}\n' > c.c && gcc -O2 -o c c.c -lpthread && ./c && printf 'all:\n\t@echo make ok\n' > Makefile && make"
step node             "node -e 'const fs=require(\"fs\");fs.writeFileSync(\"/workspace/suite_tmp/n.txt\",\"x\");console.log(require(\"os\").cpus().length>0, require(\"crypto\").randomBytes(4).length)'"
step graphviz         "cd $W && echo 'digraph{a->b}' | dot -Tsvg -o g.svg && dot -Tpng -o g.png <<< 'digraph{a->b}' && ls -l g.svg g.png"
step pdf_tools        "cd $W && echo 'digraph{a->b}' | dot -Tpdf -o p.pdf && pdftotext p.pdf - | head -2 && pdfinfo p.pdf | head -2 && pdftoppm -png -r 40 p.pdf pp && ls pp*"
step ocr              "cd $W && convert -size 300x80 xc:white -pointsize 28 -draw \"text 10,50 'Hello OCR'\" o.png 2>/dev/null || python3 -c \"from PIL import Image,ImageDraw;i=Image.new('RGB',(300,80),'white');ImageDraw.Draw(i).text((10,30),'Hello OCR',fill='black');i.save('o.png')\"; tesseract o.png - 2>&1 | head -2"
step ocrmypdf         "cd $W && ocrmypdf --force-ocr --output-type pdf p.pdf p_ocr.pdf >/dev/null 2>&1; ls -l p_ocr.pdf"
step ffmpeg           "cd $W && ffmpeg -loglevel error -y -f lavfi -i testsrc=duration=1:size=160x120:rate=10 -f lavfi -i sine=duration=1 -shortest o.mp4 && ffprobe -loglevel error -show_format o.mp4 | head -2"
step pandoc           "cd $W && printf '# T\nhello\n' > m.md && pandoc m.md -o m.html && pandoc m.md -t plain"
step sqlite_cli       "cd $W && sqlite3 d.db 'create table t(a); insert into t values(1); select * from t;'"
step tmux             "tmux -f /dev/null new-session -d -s s 'sleep 1' && tmux list-sessions && tmux kill-server"
step net_dns_https    "curl -sS -m 20 -o /dev/null -w '%{http_code}\n' https://example.com && getent hosts example.com"
step net_wget         "wget -q -T 20 -O /dev/null https://example.com"
step net_python_https "python3 -c 'import urllib.request as u;print(u.urlopen(\"https://example.com\",timeout=20).status)'"
step ssh_client       "ssh -V 2>&1 && ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=no nosuchhost.invalid true 2>&1 | head -1; true"
step rsync            "cd $W && rsync -a a.txt /tmp/r.txt && ls /tmp/r.txt"
step ro_mounts        "ls /ro/Documents | head -3 && (touch /ro/Documents/x 2>&1 | head -1; true)"
step big_io           "cd $W && dd if=/dev/zero of=big bs=1M count=64 status=none && sync && rm big && fallocate -l 8M f8 && truncate -s 1M f8 && cp --reflink=auto f8 f9"
step proc_sys_reads   "cat /proc/cpuinfo | head -1 && cat /proc/meminfo | head -1 && cat /proc/self/status | head -1 && ls /sys/fs/cgroup | head -2; nproc; free -m | head -2; ulimit -a | head -3; id; whoami; hostname"
step pgrp_signals     "sleep 30 & p=\$!; kill -TERM \$p; wait \$p; echo done; setsid sleep 0.1; (sleep 0.1 &) ; true"
step nimble_check     "nimble --version"
step login_shell       "bash -lc 'echo \$0; cd /workspace && pwd && type python3'"
step stdin_heredoc     "cat > /workspace/suite_tmp/hd.py <<'PYEOF'
print(sum(range(10)))
PYEOF
python3 /workspace/suite_tmp/hd.py"
step timeout_kill      "timeout 1 sleep 5; echo rc=\$?"
step xargs_parallel    "seq 1 20 | xargs -P4 -I{} sh -c 'echo {} >/dev/null' && echo ok"
step background_jobs   "(sleep 0.3; echo bg) & wait; echo done"
step http_server_curl  "cd /workspace/suite_tmp && (python3 -m http.server 18080 --bind 127.0.0.1 >/dev/null 2>&1 &) ; sleep 1; curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/; true"
step apt_like_readonly "ls /var/lib/dpkg | head -2; dpkg -l | head -3; dpkg -S /bin/ls; true"
step locale_tz         "TZ=America/New_York date; python3 -c 'import locale,time;print(time.tzname)'"
step cleanup          "rm -rf $W"

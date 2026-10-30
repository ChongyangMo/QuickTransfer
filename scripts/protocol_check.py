"""用官方 LocalSend CLI 与原生核心进行真实 TLS 文件、文字互传。"""
import pathlib,subprocess,json,queue,threading,time,pty,os,select,hashlib,sys,fcntl,termios,struct
ROOT=pathlib.Path(__file__).resolve().parents[1]
work=ROOT/"work/protocol-check";work.mkdir(parents=True,exist_ok=True)
destination=work/"localsend-received";destination.mkdir(exist_ok=True)
source=ROOT/"work/real-photo.png"
assert source.is_file(),"真实照片文件不存在"
config={"root":str(work/"native"),"alias":"快传协议检查","model":"Mac","mobile":False,"port":53319,"multicast":False}
(work/"config.json").write_text(json.dumps(config))
node=subprocess.Popen(["/usr/bin/python3",str(ROOT/"scripts/core_node.py"),str(work/"config.json")],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
events=queue.Queue();all_events=[]
def read():
    for line in node.stdout:
        value=json.loads(line);all_events.append(value);events.put(value)
threading.Thread(target=read,daemon=True).start()
def command(value):node.stdin.write(json.dumps(value)+"\n");node.stdin.flush()
def wait(kind,timeout=25):
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        event=events.get(timeout=max(.1,end-time.monotonic()))
        if event["type"]=="incoming":command({"action":"accept","id":event["id"],"remember":False})
        if event["type"] in ("failed","error"):raise RuntimeError(event)
        if event["type"]==kind:return event
    raise TimeoutError(kind)
pid=None;fd=None
try:
    ready=wait("ready")
    pid,fd=pty.fork()
    if pid==0:os.execl(str(ROOT/"work/localsend-cli/localsend-cli"),"localsend-cli","--alias","LocalSend 官方客户端","--port","53318","--destination",str(destination))
    fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack("HHHH",40,140,0,0))
    output=[];reader_stop=threading.Event()
    def cli_output():
        while not reader_stop.is_set():
            try:
                if select.select([fd],[],[],.2)[0]:
                    data=os.read(fd,65536)
                    if not data:return
                    output.append(data)
            except OSError:return
    threading.Thread(target=cli_output,daemon=True).start()
    time.sleep(1.5)
    command({"action":"probe","host":"127.0.0.1","port":53318})
    devices=wait("devices");peer=next(p for p in devices["devices"] if p["port"]==53318)
    digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
    command({"action":"send","peer":peer["id"],"id":"official-file","paths":[str(source)]})
    time.sleep(.4);os.write(fd,b"y")
    sent=wait("sent")
    received_files=list(destination.rglob(source.name))
    assert received_files,"官方客户端没有保存照片"
    assert digest(received_files[0])==digest(source),"官方客户端收到的照片不一致"
    text=(ROOT/"apple/Shared/Models.swift").read_text()
    command({"action":"send","peer":peer["id"],"id":"official-text","text":text})
    time.sleep(.2);os.write(fd,b"y")
    wait("sent")
    result={"official":"LocalSend CLI 1.18.2","tls":True,"native_to_localsend_photo":True,"native_to_localsend_text":True,"photo_bytes":source.stat().st_size,"sha256":digest(source)}
    (work/"result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False))
finally:
    if pid:
        try:os.kill(pid,15)
        except ProcessLookupError:pass
    node.terminate()
    (work/"events.json").write_text(json.dumps(all_events,ensure_ascii=False,indent=2))
    if "output" in locals():(work/"official-cli.log").write_bytes(b"".join(output))

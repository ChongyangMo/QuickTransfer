import json,pathlib,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
windows="1083C5869772E8BE6A808ABF36D07F1F24D19F2B2C967182CCB41DBC8128D9B9"
config={"host":"172.20.10.3","port":53317,"sendFingerprint":windows,"receiveFingerprint":windows,"transfers":[{"text":(ROOT/"apple/Shared/Models.swift").read_text()},{"paths":[str(ROOT/"work/real-photo.png")]}],"logPath":str(ROOT/"work/mac-windows-events.jsonl")}
path=ROOT/"work/mac-windows-verify.json";path.write_text(json.dumps(config))
subprocess.run(["pkill","-x","QuickTransferMac"],check=True)
for _ in range(50):
    if subprocess.run(["pgrep","-x","QuickTransferMac"],stdout=subprocess.DEVNULL).returncode!=0:break
    time.sleep(.1)
else:raise RuntimeError("旧客户端尚未退出")
subprocess.run(["ditto",str(ROOT/"build/Build/Products/Debug/QuickTransferMac.app"),"/Users/chongyang/Applications/QuickTransfer.app"],check=True)
subprocess.run(["open","-n","-a","/Users/chongyang/Applications/QuickTransfer.app","--args","--verify-config",str(path)],check=True)

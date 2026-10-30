import pathlib,json,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
DEVICE="00008150-000215CC0E78401C"
BUNDLE="com.chongyang.quicktransfer.ios"
def run(*args):subprocess.run(args,check=True,cwd=ROOT)
def copy(path,destination):run("xcrun","devicectl","device","copy","to","--device",DEVICE,"--source",str(path),"--destination",destination,"--domain-type","appDataContainer","--domain-identifier",BUNDLE)
mac=next(json.loads(line) for line in (ROOT/"work/mac-app-events.jsonl").read_text().splitlines() if json.loads(line)["type"]=="ready")
config={"host":"172.20.10.2","port":mac["port"],"sendFingerprint":mac["fingerprint"],"receiveFingerprint":mac["fingerprint"],"transfers":[{"text":(ROOT/"apple/Shared/Models.swift").read_text()},{"paths":["real-photo.png"]}]}
path=ROOT/"work/iphone-verify.json";path.write_text(json.dumps(config))
run("xcrun","devicectl","device","install","app","--device",DEVICE,str(ROOT/"build/Build/Products/Debug-iphoneos/QuickTransferiOS.app"))
copy(path,"Documents/verify.json");copy(ROOT/"work/real-photo.png","Documents/real-photo.png")
run("xcrun","devicectl","device","process","launch","--device",DEVICE,"--terminate-existing",BUNDLE,"--verify-config","verify.json")

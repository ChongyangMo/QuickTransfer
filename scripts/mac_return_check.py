import pathlib,json,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
events=[json.loads(line) for line in (ROOT/"work/iphone-send-events.jsonl").read_text().splitlines()]
phone=next(event for event in events if event["type"]=="ready")
path=ROOT/"work/mac-verify.json"
config=json.loads(path.read_text());config.update({"sendFingerprint":phone["fingerprint"],"transfers":[{"text":(ROOT/"apple/Shared/Models.swift").read_text()},{"paths":[str(ROOT/"work/real-photo.png")]}]})
path.write_text(json.dumps(config))
subprocess.run(["pkill","-x","QuickTransferMac"],check=True)
subprocess.run(["open","-a","/Users/chongyang/Applications/QuickTransfer.app","--args","--verify-config",str(path)],check=True)

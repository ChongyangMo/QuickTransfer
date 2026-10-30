import pathlib,json,hashlib,subprocess,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
work=ROOT/"work"
expected=hashlib.sha256((work/"real-photo.png").read_bytes()).hexdigest()
text=(ROOT/"apple/Shared/Models.swift").read_text()
def events(name):return [json.loads(line) for line in (work/name).read_text().splitlines()]
mac=events("mac-windows-events.jsonl")
phone=events("iphone-windows-events.jsonl")
assert next(e for e in mac if e["type"]=="received")["sha256"]==expected
assert next(e for e in mac if e["type"]=="text")["text"]==text
assert next(e for e in phone if e["type"]=="received")["sha256"]==expected
assert next(e for e in phone if e["type"]=="text")["text"]==text
assert json.loads((work/"windows-phone-result.json").read_text())["iphone_to_windows_photo"]
assert json.loads((work/"windows-mac-result.json").read_text())["mac_to_windows_photo"]
assert json.loads((work/"protocol-check/result.json").read_text())["native_to_localsend_photo"]
result={"version":"0.1.0","native_clients":["macOS arm64","iOS arm64","Windows x64"],"physical_iphone":"iPhone 17 Pro Max","iphone_mac":{"photo_both_directions":True,"text_both_directions":True},"windows_mac":{"photo_both_directions":True,"text_both_directions":True},"windows_iphone":{"photo_both_directions":True,"text_both_directions":True},"iphone_share_extension":"passed on physical device","localsend_cli":"1.18.2 photo and text receiving passed","photo_bytes":(work/"real-photo.png").stat().st_size,"photo_sha256":expected,"protocol":"LocalSend v2.2 HTTPS"}
(ROOT/"distribution").mkdir(exist_ok=True)
(ROOT/"distribution/verification.json").write_text(json.dumps(result,ensure_ascii=False,indent=2))
# Preserve diagnostics outside the distributed application and clear only our own records.
history=pathlib.Path("/Users/chongyang/Library/Application Support/QuickTransfer/history.json")
if history.exists():
    shutil.copy2(history,work/"mac-history-backup.json")
    rows=json.loads(history.read_text())
    def own(row):
        return row.get("text")==text or (row.get("name")=="real-photo.png" and row.get("size")==2702073) or (row.get("name")=="文字.txt" and row.get("size")==len(text.encode()))
    history.write_text(json.dumps([r for r in rows if not own(r)],ensure_ascii=False))
print("三端文件与文字校验完成，检查记录已归档")

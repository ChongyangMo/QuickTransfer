import pathlib,plistlib,subprocess,os,datetime
ROOT=pathlib.Path(__file__).resolve().parents[1]
subprocess.run(["/usr/bin/python3",str(ROOT/"scripts/generate_project.py")],check=True)
label="com.chongyang.quicktransfer.sharecheck"
job=ROOT/"work/share-check.plist"
result=ROOT/("work/share-ui-"+datetime.datetime.now().strftime("%H%M%S")+".xcresult")
args=["/usr/bin/python3",str(ROOT/"scripts/run_share_ui.py"),str(result)]
job.write_bytes(plistlib.dumps({"Label":label,"ProgramArguments":args,"WorkingDirectory":str(ROOT),"RunAtLoad":True,"LimitLoadToSessionType":"Aqua","StandardOutPath":str(ROOT/"work/share-ui.log"),"StandardErrorPath":str(ROOT/"work/share-ui-errors.log")}))
subprocess.run(["launchctl","bootstrap",f"gui/{os.getuid()}",str(job)],check=True)
print("已启动真机分享流程检查")

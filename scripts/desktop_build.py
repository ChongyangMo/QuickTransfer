import pathlib,plistlib,subprocess,os,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
label="com.chongyang.quicktransfer.build"
job=ROOT/"work/desktop-build.plist"
job.write_bytes(plistlib.dumps({"Label":label,"ProgramArguments":["/usr/bin/python3",str(ROOT/"scripts/build.py"),"ios","--configuration","Release" if "--release" in sys.argv else "Debug"],"WorkingDirectory":str(ROOT),"RunAtLoad":True,"LimitLoadToSessionType":"Aqua","StandardOutPath":str(ROOT/"work/ios-desktop-build.log"),"StandardErrorPath":str(ROOT/"work/ios-desktop-build-errors.log")}))
subprocess.run(["launchctl","bootstrap",f"gui/{os.getuid()}",str(job)],check=True)
print("已在 Mac 桌面会话启动签名构建")

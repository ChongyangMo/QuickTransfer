import argparse,pathlib,subprocess,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument("platform",choices=["mac","ios","sim"]);parser.add_argument("--device",default="00008150-000215CC0E78401C");parser.add_argument("--configuration",choices=["Debug","Release"],default="Debug");args=parser.parse_args()
target={"mac":"aarch64-apple-darwin","ios":"aarch64-apple-ios","sim":"aarch64-apple-ios-sim"}[args.platform]
platform={"mac":"macosx","ios":"iphoneos","sim":"iphonesimulator"}[args.platform]
cargo="/Users/chongyang/.cargo/bin/cargo"
print("编译传输核心",flush=True)
subprocess.run([cargo,"build","--release","--locked","--manifest-path",str(ROOT/"core/Cargo.toml"),"--target",target],check=True,cwd=ROOT)
asset=ROOT/"apple/Assets.xcassets/AppIcon.appiconset/Contents.json"
if not asset.exists() or (ROOT/"scripts/generate_assets.swift").stat().st_mtime>asset.stat().st_mtime:
    subprocess.run(["swift",str(ROOT/"scripts/generate_assets.swift"),str(ROOT)],check=True,cwd=ROOT)
library=ROOT/"Libraries"/platform;library.mkdir(parents=True,exist_ok=True)
shutil.copy2(ROOT/"core/target"/target/"release/libquicktransfer.a",library/"libquicktransfer.a")
subprocess.run(["/usr/bin/python3",str(ROOT/"scripts/generate_project.py")],check=True)
scheme="QuickTransferMac" if args.platform=="mac" else "QuickTransferiOS"
destination="platform=macOS,arch=arm64" if args.platform=="mac" else "generic/platform=iOS Simulator" if args.platform=="sim" else "id="+args.device
command=["xcodebuild","-project",str(ROOT/"QuickTransfer.xcodeproj"),"-scheme",scheme,"-configuration",args.configuration,"-derivedDataPath",str(ROOT/"build"),"-destination",destination,"ONLY_ACTIVE_ARCH=YES","ARCHS=arm64","build"]
if args.platform=="sim":command.append("CODE_SIGNING_ALLOWED=NO")
elif args.platform=="ios":command.append("-allowProvisioningUpdates")
print("编译原生客户端",flush=True)
subprocess.run(command,check=True,cwd=ROOT)
print("编译完成",flush=True)

import pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
device="00008150-000215CC0E78401C"
base=["xcodebuild","-project",str(ROOT/"QuickTransfer.xcodeproj"),"-configuration","Debug","-derivedDataPath",str(ROOT/"build"),"-destination","id="+device,"-allowProvisioningUpdates","ONLY_ACTIVE_ARCH=YES","ARCHS=arm64"]
subprocess.run(base+["-scheme","QuickTransferShareHost","build"],check=True)
subprocess.run(["xcrun","devicectl","device","install","app","--device",device,str(ROOT/"build/Build/Products/Debug-iphoneos/QuickTransferShareHost.app")],check=True)
subprocess.run(["xcrun","devicectl","device","copy","to","--device",device,"--source",str(ROOT/"work/real-photo.png"),"--destination","Documents/real-photo.png","--domain-type","appDataContainer","--domain-identifier","com.chongyang.quicktransfer.sharehost"],check=True)
subprocess.run(base+["-scheme","QuickTransferiOS","-resultBundlePath",sys.argv[1],"test"],check=True)

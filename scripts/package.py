import pathlib,shutil,subprocess,zipfile,json,hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
dist=ROOT/"distribution";dist.mkdir(exist_ok=True)
mac=dist/"Mac/QuickTransfer.app";mac.parent.mkdir(exist_ok=True)
subprocess.run(["ditto",str(ROOT/"build/Build/Products/Release/QuickTransferMac.app"),str(mac)],check=True)
subprocess.run(["codesign","--verify","--deep","--strict",str(mac)],check=True)
subprocess.run(["ditto","-c","-k","--sequesterRsrc","--keepParent",str(mac),str(dist/"QuickTransfer-Mac.zip")],check=True)
phone=dist/"iPhone/Payload/QuickTransferiOS.app";phone.parent.mkdir(parents=True,exist_ok=True)
subprocess.run(["ditto",str(ROOT/"build/Build/Products/Release-iphoneos/QuickTransferiOS.app"),str(phone)],check=True)
subprocess.run(["codesign","--verify","--deep","--strict",str(phone)],check=True)
subprocess.run(["ditto","-c","-k","--keepParent",str(phone.parent),str(dist/"QuickTransfer-iPhone.ipa")],check=True)
source=dist/"QuickTransfer-source.zip"
with zipfile.ZipFile(source,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for name in ["apple","scripts","QuickTransfer.xcodeproj","core/src","core/include","vendor/localsend/packages/core"]:
        for path in (ROOT/name).rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts:
                archive.write(path,"QuickTransfer/"+str(path.relative_to(ROOT)))
    for path in (ROOT/"windows").rglob("*"):
        if path.is_file() and not any(p in path.parts for p in ["packages-feed","obj","bin"]):archive.write(path,"QuickTransfer/"+str(path.relative_to(ROOT)))
    for name in ["core/Cargo.toml","core/Cargo.lock","QuickTransfer.slnx","README.txt","THIRD_PARTY_NOTICES.txt","vendor/localsend/LICENSE"]:
        archive.write(ROOT/name,"QuickTransfer/"+name)
print("Mac、iPhone 与源码包已生成")

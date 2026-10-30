import pathlib, plistlib, json, hashlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEAM = "Q269MU4N6F"
objects = {}
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def add(identifier, **value):
    key = uid(identifier); objects[key] = value; return key
def quote(value): return json.dumps(str(value), ensure_ascii=False)
def render(value):
    if isinstance(value, dict): return "{ " + " ".join(quote(k)+" = "+render(v)+";" for k,v in value.items()) + " }"
    if isinstance(value, list): return "(" + ", ".join(render(v) for v in value) + ")"
    return quote(value)
def plist(name, value):
    path = ROOT / name; path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(plistlib.dumps(value))

base = {"CFBundleDisplayName":"快传","CFBundleName":"QuickTransfer","CFBundleExecutable":"$(EXECUTABLE_NAME)","CFBundleIdentifier":"$(PRODUCT_BUNDLE_IDENTIFIER)","CFBundlePackageType":"APPL","CFBundleShortVersionString":"0.1.0","CFBundleVersion":"1","NSLocalNetworkUsageDescription":"发现附近设备并直接传输照片和文字。","NSBonjourServices":["_quicktransfer._tcp."]}
plist("apple/Mac/Info.plist",dict(base,NSPrincipalClass="NSApplication",LSMinimumSystemVersion="14.0",NSHighResolutionCapable=True))
plist("apple/iOS/Info.plist",dict(base,LSRequiresIPhoneOS=True,UILaunchScreen={},UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait","UIInterfaceOrientationLandscapeLeft","UIInterfaceOrientationLandscapeRight"],UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes":False},UIFileSharingEnabled=True,LSSupportsOpeningDocumentsInPlace=True))
plist("apple/ShareHost/Info.plist",dict(base,CFBundleDisplayName="分享检查",LSRequiresIPhoneOS=True,UILaunchScreen={},UIApplicationSceneManifest={"UIApplicationSupportsMultipleScenes":False}))
plist("apple/iOS/QuickTransfer.entitlements",{"com.apple.security.application-groups":["group.com.chongyang.quicktransfer"]})
plist("apple/Share/Info.plist",dict(base,CFBundlePackageType="XPC!",NSExtension={"NSExtensionPointIdentifier":"com.apple.share-services","NSExtensionPrincipalClass":"$(PRODUCT_MODULE_NAME).ShareViewController","NSExtensionAttributes":{"NSExtensionActivationRule":{"NSExtensionActivationSupportsText":True,"NSExtensionActivationSupportsWebURLWithMaxCount":10,"NSExtensionActivationSupportsImageWithMaxCount":100,"NSExtensionActivationSupportsMovieWithMaxCount":10,"NSExtensionActivationSupportsFileWithMaxCount":100}}}))
shared=sorted((ROOT/"apple/Shared").glob("*.swift"))
refs=[]; products=[];targets=[];configs={}
project_id=uid("project")
product_group=uid("products")
main_group=uid("main")
source_refs={}
for path in sorted((ROOT/"apple").rglob("*.swift")):
    relative=str(path.relative_to(ROOT))
    ref=add("file:"+relative,isa="PBXFileReference",lastKnownFileType="sourcecode.swift",path=relative,sourceTree="<group>")
    refs.append(ref);source_refs[relative]=ref
asset_ref=add("assets",isa="PBXFileReference",lastKnownFileType="folder.assetcatalog",path="apple/Assets.xcassets",sourceTree="<group>")
refs.append(asset_ref)

for name,platform,bundle,entry in [("QuickTransferMac","macosx","com.chongyang.quicktransfer.mac","apple/Mac/QuickTransferApp.swift"),("QuickTransferShare","iphoneos","com.chongyang.quicktransfer.ios.share","apple/Share/ShareViewController.swift"),("QuickTransferiOS","iphoneos","com.chongyang.quicktransfer.ios","apple/iOS/QuickTransferApp.swift"),("QuickTransferShareHost","iphoneos","com.chongyang.quicktransfer.sharehost","apple/ShareHost/ShareHost.swift")]:
    extension=name.endswith("Share")
    host=name.endswith("Host")
    target_id=uid(name)
    product=add(name+":product",isa="PBXFileReference",explicitFileType="wrapper.app-extension" if extension else "wrapper.application",includeInIndex="0",path=name+(".appex" if extension else ".app"),sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    sources=[]
    for path in ([] if host else [str(p.relative_to(ROOT)) for p in shared])+[str(p.relative_to(ROOT)) for p in sorted((ROOT/entry).parent.glob("*.swift"))]:
        # Share extensions use UIKit; desktop clipboard APIs are excluded by platform.
        sources.append(add(name+":source:"+path,isa="PBXBuildFile",fileRef=source_refs[path]))
    source_phase=add(name+":sources",isa="PBXSourcesBuildPhase",buildActionMask="2147483647",files=sources,runOnlyForDeploymentPostprocessing="0")
    asset_build=[] if extension else [add(name+":assets",isa="PBXBuildFile",fileRef=asset_ref)]
    phases=[source_phase,add(name+":frameworks",isa="PBXFrameworksBuildPhase",buildActionMask="2147483647",files=[],runOnlyForDeploymentPostprocessing="0"),add(name+":resources",isa="PBXResourcesBuildPhase",buildActionMask="2147483647",files=asset_build,runOnlyForDeploymentPostprocessing="0")]
    dependencies=[]
    if name=="QuickTransferiOS":
        proxy=add("share:proxy",isa="PBXContainerItemProxy",containerPortal=project_id,proxyType="1",remoteGlobalIDString=uid("QuickTransferShare"),remoteInfo="QuickTransferShare")
        dependencies.append(add("share:dependency",isa="PBXTargetDependency",target=uid("QuickTransferShare"),targetProxy=proxy))
        embed_file=add("share:embed",isa="PBXBuildFile",fileRef=uid("QuickTransferShare:product"),settings={"ATTRIBUTES":["RemoveHeadersOnCopy"]})
        phases.append(add("share:phase",isa="PBXCopyFilesBuildPhase",buildActionMask="2147483647",dstPath="",dstSubfolderSpec="13",files=[embed_file],name="Embed Extensions",runOnlyForDeploymentPostprocessing="0"))
    target_configs=[]
    for mode in ["Debug","Release"]:
        settings={"PRODUCT_NAME":name,"PRODUCT_BUNDLE_IDENTIFIER":bundle,"SWIFT_VERSION":"5.0","SDKROOT":platform,"CODE_SIGN_STYLE":"Automatic","DEVELOPMENT_TEAM":TEAM,"CURRENT_PROJECT_VERSION":"1","MARKETING_VERSION":"0.1.0","GENERATE_INFOPLIST_FILE":"NO","SWIFT_OBJC_BRIDGING_HEADER":"$(SRCROOT)/core/include/QuickTransfer.h","HEADER_SEARCH_PATHS":["$(inherited)","$(SRCROOT)/core/include"],"LIBRARY_SEARCH_PATHS":["$(inherited)","$(SRCROOT)/Libraries/$(PLATFORM_NAME)"],"OTHER_LDFLAGS":["$(inherited)","-lquicktransfer","-framework","Security","-framework","SystemConfiguration","-liconv","-lresolv"],"ENABLE_USER_SCRIPT_SANDBOXING":"YES","SWIFT_OPTIMIZATION_LEVEL":"-Onone" if mode=="Debug" else "-O","SWIFT_ACTIVE_COMPILATION_CONDITIONS":"DEBUG" if mode=="Debug" else "","CLANG_ENABLE_MODULES":"YES","ENABLE_HARDENED_RUNTIME":"YES" if platform=="macosx" else "NO"}
        if platform=="macosx": settings.update({"INFOPLIST_FILE":"apple/Mac/Info.plist","MACOSX_DEPLOYMENT_TARGET":"14.0","SUPPORTED_PLATFORMS":"macosx","CODE_SIGN_IDENTITY":"-"})
        else: settings.update({"INFOPLIST_FILE":"apple/Share/Info.plist" if extension else "apple/iOS/Info.plist","IPHONEOS_DEPLOYMENT_TARGET":"17.0","TARGETED_DEVICE_FAMILY":"1,2","SUPPORTED_PLATFORMS":"iphoneos iphonesimulator","CODE_SIGN_ENTITLEMENTS":"apple/iOS/QuickTransfer.entitlements","APPLICATION_EXTENSION_API_ONLY":"YES" if extension else "NO"})
        if not extension:settings["ASSETCATALOG_COMPILER_APPICON_NAME"]="AppIcon"
        if host:
            settings["INFOPLIST_FILE"]="apple/ShareHost/Info.plist"
            for key in ["SWIFT_OBJC_BRIDGING_HEADER","LIBRARY_SEARCH_PATHS","OTHER_LDFLAGS","CODE_SIGN_ENTITLEMENTS"]:settings.pop(key,None)
        target_configs.append(add(name+":"+mode,isa="XCBuildConfiguration",buildSettings=settings,name=mode))
    config_list=add(name+":configs",isa="XCConfigurationList",buildConfigurations=target_configs,defaultConfigurationIsVisible="0",defaultConfigurationName="Release")
    add(name,isa="PBXNativeTarget",buildConfigurationList=config_list,buildPhases=phases,buildRules=[],dependencies=dependencies,name=name,productName=name,productReference=product,productType="com.apple.product-type.app-extension" if extension else "com.apple.product-type.application")
    targets.append(target_id)
test_name="QuickTransferUITests"
test_product=add(test_name+":product",isa="PBXFileReference",explicitFileType="wrapper.cfbundle",includeInIndex="0",path=test_name+".xctest",sourceTree="BUILT_PRODUCTS_DIR")
products.append(test_product)
test_file=add(test_name+":source",isa="PBXBuildFile",fileRef=source_refs["apple/Tests/ShareSmokeTests.swift"])
test_phase=add(test_name+":sources",isa="PBXSourcesBuildPhase",buildActionMask="2147483647",files=[test_file],runOnlyForDeploymentPostprocessing="0")
test_configs=[]
for mode in ["Debug","Release"]:
    test_configs.append(add(test_name+":"+mode,isa="XCBuildConfiguration",buildSettings={"PRODUCT_NAME":test_name,"PRODUCT_BUNDLE_IDENTIFIER":"com.chongyang.quicktransfer.uitests","SWIFT_VERSION":"5.0","SDKROOT":"iphoneos","IPHONEOS_DEPLOYMENT_TARGET":"17.0","TARGETED_DEVICE_FAMILY":"1,2","SUPPORTED_PLATFORMS":"iphoneos iphonesimulator","CODE_SIGN_STYLE":"Automatic","DEVELOPMENT_TEAM":TEAM,"GENERATE_INFOPLIST_FILE":"YES","TEST_TARGET_NAME":"QuickTransferiOS","SWIFT_ACTIVE_COMPILATION_CONDITIONS":"DEBUG","CLANG_ENABLE_MODULES":"YES"},name=mode))
test_list=add(test_name+":configs",isa="XCConfigurationList",buildConfigurations=test_configs,defaultConfigurationIsVisible="0",defaultConfigurationName="Debug")
test_proxy=add(test_name+":proxy",isa="PBXContainerItemProxy",containerPortal=project_id,proxyType="1",remoteGlobalIDString=uid("QuickTransferiOS"),remoteInfo="QuickTransferiOS")
test_dep=add(test_name+":dependency",isa="PBXTargetDependency",target=uid("QuickTransferiOS"),targetProxy=test_proxy)
add(test_name,isa="PBXNativeTarget",buildConfigurationList=test_list,buildPhases=[test_phase],buildRules=[],dependencies=[test_dep],name=test_name,productName=test_name,productReference=test_product,productType="com.apple.product-type.bundle.ui-testing")
targets.append(uid(test_name))
project_configs=[add("project:"+mode,isa="XCBuildConfiguration",buildSettings={"CLANG_ENABLE_OBJC_ARC":"YES","GCC_C_LANGUAGE_STANDARD":"gnu17","COPY_PHASE_STRIP":"NO","DEBUG_INFORMATION_FORMAT":"dwarf","SWIFT_STRICT_CONCURRENCY":"minimal"},name=mode) for mode in ["Debug","Release"]]
project_config=add("project:configs",isa="XCConfigurationList",buildConfigurations=project_configs,defaultConfigurationIsVisible="0",defaultConfigurationName="Release")
objects[product_group]={"isa":"PBXGroup","children":products,"name":"Products","sourceTree":"<group>"}
objects[main_group]={"isa":"PBXGroup","children":refs+[product_group],"sourceTree":"<group>"}
objects[project_id]={"isa":"PBXProject","attributes":{"LastUpgradeCheck":"2700","TargetAttributes":{uid(name):{"DevelopmentTeam":TEAM,"ProvisioningStyle":"Automatic"} for name in ["QuickTransferMac","QuickTransferiOS","QuickTransferShare"]}},"buildConfigurationList":project_config,"compatibilityVersion":"Xcode 14.0","developmentRegion":"zh-Hans","hasScannedForEncodings":"0","knownRegions":["zh-Hans","en","Base"],"mainGroup":main_group,"productRefGroup":product_group,"projectDirPath":"","projectRoot":"","targets":targets}
project=ROOT/"QuickTransfer.xcodeproj";project.mkdir(exist_ok=True)
(project/"project.pbxproj").write_text("// !$*UTF8*$!\n"+render({"archiveVersion":"1","classes":{},"objectVersion":"56","objects":objects,"rootObject":project_id}),encoding="utf-8")
schemes=project/"xcshareddata/xcschemes";schemes.mkdir(parents=True,exist_ok=True)
for name in ["QuickTransferMac","QuickTransferiOS","QuickTransferShareHost"]:
    reference=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name)}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:QuickTransfer.xcodeproj"/>'
    test_action=f'<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(test_name)}" BuildableName="{test_name}.xctest" BlueprintName="{test_name}" ReferencedContainer="container:QuickTransfer.xcodeproj"/></TestableReference></Testables></TestAction>' if name=="QuickTransferiOS" else ""
    (schemes/(name+".xcscheme")).write_text(f'<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>{test_action}<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>',encoding="utf-8")
print("Xcode 工程已生成")


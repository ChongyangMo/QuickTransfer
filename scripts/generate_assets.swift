import AppKit
import Foundation

let root=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("apple/Assets.xcassets")
let folder=root.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
var images:[[String:String]]=[]
func icon(_ size:Int,_ file:String) throws {
    let image=NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    NSColor(srgbRed:0.12,green:0.39,blue:0.93,alpha:1).setFill()
    NSRect(x:0,y:0,width:size,height:size).fill()
    let configuration=NSImage.SymbolConfiguration(pointSize:CGFloat(size)*0.56,weight:.medium)
    let symbol=NSImage(systemSymbolName:"arrow.up.arrow.down",accessibilityDescription:nil)!.withSymbolConfiguration(configuration)!
    let rect=NSRect(x:CGFloat(size)*0.23,y:CGFloat(size)*0.19,width:CGFloat(size)*0.54,height:CGFloat(size)*0.62)
    let white=NSImage(size:symbol.size)
    white.lockFocus();NSColor.white.setFill();NSRect(origin:.zero,size:symbol.size).fill();symbol.draw(at:.zero,from:.zero,operation:.destinationIn,fraction:1);white.unlockFocus()
    white.draw(in:rect)
    image.unlockFocus()
    let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
    try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(file))
}
try icon(1024,"icon-ios.png")
images.append(["filename":"icon-ios.png","idiom":"universal","platform":"ios","size":"1024x1024"])
for size in [16,32,128,256,512] { for scale in [1,2] {
    let name="icon-mac-\(size)-\(scale).png";try icon(size*scale,name)
    images.append(["filename":name,"idiom":"mac","size":"\(size)x\(size)","scale":"\(scale)x"])
} }
try JSONSerialization.data(withJSONObject:["images":images,"info":["author":"xcode","version":1]],options:.prettyPrinted).write(to:folder.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject:["info":["author":"xcode","version":1]]).write(to:root.appendingPathComponent("Contents.json"))
print("应用图标已生成")

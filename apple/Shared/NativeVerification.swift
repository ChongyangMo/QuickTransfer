#if DEBUG
import Foundation
import CryptoKit

@MainActor
final class NativeVerification {
    private weak var service:TransferService?
    private var config:[String:Any]?
    private var log:URL?
    private var step=0
    private var sending=false
    init(service:TransferService) {
        self.service=service
        let args=ProcessInfo.processInfo.arguments
        guard let index=args.firstIndex(of:"--verify-config"),args.indices.contains(index+1) else { return }
        let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let argument=args[index+1]
        let url=argument.hasPrefix("/") ? URL(fileURLWithPath:argument):documents.appendingPathComponent(argument)
        do {
            guard let config=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any] else { throw CocoaError(.fileReadCorruptFile) }
            self.config=config
            log=(config["logPath"] as? String).map{URL(fileURLWithPath:$0)} ?? documents.appendingPathComponent("quicktransfer-verification.jsonl")
            try Data().write(to:log!,options:.atomic)
        } catch { service.error="真机检查配置读取失败：\(error.localizedDescription)" }
    }
    func event(_ value:[String:Any]) {
        guard let config,let service else { return }
        do {
            if let log,value["type"] as? String != "progress" {
                var record=value
                if value["type"] as? String=="received",let path=value["path"] as? String {
                    let input=try FileHandle(forReadingFrom:URL(fileURLWithPath:path))
                    var hash=SHA256()
                    while let bytes=try input.read(upToCount:1024*1024),!bytes.isEmpty { hash.update(data:bytes) }
                    try input.close()
                    record["sha256"]=hash.finalize().map{String(format:"%02x",$0)}.joined()
                }
                var data=try JSONSerialization.data(withJSONObject:record);data.append(10)
                let handle=try FileHandle(forWritingTo:log);try handle.seekToEnd();try handle.write(contentsOf:data);try handle.close()
            }
            let type=value["type"] as? String
            if type=="ready",let host=config["host"] as? String {
                service.command(["action":"probe","host":host,"port":config["port"] as? Int ?? 53317])
            }
            if type=="incoming",let expected=config["receiveFingerprint"] as? String,value["peer"] as? String==expected {
                service.answer(accept:true,remember:false)
            }
            if type=="sent" { sending=false;step += 1 }
            let transfers=config["transfers"] as? [[String:Any]] ?? [config]
            if (type=="devices" || type=="sent"),!sending,step<transfers.count,let expected=config["sendFingerprint"] as? String,service.peers.contains(where:{$0.id==expected}) {
                sending=true
                let transfer=transfers[step]
                var payload:[String:Any]=["action":"send","peer":expected,"id":UUID().uuidString]
                if let text=transfer["text"] as? String { payload["text"]=text }
                if let paths=transfer["paths"] as? [String] {
                    let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                    payload["paths"]=paths.map{$0.hasPrefix("/") ? $0:documents.appendingPathComponent($0).path}
                }
                service.command(payload)
            }
        } catch { service.error="真机检查记录失败：\(error.localizedDescription)" }
    }
}
#endif

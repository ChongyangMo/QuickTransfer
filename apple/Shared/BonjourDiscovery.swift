import Foundation
import Darwin

@MainActor
final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let alias: String
    private let port: UInt16
    private let discovered: (String,UInt16)->Void
    private let browser = NetServiceBrowser()
    private var publisher: NetService?
    private var services: [NetService] = []
    init(alias:String,port:UInt16,discovered:@escaping(String,UInt16)->Void) { self.alias=alias;self.port=port;self.discovered=discovered }
    func start() {
        let publisher=NetService(domain:"local.",type:"_quicktransfer._tcp.",name:alias,port:Int32(port))
        publisher.delegate=self; publisher.publish(); self.publisher=publisher
        browser.delegate=self; browser.searchForServices(ofType:"_quicktransfer._tcp.",inDomain:"local.")
    }
    func stop() { browser.stop();publisher?.stop();services.forEach{$0.stop()};services=[] }
    func refresh() { services.forEach{$0.resolve(withTimeout:3)} }
    func netServiceBrowser(_ browser:NetServiceBrowser,didFind service:NetService,moreComing:Bool) {
        services.append(service);service.delegate=self;service.resolve(withTimeout:3)
    }
    func netServiceBrowser(_ browser:NetServiceBrowser,didRemove service:NetService,moreComing:Bool) { services.removeAll{$0==service} }
    func netServiceDidResolveAddress(_ sender:NetService) {
        guard sender.port>0,sender.port<=65535 else { return }
        for data in sender.addresses ?? [] {
            let host:String?=data.withUnsafeBytes { raw in
                guard let address=raw.bindMemory(to:sockaddr.self).baseAddress,Int32(address.pointee.sa_family)==AF_INET else { return nil }
                var buffer=[CChar](repeating:0,count:Int(NI_MAXHOST))
                guard getnameinfo(address,socklen_t(data.count),&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST)==0 else { return nil }
                return String(cString:buffer)
            }
            if let host { discovered(host,UInt16(sender.port));return }
        }
    }
    func netService(_ sender:NetService,didNotPublish errorDict:[String:NSNumber]) {
        TransferService.shared.error="设备广播失败：\(errorDict)"
    }
    func netServiceBrowser(_ browser:NetServiceBrowser,didNotSearch errorDict:[String:NSNumber]) {
        TransferService.shared.error="发现设备失败：\(errorDict)"
    }
}

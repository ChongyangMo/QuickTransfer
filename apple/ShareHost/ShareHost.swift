import SwiftUI

@main
struct ShareHost:App {
    var body:some Scene {
        WindowGroup {
            let photo=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("real-photo.png")
            ShareLink(item:photo) { Label("分享照片",systemImage:"square.and.arrow.up") }.accessibilityIdentifier("share-real-photo")
        }
    }
}

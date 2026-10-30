import XCTest

final class ShareSmokeTests:XCTestCase {
    func testShareReceivedPhoto() {
        continueAfterFailure=false
        let app=XCUIApplication(bundleIdentifier:"com.chongyang.quicktransfer.sharehost")
        app.launchArguments=[];app.launch()
        let share=app.buttons["share-real-photo"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout:12),"没有收到过的真实照片")
        share.tap()
        let quickTransfer=app.cells.containing(.staticText,identifier:"快传").firstMatch
        let activities=app.collectionViews["activityCollectionView"].firstMatch
        XCTAssertTrue(activities.waitForExistence(timeout:10),app.debugDescription)
        for _ in 0..<8 {
            if quickTransfer.exists && quickTransfer.isHittable { break }
            if app.cells["更多"].exists && app.cells["更多"].isHittable { app.cells["更多"].tap();break }
            activities.coordinate(withNormalizedOffset:CGVector(dx:0.87,dy:0.60)).press(forDuration:0.05,thenDragTo:activities.coordinate(withNormalizedOffset:CGVector(dx:0.12,dy:0.60)))
        }
        for _ in 0..<5 {
            if quickTransfer.exists && quickTransfer.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(quickTransfer.waitForExistence(timeout:5),app.debugDescription)
        quickTransfer.tap()
        let mac=app.buttons["chongyang的Mac mini"].firstMatch
        XCTAssertTrue(mac.waitForExistence(timeout:12),app.debugDescription)
        mac.tap()
        let send=app.buttons["发送"].firstMatch
        XCTAssertTrue(send.isEnabled,"照片尚未导入")
        send.tap()
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"hittable == true"),object:share)
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:20),.completed,"分享后没有返回主界面")
    }
}

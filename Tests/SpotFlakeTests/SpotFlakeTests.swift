import XCTest
@testable import SpotFlake

final class SpotFlakeTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd ZZZ"
		print("epoch of custom date:", SpotFlake.Time(formatter.date(from: "2018-01-01 UTC")!).flakeTime)
		print("epoch of now:", SpotFlake.Time(Date()).flakeTime)
		print("current epoch:", SpotFlake.epoch)
	}
	
    func testGenerate() {
		let count = 1010
		let node = SpotFlake.Node(node: 1)!
		var ids: Set<Int64> = []
		for _ in 0..<count {
			ids.insert(node.generate())
		}
		XCTAssert(ids.count == count)
    }
	
	func testClockTime() {
		let timeOver = SpotFlake.Time(seconds: 3, nano: -2_123_456_789)
		let timeResult = SpotFlake.Time(seconds: 0, nano: 876_543_211)
		XCTAssert(timeOver == timeResult)
		
		let date = Date()
		let now = SpotFlake.Time(date)
		let date2 = now.date
		print(date.timeIntervalSince1970 - date2.timeIntervalSince1970)
	}

    static var allTests = [
        ("testGenerate", testGenerate),
		("testClockTime", testClockTime),
    ]
}

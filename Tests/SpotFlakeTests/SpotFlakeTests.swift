import XCTest
@testable import SpotFlake

final class SpotFlakeTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd ZZZ"
		print("epoch of custom date:", SpotFlake.Node.flakeTimestamp(Time(formatter.date(from: "2018-01-01 UTC")!)))
		print("epoch of now:", SpotFlake.Node.flakeTimestamp(Time(Date())))
		print("current epoch:", SpotFlake.epoch)
	}
	
    func testGenerate() {
		let count = 1010
		let node = SpotFlake.Node(node: 1)!
		var ids: Set<SpotFlake.ID> = []
		for _ in 0..<count {
			ids.insert(node.generate())
		}
		XCTAssert(ids.count == count)
		
		let id = SpotFlake.ID(324932740761784320)
		let b36 = "2gvf1kdqtc00"
		let b64 = "MzI0OTMyNzQwNzYxNzg0MzIw"
		XCTAssert(id.base36 == b36)
		XCTAssert(id.base64 == b64)
		XCTAssert(id == SpotFlake.ID(base36: b36))
		XCTAssert(id == SpotFlake.ID(base64: b64))
    }
}

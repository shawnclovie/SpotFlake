import XCTest
@testable import SpotFlake

final class SpotFlakeTests: XCTestCase {
	
	override func setUp() {
		super.setUp()
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd ZZZ"
		print("epoch of custom date:", Flake.Node.flakeTimestamp(Time(formatter.date(from: "2018-01-01 UTC")!)))
		print("epoch of now:", Flake.Node.flakeTimestamp(Time(Date())))
		print("current epoch:", Flake.epoch)
	}
	
    func testGenerate() {
		let count = 1010
		let node = Flake.Node(node: 1)!
		var ids: Set<Flake.ID> = []
		for _ in 0..<count {
			ids.insert(node.generate())
		}
		XCTAssert(ids.count == count)
		
		let id = Flake.ID(324932740761784320)
		let b36 = "2gvf1kdqtc00"
		let b64 = "MzI0OTMyNzQwNzYxNzg0MzIw"
		XCTAssert(id.base36 == b36)
		XCTAssert(id.base64 == b64)
		XCTAssert(id == Flake.ID(base36: b36))
		XCTAssert(id == Flake.ID(base64: b64))
    }
	
	func testGenerateBenchmark() {
		let opt = XCTMeasureOptions()
		opt.iterationCount = 10000
		let node = Flake.Node(node: 1)!
		var ids: [Flake.ID] = []
		self.measure(options: opt) {
			let id = node.generate()
			ids.append(id)
		}
		print(ids)
	}
}

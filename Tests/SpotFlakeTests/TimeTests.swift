import XCTest
@testable import SpotFlake

final class TimeTests: XCTestCase {
    func testParseTimeDuration() throws {
		struct Item {
			let source: String
			let defaultUnit: String?
			let match: TimeDuration
			
			init(_ src: String, defaultUnit: String? = nil, match: TimeDuration, export: String? = nil) {
				source = src
				self.defaultUnit = defaultUnit
				self.match = match
			}
		}
		let items: [Item] = [
			.init("1d2h3m0s5ms", match: .components(days: 1, hours: 2, minutes: 3, milliseconds: 5)),
			.init("+1d", match: .components(days: 1)),
			.init("-1d", match: .components(days: -1)),
			.init("", match: .zero),
			.init("0", match: .zero),
			.init("300", match: .components(seconds: 300)),
			.init("300", defaultUnit: "ms", match: .components(milliseconds: 300)),
			.init("1.5h", match: .components(hours: 1, minutes: 30)),
			.init(".5h", match: .components(minutes: 30)),
			.init("1d1d", match: .components(days: 2)),
		]
		for item in items {
			let dur = TimeDuration.parse(item.source, defaultUnit: item.defaultUnit ?? TimeDuration.defaultParseUnit)
			XCTAssertEqual(dur, item.match)
			let reparsed = TimeDuration.parse(dur.description)
			XCTAssertEqual(reparsed, dur)
		}
}
	
	func testTime() {
		let timeOver = Time(seconds: 3, nano: -2_123_456_789)
		let timeResult = Time(seconds: 0, nano: 876_543_211)
		XCTAssert(timeOver == timeResult)
		
		let t1 = Time(year: 2020, month: .october, day: 1, hour: 0, minute: 10, second: 10, nano: 2, offset: 0)
		XCTAssertEqual(t1.clock, .init(hour: 0, minute: 10, second: 10))
		XCTAssertEqual(t1.add(years: 1, months: 1, days: 1).date,
					   .init(year: 2021, month: .november, day: 2))
		XCTAssertEqual(t1.add(years: 1, months: 1, days: 100).date,
					   .init(year: 2022, month: .february, day: 9))
	}
}

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
		XCTAssertEqual(t1.weekday, .thursday)
		XCTAssertEqual(t1.weekday.shortName, "Thu")
		XCTAssertEqual(t1.weekday.name, "Thursday")
		let te = Time(year: 20221014, month: 0, day: 0, hour: 0, minute: 0, second: 0, nano: 0, offset: 0)
		print(te.asDate)
	}

	func testTimeParser() {
		let texts = [
			"0001-01-01T00:00:00Z",
			"2020112-4-2T13:00:03Z", // RFC3339
			"2022-10-11",
			"2022-10-11 13:43:15.324 +08:00", // from postgres
			"2022-10-11 13:43:15 +0000", // from postgres
			"2022-10-11 13:43:15 +0800", // from postgres
			"2022-10-11 13:43:15 +08:00", // from postgres
			"2020-11-2T13:00:03+0200", // RFC3339
			"2020-11-2T13:00:03Z", // RFC3339
			"2020-11-2T13:00:03.366Z", // RFC3339
		]
		let layout = TimeLayout.rfc3339Millisecond
		for text in texts {
			let time = Time.parse(date: text)
			print("   \(text)\n>> \(time.map({ layout.format($0) }) ?? "")")
		}
	}
	
	func testTimeFormat() {
		let time = Time(year: 2020, month: .october, day: 1, hour: 13, minute: 10, second: 10, nano: 31_314_622, offset: 28800)
		for layout in [
			.ansiC,
			.rfc3339,
			.rfc3339Millisecond,
			.rfc3339Nanosecond,
			.rfc822,
			.rfc822Z,
			.rfc850,
			.init(components: [.hour(.ampm), .string(":"), .minute, .ampm]),
		] as [TimeLayout] {
			print(layout.format(time))
		}
		measure {
			_ = TimeLayout.rfc3339Millisecond.format(time)
		}
	}
}

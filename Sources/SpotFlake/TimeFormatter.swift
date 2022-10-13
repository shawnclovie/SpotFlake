//
//  TimeFormatter.swift
//  
//
//  Created by Shawn Clovie on 12/10/2022.
//

import Foundation

public struct TimeFormatter {
	public static let hyphenDateFormat = "%d-%d-%dT%d:%d:%f%d:%dZ"

	public let format: String
	
	public init(format: String = Self.hyphenDateFormat) {
		self.format = format
	}
	
	private struct Parser {
		var parseCount = 0
		var year = 0, month = 0, day = 0
		var hour = 0, minute = 0
		var second: Double = 0.0
		var hourOffset = 0, minuteOffset = 0
		
		mutating func scan(_ string: String) {
			let scanner = Scanner(string: string)
			guard scanner.scanInt(&year) else { return }
			parseCount += 1
			_ = scanner.scanCharacter()
			guard scanner.scanInt(&month) else { return }
			parseCount += 1
			_ = scanner.scanCharacter()
			guard scanner.scanInt(&day) else { return }
			parseCount += 1
			_ = scanner.scanCharacter()
			guard scanner.scanInt(&hour) else { return }
			parseCount += 1
			_ = scanner.scanCharacter()
			guard scanner.scanInt(&minute) else { return }
			parseCount += 1
			_ = scanner.scanCharacter()
			guard let sec = scanner.scanDouble(representation: .decimal) else { return }
			parseCount += 1
			second = sec
			guard scanner.scanInt(&hourOffset) else { return }
			parseCount += 1
			guard scanner.scanInt(&minuteOffset) else { return }
			parseCount += 1
		}
	}

	public func parse(date string: String) -> Time? {
		var string = string
		if let range = string.range(of: " ") {
			string.replaceSubrange(range, with: "T")
		}
		var parser = Parser()
		parser.scan(string)
		guard parser.parseCount >= 3 else {
			return nil
		}
		// Work out the timezone offset
		let offset: Int
		if parser.parseCount > 6 && (parser.hourOffset != 0 || parser.minuteOffset != 0) {
			let isMinusOffset = parser.hourOffset < 0
			var hOffset = abs(parser.hourOffset)
			if parser.parseCount == 7 && hOffset > 100 {
				parser.minuteOffset = hOffset - (hOffset / 100 * 100)
				hOffset /= 100
			}
			offset = (hOffset * 3600 + parser.minuteOffset * 60) * (isMinusOffset ? -1 : 1)
		} else {
			offset = 0
		}
		let sec = Int(parser.second)
		let nano = Int((parser.second - Double(sec)) * 1e9)
		return Time(year: parser.year, month: parser.month, day: parser.day,
					hour: parser.hour, minute: parser.minute,
					second: sec, nano: nano, offset: offset)
	}
	
	public struct WriteOption: OptionSet {
		/// Separate date and time with SPACE instead `"T"`.
		public static let spaceSeparator = Self(rawValue: 1)

		/// Do not write timezone part (Z or +0800).
		public static let noTimeZone = Self(rawValue: 2)

		public static let withMilliseconds = Self(rawValue: 4)

		public let rawValue: Int8
		
		public init(rawValue: Int8) {
			self.rawValue = rawValue
		}
	}
	
	public func format(_ time: Time, options: WriteOption = []) -> String {
		let date = time.date
		let clock = time.clock
		let separator = options.contains(.spaceSeparator) ? " " : "T"
		var s = String(format: "%04d-%02d-%02d%@%02d:%02d:%02d",
					   date.year, date.month.rawValue, date.day,
					   separator, clock.hour, clock.minute, clock.second)
		if options.contains(.withMilliseconds) && clock.millisecond > 0 {
			s += .init(format: ".%03d", clock.millisecond)
		}
		if !options.contains(.noTimeZone) {
			s += formatOffset(time)
		}
		return s
	}
	
	public func formatOffset(_ time: Time) -> String {
		if time.offset == 0 {
			return "Z"
		}
		let offset = abs(time.offset) / 60
		let hOffset = offset / 60
		let mOffset = offset % 60
		let symbol = time.offset < 0 ? "-" : "+"
		return String(format: "%@%02d%02d", symbol, hOffset, mOffset)
	}
}

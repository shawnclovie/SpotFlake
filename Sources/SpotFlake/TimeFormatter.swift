//
//  TimeFormatter.swift
//  
//
//  Created by Shawn Clovie on 12/10/2022.
//

import Foundation

public struct TimeLayout {
	/// `Mon Jan _2 15:04:05 2006`
	public static let ansiC = Self(dateLeadingZero: false, components: [
		.weekday(.short), .string(" "),
		.month(.short), .string(" "),
		.day, .string(" "),
		.hour(), .string(":"), .minute, .string(":"), .second, .string(" "),
		.year(.full),
	])
	
	/// ISO8601 or RFC3339: `2006-01-02T15:04:05-0700`
	public static let rfc3339 = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
		.string("T"),
		.hour(), .string(":"), .minute, .string(":"), .second,
		.timezone(colon: true),
	])

	public static let rfc3339Millisecond = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
		.string("T"),
		.hour(), .string(":"), .minute, .string(":"), .second,
		.string("."), .millisecond,
		.timezone(colon: true),
	])

	public static let rfc3339Nanosecond = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
		.string("T"),
		.hour(), .string(":"), .minute, .string(":"), .second,
		.string("."), .nanosecond,
		.timezone(colon: true),
	])
	
	/// `02 Jan 06 15:04 MST`
	public static let rfc822 = Self(components: [
		.year(.full), .string(" "), .month(.short), .string(" "), .day,
		.string(" "), .hour(), .string(":"), .minute, .string(" MST"),
	])
	
	/// `02 Jan 06 15:04 -07:00`
	public static let rfc822Z = Self(components: [
		.year(.full), .string(" "), .month(.short), .string(" "), .day,
		.string(" "), .hour(), .string(":"), .minute, .timezone(),
	])

	/// `Monday, 02-Jan-06 15:04:05 MST`
	public static let rfc850 = Self(components: [
		.weekday(.name), .string(", "),
		.year(.inCentry), .string("-"), .month(.short), .string("-"), .day,
		.string(" "), .hour(), .string(":"), .minute, .string(":"), .second,
		.string(" MST"),
	])

	/// `2006-01-02`
	public static let date = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
	])

	/// `15:04:05`
	public static let time = Self(components: [
		.hour(), .string(":"), .minute, .string(":"), .second,
	])

	/// `2006-01-02 15:04:05`
	public static let datetime = Self(components: [
		.year(.full), .string("-"), .month(.digital), .string("-"), .day,
		.string(" "),
		.hour(), .string(":"), .minute, .string(":"), .second,
	])
	
	public enum Component {
		case string(String)
		case year(YearStyle)
		case month(MonthStyle)
		case day
		case weekday(WeekdayStyle)
		case ampm
		case hour(HourStyle = .h24)
		case minute
		case second
		case millisecond
		case nanosecond
		case timezone(gmt: String = "Z", colon: Bool = false)
	}
	
	public enum YearStyle {
		case full, inCentry

		var digitCount: Int {
			switch self {
			case .full:		return 4
			case .inCentry:	return 2
			}
		}
	}
	
	public enum MonthStyle {
		case digital, name, short
	}
	
	public enum WeekdayStyle {
		case name, short
	}
	
	public enum HourStyle {
		case h24, ampm
		
		func hour(_ hour: Int) -> Int {
			switch self {
			case .h24:
				return hour
			case .ampm:
				return hour > 12 ? hour - 12 : hour
			}
		}
	}

	public var dateLeadingZero: Bool
	public var timeLeadingZero: Bool
	public var components: [Component]
	
	public init(dateLeadingZero: Bool = true, timeLeadingZero: Bool = true, components: [Component]) {
		self.dateLeadingZero = dateLeadingZero
		self.timeLeadingZero = timeLeadingZero
		self.components = components
	}
	
	public func format(_ time: Time) -> String {
		var str = ""
		let date = time.date
		let clock = time.clock
		for component in components {
			switch component {
			case .string(let s):
				str += s
			case .year(let style):
				let v: Int
				switch style {
				case .full:
					v = date.year
				case .inCentry:
					v = date.year - date.year / 100 * 100
				}
				let s = "\(v)"
				let leadingZeroCount = style.digitCount - s.count
				if leadingZeroCount > 0 {
					str += String(repeating: "0", count: leadingZeroCount) + s
				} else {
					str += s
				}
			case .month(let style):
				switch style {
				case .digital:
					str += dateLeadingZero ? Self.format(Int(date.month.rawValue), leadingZero: 2) : "\(date.month.rawValue)"
				case .name:
					str += date.month.name
				case .short:
					str += date.month.shortName
				}
			case .day:
				str += dateLeadingZero ? Self.format(date.day, leadingZero: 2) : "\(date.day)"
			case .weekday(let style):
				let wd = time.weekday
				switch style {
				case .name:
					str += wd.name
				case .short:
					str += wd.shortName
				}
			case .ampm:
				str += clock.hour >= 12 ? "PM" : "AM"
			case .hour(let style):
				let hour = style.hour(clock.hour)
				str += timeLeadingZero ? Self.format(hour, leadingZero: 2) : "\(hour)"
			case .minute:
				str += timeLeadingZero ? Self.format(clock.minute, leadingZero: 2) : "\(clock.minute)"
			case .second:
				str += timeLeadingZero ? Self.format(clock.second, leadingZero: 2) : "\(clock.second)"
			case .millisecond:
				let clock = time.clock
				str += Self.format(clock.millisecond, leadingZero: 3)
			case .nanosecond:
				str += Self.format(Int(time.nanoseconds), leadingZero: 9)
			case .timezone(let gmt, let colon):
				str += Self.formatOffset(time.offset, zero: gmt, colon: colon)
			}
		}
		return str
	}
	
	public var dateFormat: String {
		var str = ""
		for component in components {
			switch component {
			case .string(let s):
				str += s
			case .year(let style):
				switch style {
				case .full:
					str += "yyyy"
				case .inCentry:
					str += "yy"
				}
			case .month(let style):
				switch style {
				case .digital:
					str += dateLeadingZero ? "MM" : "M"
				case .name:
					str += "MMMM"
				case .short:
					str += "MMM"
				}
			case .day:
				str += dateLeadingZero ? "dd" : "d"
			case .weekday(let style):
				switch style {
				case .name:
					str += "E"
				case .short:
					str += "EEE"
				}
			case .ampm:
				str += "a"
			case .hour(_):
				str += timeLeadingZero ? "HH" : "H"
			case .minute:
				str += timeLeadingZero ? "mm" : "m"
			case .second:
				str += timeLeadingZero ? "ss" : "ss"
			case .millisecond:
				str += "SSS"
			case .nanosecond:
				break
			case .timezone(_, let colon):
				str += colon ? "XXX" : "XX"
			}
		}
		return str
	}
	
	static func format(_ number: Int, leadingZero: UInt8) -> String {
		let str = "\(number)"
		let zeroLen = Int(leadingZero) - str.count
		return zeroLen > 0 ? String(repeating: "0", count: zeroLen) + str : str
	}
	
	static func formatOffset(_ offset: Int, zero: String = "Z", colon: Bool) -> String {
		if offset == 0 {
			return zero
		}
		let _offset = abs(offset) / 60
		let hOffset = _offset / 60
		let mOffset = _offset % 60
		let symbol = offset < 0 ? "-" : "+"
		return String(format: "%@%02d\(colon ? ":" : "")%02d", symbol, hOffset, mOffset)
	}
}

extension Time {
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

	public static func parse(date string: String) -> Time? {
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
}

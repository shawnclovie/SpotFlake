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

	public func parse(date string: String) -> Time? {
		let year = UnsafeMutablePointer<Int>.allocate(capacity: 1)
		let month = UnsafeMutablePointer<Int>.allocate(capacity: 1)
		let day = UnsafeMutablePointer<Int>.allocate(capacity: 1)
		let hour = UnsafeMutablePointer<Int>.allocate(capacity: 1)
		let minute = UnsafeMutablePointer<Int>.allocate(capacity: 1)
		let second = UnsafeMutablePointer<Float>.allocate(capacity: 1)
		let hourOffset = UnsafeMutablePointer<Int>.allocate(capacity: 1)
		let minuteOffset = UnsafeMutablePointer<Int>.allocate(capacity: 1)

		var string = string
		if let range = string.range(of: " ") {
			string.replaceSubrange(range, with: "T")
		}
		let parseCount = withVaList([
			year, month, day, hour, minute, second,
			hourOffset, minuteOffset,
		], { pointer in
			vsscanf(string, format, pointer)
		})
		guard parseCount >= 3 else {
			return nil
		}
		// Work out the timezone offset
		let offset: Int
		if parseCount > 6 && (hourOffset.pointee != 0 || minuteOffset.pointee != 0) {
			let isMinusOffset = hourOffset.pointee < 0
			var hOffset = abs(hourOffset.pointee)
			if parseCount == 7 && hOffset > 100 {
				minuteOffset.pointee = hOffset - (hOffset / 100 * 100)
				hOffset /= 100
			}
			offset = (hOffset * 3600 + minuteOffset.pointee * 60) * (isMinusOffset ? -1 : 1)
		} else {
			offset = 0
		}
		let sec = Int(second.pointee)
		let nano = Int((second.pointee - Float(sec)) * 1e9)
		return Time(year: year.pointee, month: month.pointee, day: day.pointee,
					hour: hour.pointee, minute: minute.pointee,
					second: sec, nano: nano, offset: offset)
	}
	
	public func format(_ time: Time) -> String {
		let offsetSuffix = formatOffset(time)
		let comps = time.date
		return String(format: "%04d-%02d-%02dT%02d:%02d:%02d%@",
					  comps.year, comps.month.rawValue, comps.day,
					  time.hour, time.minute, time.second, offsetSuffix)
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

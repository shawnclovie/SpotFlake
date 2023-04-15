//
//  Clock.swift
//  SpotFlake
//
//  Created by Shawn Clovie on 18/10/2018.
//

import Foundation
#if os(Linux)
	import Glibc
	private typealias CTimeSpec = timespec
#elseif os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
	import Darwin
	private func mach_task_self() -> mach_port_t {
		return mach_task_self_
	}

	private typealias CTimeSpec = mach_timespec_t
#endif

public struct Time: Sendable {
	public static var zero: Self { .init(seconds: 0, nano: 0, offset: 0) }
	
	public static var utc: Self { .init(offset: 0) }
	
	public static var local: Self {
		.init(offset: TimeZone.current.secondsFromGMT())
	}
	
	/// Seconds since `0001-01-01`
	fileprivate let seconds: Int64
	
	/// Part of time that less than 1 second.
	public let nanoseconds: Int32
	
	/// Offset seconds to GMT.
	public let offset: Int

	public init(unix seconds: Int64, nano: Int64, offset: Int = 0) {
		var sec = seconds
		var nano = nano
		if nano < 0 || nano >= TimeDuration.nanosecondsPerSecond {
			let n = nano / TimeDuration.nanosecondsPerSecond
			sec += n
			nano -= n * TimeDuration.nanosecondsPerSecond
			if nano < 0 {
				nano += TimeDuration.nanosecondsPerSecond
				sec -= 1
			}
		}
		self.init(seconds: sec + unixToInternal, nano: nano, offset: offset)
	}

	public init(unixMilli: Int64, offset: Int = 0) {
		self.init(unix: unixMilli / 1000,
		          nano: (unixMilli % 1000) * 1_000_000, offset: offset)
	}

	public init(unixMicro: Int64, offset: Int = 0) {
		self.init(unix: unixMicro / 1_000_000,
		          nano: (unixMicro % 1_000_000) * 1000, offset: offset)
	}

	public init(unixNano: Int64, offset: Int = 0) {
		self.init(unix: unixNano / TimeDuration.nanosecondsPerSecond,
		          nano: unixNano % TimeDuration.nanosecondsPerSecond,
				  offset: offset)
	}

	public init(seconds: Int64, nano: Int64, offset: Int = 0) {
		(self.seconds, nanoseconds) = normalized(seconds: seconds, nano: nano)
		self.offset = offset
	}
	
	/// Time for now without timezone.
	public init() {
		self.init(offset: 0)
	}

	/// Time for now.
	public init(offset: Int) {
		var c_timespec = CTimeSpec(tv_sec: 0, tv_nsec: 0)
		var retval: CInt = -1

		#if os(Linux)
			// use CLOCK_MONOTONIC as system clock
			retval = clock_gettime(CLOCK_REALTIME, &c_timespec)
		#elseif os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
			var clockName: clock_serv_t = 0
			// use SYSTEM_CLOCK as system clock
			retval = host_get_clock_service(mach_host_self(), CALENDAR_CLOCK, &clockName)
			if retval == 0 {
				retval = clock_get_time(clockName, &c_timespec)
				_ = mach_port_deallocate(mach_task_self(), clockName)
			}
		#endif
		if retval == 0 {
			self.init(unix: Int64(c_timespec.tv_sec),
			          nano: Int64(c_timespec.tv_nsec), offset: offset)
		} else {
			self.init(Date(), offset: offset)
		}
	}

	public init(_ date: Date, offset: Int = 0) {
		let sec = date.timeIntervalSince1970
		self.init(unix: Int64(sec),
		          nano: Int64((sec - floor(sec)) * TimeInterval(TimeDuration.nanosecondsPerSecond)),
		          offset: offset)
	}

	public init(year: Int, month: Month, day: Int,
	            hour: Int = 0, minute: Int = 0, second: Int = 0, nano: Int = 0,
				offset: Int = 0)
	{
		self.init(year: year, month: month.index + 1,
		          day: day, hour: hour, minute: minute, second: second, nano: nano,
		          offset: offset)
	}

	public init(year: Int, month: Int, day: Int,
	            hour: Int = 0, minute: Int = 0, second: Int = 0, nano: Int = 0,
				offset: Int = 0)
	{
		// Normalize month, overflowing into year.
		let (year, monthIndex) = normalized(max(year, absoluteZeroYear), month - 1, base: 12)
		let month = Month(index: monthIndex)

		// Normalize nsec, sec, min, hour, overflowing into day.
		var (day, hour, min, sec, nsec) = (day, hour, minute, second, nano)
		(sec, nsec) = normalized(second, nano, base: 1_000_000_000)
		(min, sec) = normalized(minute, sec, base: 60)
		(hour, min) = normalized(hour, min, base: 60)
		(day, hour) = normalized(day, hour, base: 24)

		// Compute days since the absolute epoch.
		var d = Self.daysSinceEpoch(year)

		// Add in days before this month.
		d += UInt64(daysBefore[month.index])
		if Self.isLeapYear(year), month.rawValue >= Month.march.rawValue {
			d += 1 // February 29
		}

		// Add in days before today.
		if day > 0 {
			d += UInt64(day - 1)
		}
		// Add in time elapsed today.
		var ns = d * UInt64(secondsPerDay)
		ns += UInt64(hour * secondsPerHour + min * secondsPerMinute + sec)
		var unix = Int64(exactly: ns) ?? unixToInternal
		unix += (absoluteToInternal + internalToUnix)
		if offset != 0 {
			unix -= Int64(offset)
		}
		self.init(unix: unix, nano: Int64(nsec), offset: offset)
	}

	public func `in`(zone: TimeZone) -> Time {
		.init(seconds: seconds, nano: Int64(nanoseconds), offset: zone.secondsFromGMT())
	}

	public var withUTC: Time {
		.init(seconds: seconds, nano: Int64(nanoseconds), offset: 0)
	}

	public var withLocal: Time {
		.init(seconds: seconds, nano: Int64(nanoseconds), offset: TimeZone.current.secondsFromGMT())
	}

	public var asDate: Date {
		Date(timeIntervalSince1970: TimeInterval(
			unixSeconds +
				Int64(nanoseconds) / TimeDuration.nanosecondsPerSecond))
	}

	public func add(years: Int, months: Int, days: Int) -> Time {
		let dates = date
		let clocks = clock
		return .init(year: dates.year + years,
		             month: dates.month.index + 1 + months,
		             day: dates.day + days,
		             hour: clocks.hour, minute: clocks.minute, second: clocks.second,
		             nano: Int(nanoseconds),
					 offset: offset)
	}
}

public extension Time {
	var unixSeconds: Int64 { seconds + internalToUnix }

	var unixMilliseconds: Int64 {
		unixSeconds * 1000 + Int64(nanoseconds) / 1_000_000
	}

	var unixMicroseconds: Int64 {
		unixSeconds * 1000 + Int64(nanoseconds) / 1000
	}

	var unixNanoseconds: Int64 {
		unixSeconds * TimeDuration.nanosecondsPerSecond + Int64(nanoseconds)
	}

	var isZero: Bool { seconds == 0 && nanoseconds == 0 }

	var date: DateComponents { dateComponents(full: true) }

	var clock: ClockComponents {
		Self.clockComponents(nanosecondsInZone, nanoseconds: nanoseconds)
	}

	var year: Int { dateComponents(full: false).year }

	var month: Month { dateComponents(full: true).month }

	var day: Int { dateComponents(full: true).day }

	var yearDay: Int { dateComponents(full: false).yearDay }
	
	var weekday: Weekday { Self.absWeekday(nanosecondsInZone) }

	var hour: Int {
		Int(nanosecondsInZone % UInt64(secondsPerDay)) / secondsPerHour
	}

	var minute: Int {
		Int(nanosecondsInZone % UInt64(secondsPerHour)) / secondsPerMinute
	}

	var second: Int { Int(nanosecondsInZone % UInt64(secondsPerMinute)) }
}

extension Time: Equatable, Comparable {
	public func isEqual(_ other: Self) -> Bool {
		seconds == other.seconds && nanoseconds == other.nanoseconds
	}

	@inlinable
	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.isEqual(rhs)
	}

	public func isBefore(_ other: Self) -> Bool {
		seconds < other.seconds || (seconds == other.seconds && nanoseconds < other.nanoseconds)
	}

	@inlinable
	public static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.isBefore(rhs)
	}

	public func after(_ dur: TimeDuration) -> Self {
		var dsec = dur.nanoseconds / TimeDuration.nanosecondsPerSecond
		var nsec = Int64(nanoseconds) + dur.nanoseconds % TimeDuration.nanosecondsPerSecond
		if nsec >= TimeDuration.nanosecondsPerSecond {
			dsec += 1
			nsec -= TimeDuration.nanosecondsPerSecond
		} else if nsec < 0 {
			dsec -= 1
			nsec += TimeDuration.nanosecondsPerSecond
		}
		let (sec, _) = seconds.addingReportingOverflow(dsec)
		return .init(seconds: sec, nano: nsec, offset: offset)
	}

	@inlinable
	public func before(_ dur: TimeDuration) -> Self {
		after(-dur)
	}

	@inlinable
	public static func + (t: Self, dur: TimeDuration) -> Self {
		t.after(dur)
	}

	@inlinable
	public static func - (t: Self, dur: TimeDuration) -> Self {
		t.after(-dur)
	}

	public func diff(_ other: Self) -> TimeDuration {
		let (d, _) = ((seconds - other.seconds) * TimeDuration.nanosecondsPerSecond)
			.addingReportingOverflow(Int64(nanoseconds - other.nanoseconds))
		let dur = TimeDuration(d)
		if other.after(dur) == self {
			return dur
		}
		return .init(self < other ? .min : .max)
	}

	public static func - (lhs: Self, rhs: Self) -> TimeDuration {
		lhs.diff(rhs)
	}

	public static func += (lhs: inout Self, rhs: TimeDuration) {
		lhs = lhs.after(rhs)
	}

	public static func -= (lhs: inout Self, rhs: TimeDuration) {
		lhs = lhs.after(-rhs)
	}
}

extension Time: Strideable {
	public typealias Stride = Int64
	
	public func distance(to other: Time) -> Int64 {
		other.diff(self).nanoseconds
	}
	
	public func advanced(by n: Int64) -> Time {
		after(.init(n))
	}
}

extension Time {
	public struct DateComponents: Equatable {
		public var year: Int
		public var month: Month
		public var day: Int
		public var yearDay: Int

		public init(year: Int, month: Month, day: Int, yearDay: Int = 0) {
			self.year = year
			self.month = month
			self.day = day
			self.yearDay = yearDay
		}

		public static func == (lhs: Self, rhs: Self) -> Bool {
			lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
		}
	}

	public struct ClockComponents: Equatable {
		public var hour: Int
		public var minute: Int
		public var second: Int
		public var millisecond: Int

		public init(hour: Int, minute: Int, second: Int, millisecond: Int = 0) {
			self.hour = hour
			self.minute = minute
			self.second = second
			self.millisecond = millisecond
		}
	}

	public enum Month: UInt8, Equatable, CaseIterable {
		case january = 1
		case february
		case march
		case april
		case may
		case june
		case july
		case august
		case september
		case october
		case november
		case december

		/// Make `Month` with carousel `index`.
		public init(index: Int) {
			var index = index % 12
			if index < 0 {
				index += 12
			}
			self.init(rawValue: UInt8(index) + 1)!
		}

		public init?(shortName: String) {
			guard let index = Self.shortNames.firstIndex(of: shortName) else {
				return nil
			}
			self = Self.allCases[index]
		}

		public init?(named name: String) {
			guard let index = Self.names.firstIndex(of: name) else {
				return nil
			}
			self = Self.allCases[index]
		}

		public var index: Int {
			Int(rawValue - 1)
		}
		
		public var name: String {
			Self.names[Int(rawValue) - 1]
		}
		
		public var shortName: String {
			Self.shortNames[Int(rawValue) - 1]
		}

		/// Calculate month with advanced index. `1` means next month.
		public func advanced(_ offset: Int) -> Self {
			guard offset != 0 else {
				return self
			}
			return .init(index: index + offset)
		}

		static let names = [
			"January", "February", "March", "April",
			"May", "June", "July", "August",
			"September", "October", "November", "December",
		]

		static let shortNames = [
			"Jan", "Feb", "Mar", "Apr", "May", "Jun",
			"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
		]
	}

	public enum Weekday: Int, Equatable, CaseIterable {
		case sunday = 0
		case monday
		case tuesday
		case wednesday
		case thursday
		case friday
		case saturday
		
		public init?(shortName: String) {
			guard let index = Self.shortNames.firstIndex(of: shortName) else {
				return nil
			}
			self = Self.allCases[index]
		}

		public init?(named name: String) {
			guard let index = Self.names.firstIndex(of: name) else {
				return nil
			}
			self = Self.allCases[index]
		}
		
		public var name: String {
			Self.names[rawValue]
		}
		
		public var shortName: String {
			Self.shortNames[rawValue]
		}

		static let names = [
			"Sunday", "Monday", "Tuesday", "Wednesday",
			"Thursday", "Friday", "Saturday",
		]

		static let shortNames = [
			"Sun", "Mon", "Tue", "Wed",
			"Thu", "Fri", "Sat",
		]
	}
}

extension Time {
	/// Get the time as an absolute time, adjusted by the zone offset.
	/// It is called when computing a presentation property like Month or Hour.
	var nanosecondsInZone: UInt64 {
		let sec = unixSeconds + Int64(offset)
		return UInt64(sec + unixToInternal + internalToAbsolute)
	}
	
	/// absWeekday is like Weekday but operates on an absolute time.
	static func absWeekday(_ abs: UInt64) -> Weekday {
		// January 1 of the absolute year, like January 1 of 2001, was a Monday.
		let sec = (Int(abs) + secondsPerDay) % secondsPerWeek
		let index = (Int(sec) / secondsPerDay) % Weekday.allCases.count
		return Weekday.allCases[index]
	}


	func dateComponents(full: Bool) -> DateComponents {
		Self.dateComponents(nanosecondsInZone, full: full)
	}

	static func dateComponents(_ ns: UInt64, full: Bool) -> DateComponents {
		// Split into time and day.
		var d = ns / UInt64(secondsPerDay)

		// Account for 400 year cycles.
		var n = d / UInt64(daysPer400Years)
		var y = 400 * n
		d -= UInt64(daysPer400Years) * n

		// Cut off 100-year cycles.
		// The last cycle has one extra leap year, so on the last day
		// of that year, day / daysPer100Years will be 4 instead of 3.
		// Cut it back down to 3 by subtracting n>>2.
		n = d / UInt64(daysPer100Years)
		n -= n >> 2
		y += 100 * n
		d -= UInt64(daysPer100Years) * n

		// Cut off 4-year cycles.
		// The last cycle has a missing leap year, which does not
		// affect the computation.
		n = d / UInt64(daysPer4Years)
		y += 4 * n
		d -= UInt64(daysPer4Years) * n

		// Cut off years within a 4-year cycle.
		// The last year is a leap year, so on the last day of that year,
		// day / 365 will be 4 instead of 3. Cut it back down to 3
		// by subtracting n>>2.
		n = d / 365
		n -= n >> 2
		y += n
		d -= 365 * n

		var comps = DateComponents(
			year: Int(Int64(y) + Int64(absoluteZeroYear)),
			month: .january, day: 0, yearDay: Int(d)
		)
		if !full {
			return comps
		}

		comps.day = comps.yearDay
		if isLeapYear(comps.year) {
			// Leap year
			if comps.day > 31 + 29 - 1 {
				// After leap day; pretend it wasn't there.
				comps.day -= 1
			} else if comps.day == 31 + 29 - 1 {
				// Leap day.
				comps.month = .february
				comps.day = 29
				return comps
			}
		}

		// Estimate month on assumption that every month has 31 days.
		// The estimate may be too low by at most one month, so adjust.
		var monthIndex = comps.day / 31
		let end = Int(daysBefore[monthIndex + 1])
		var begin: Int
		if comps.day >= end {
			monthIndex += 1
			begin = end
		} else {
			begin = Int(daysBefore[monthIndex])
		}

		comps.month = Month(index: monthIndex)
		comps.day = comps.day - begin + 1
		return comps
	}

	public static func isLeapYear(_ year: Int) -> Bool {
		year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
	}

	static func clockComponents(_ nsInZone: UInt64, nanoseconds: Int32) -> ClockComponents {
		var sec = Int(nsInZone % UInt64(secondsPerDay))
		let hour = sec / secondsPerHour
		sec -= hour * secondsPerHour
		let min = sec / secondsPerMinute
		sec -= min * secondsPerMinute
		let ms = (Int64(nanoseconds) % TimeDuration.nanosecondsPerSecond) / TimeDuration.nanosecondsPerMillisecond
		return .init(hour: hour, minute: min, second: sec, millisecond: Int(ms))
	}

	/// Takes a year and returns the number of days from the absolute epoch to the start of that year.
	/// This is basically (year - zeroYear) * 365, but accounting for leap days.
	static func daysSinceEpoch(_ year: Int) -> UInt64 {
		var y = UInt64(Int64(year) - Int64(absoluteZeroYear))

		// Add in days from 400-year cycles.
		var n = y / 400
		y -= 400 * n
		var d = UInt64(daysPer400Years) * n

		// Add in 100-year cycles.
		n = y / 100
		y -= 100 * n
		d += UInt64(daysPer100Years) * n

		// Add in 4-year cycles.
		n = y / 4
		y -= 4 * n
		d += UInt64(daysPer4Years) * n

		// Add in non-leap years.
		n = y
		d += 365 * n

		return d
	}
}

private let secondsPerMinute = 60
private let secondsPerHour = 60 * secondsPerMinute
private let secondsPerDay = 24 * secondsPerHour
private let secondsPerWeek = 7 * secondsPerDay
private let daysPer400Years = 365 * 400 + 97
private let daysPer100Years = 365 * 100 + 24
private let daysPer4Years = 365 * 4 + 1
// daysBefore[m] counts the number of days in a non-leap year
// before month m begins. There is an entry for m=12, counting
// the number of days before January of next year (365).
private let daysBefore: [Int32] = [
	0,
	31,
	31 + 28,
	31 + 28 + 31,
	31 + 28 + 31 + 30,
	31 + 28 + 31 + 30 + 31,
	31 + 28 + 31 + 30 + 31 + 30,
	31 + 28 + 31 + 30 + 31 + 30 + 31,
	31 + 28 + 31 + 30 + 31 + 30 + 31 + 31,
	31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
	31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
	31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30,
	31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30 + 31,
]

/// The unsigned zero year for internal calculations.
/// Must be 1 mod 400, and times before it will not compute correctly,
/// but otherwise can be changed at will.
private let absoluteZeroYear = -292_277_022_399

/// The year of the zero Time.
/// Assumed by the unixToInternal computation below.
private let internalYear = 1

/// Offsets to convert between internal and absolute or Unix times.
private let absoluteToInternal = Int64(Double(absoluteZeroYear - internalYear) * 365.2425) * Int64(secondsPerDay)
private let internalToAbsolute = -absoluteToInternal

private let unixToInternal = Int64((1969 * 365 + 1969 / 4 - 1969 / 100 + 1969 / 400) * secondsPerDay)
private let internalToUnix = -unixToInternal
private let wallToInternal = Int64((1884 * 365 + 1884 / 4 - 1884 / 100 + 1884 / 400) * secondsPerDay)
private let internalToWall = -wallToInternal

private func normalized(seconds: Int64, nano: Int64) -> (Int64, Int32) {
	// `nanoseconds` must be always zero or positive value and less than 1_000_000_000
	if nano >= TimeDuration.nanosecondsPerSecond {
		return (seconds + nano / TimeDuration.nanosecondsPerSecond,
		        Int32(nano % TimeDuration.nanosecondsPerSecond))
	}
	if nano < 0 {
		// For example, (3,-2_123_456_789) -> (0,876_543_211)
		return (seconds + Int64(nano) / TimeDuration.nanosecondsPerSecond - 1,
		        Int32(nano % TimeDuration.nanosecondsPerSecond + TimeDuration.nanosecondsPerSecond))
	}
	return (seconds, Int32(nano))
}

/// Get normalized `hi` and `lo` such that
///	`hi * base + lo == nhi * base + nlo`
///	`0 <= nlo < base`
private func normalized(_ hi: Int, _ lo: Int, base: Int) -> (Int, Int) {
	var (hi, lo) = (hi, lo)
	if lo < 0 {
		let n = (-lo - 1) / base + 1
		hi -= n
		lo += n * base
	}
	if lo >= base {
		let n = lo / base
		hi += n
		lo -= n * base
	}
	return (hi, lo)
}

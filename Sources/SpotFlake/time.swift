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

public extension TimeZone {
	static var utc: TimeZone { .init(secondsFromGMT: 0)! }
}

public struct Time {
	public static var zero: Self { .init(seconds: 0, nano: 0, zone: nil) }
	
	/// Seconds since `0001-01-01`
	fileprivate let seconds: Int64
	public let nanoseconds: Int32
	public let zone: TimeZone?

	public init(unix seconds: Int64, nano: Int64, zone: TimeZone? = nil) {
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
		self.init(seconds: sec + unixToInternal, nano: nano, zone: zone)
	}

	public init(unixMilli: Int64, zone: TimeZone? = nil) {
		self.init(unix: unixMilli / 1000,
		          nano: (unixMilli % 1000) * 1_000_000, zone: zone)
	}

	public init(unixMicro: Int64, zone: TimeZone? = nil) {
		self.init(unix: unixMicro / 1_000_000,
		          nano: (unixMicro % 1_000_000) * 1000, zone: zone)
	}

	public init(unixNano: Int64, zone: TimeZone? = nil) {
		self.init(unix: unixNano / TimeDuration.nanosecondsPerSecond,
		          nano: unixNano % TimeDuration.nanosecondsPerSecond, zone: zone)
	}

	public init(seconds: Int64, nano: Int64, zone: TimeZone? = nil) {
		(self.seconds, nanoseconds) = normalized(seconds: seconds, nano: nano)
		self.zone = zone
	}
	
	/// Time for now without timezone.
	public init() {
		self.init(zone: nil)
	}

	/// Time for now.
	public init(zone: TimeZone? = nil) {
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
			          nano: Int64(c_timespec.tv_nsec), zone: zone)
		} else {
			self.init(Date(), zone: zone)
		}
	}

	public init(_ date: Date, zone: TimeZone? = nil) {
		let sec = date.timeIntervalSince1970
		self.init(unix: Int64(sec),
		          nano: Int64((sec - floor(sec)) * TimeInterval(TimeDuration.nanosecondsPerSecond)),
		          zone: zone)
	}

	public init(year: Int, month: Month, day: Int,
	            hour: Int, minute: Int, second: Int, nano: Int,
	            zone: TimeZone? = nil)
	{
		self.init(year: year, month: month.rawValue,
		          day: day, hour: hour, minute: minute, second: second, nano: nano,
		          zone: zone)
	}

	public init(year: Int, month: Int, day: Int,
	            hour: Int, minute: Int, second: Int, nano: Int,
	            zone: TimeZone? = nil)
	{
		// Normalize month, overflowing into year.
		let (year, monthIndex) = normalized(year, month - 1, base: 12)
		let month = Month(rawValue: monthIndex + 1)!

		// Normalize nsec, sec, min, hour, overflowing into day.
		var (day, hour, min, sec, nsec) = (day, hour, minute, second, nano)
		(sec, nsec) = normalized(second, nano, base: 1_000_000_000)
		(min, sec) = normalized(minute, sec, base: 60)
		(hour, min) = normalized(hour, min, base: 60)
		(day, hour) = normalized(day, hour, base: 24)

		// Compute days since the absolute epoch.
		var d = Self.daysSinceEpoch(year)

		// Add in days before this month.
		d += UInt64(daysBefore[month.rawValue - 1])
		if Self.isLeapYear(year), month.rawValue >= Month.march.rawValue {
			d += 1 // February 29
		}

		// Add in days before today.
		d += UInt64(day - 1)

		// Add in time elapsed today.
		var ns = d * UInt64(secondsPerDay)
		ns += UInt64(hour * secondsPerHour + min * secondsPerMinute + sec)

		var unix = Int64(ns) + (absoluteToInternal + internalToUnix)
		let zone = zone ?? .utc
		let offset = zone.secondsFromGMT()
		if offset != 0 {
			unix -= Int64(offset)
		}
		self.init(unix: unix, nano: Int64(nsec), zone: zone)
	}

	public func `in`(zone: TimeZone) -> Time {
		.init(seconds: seconds, nano: Int64(nanoseconds), zone: zone)
	}

	public var withUTC: Time {
		.init(seconds: seconds, nano: Int64(nanoseconds), zone: .utc)
	}

	public var withLocal: Time {
		.init(seconds: seconds, nano: Int64(nanoseconds), zone: .current)
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
		             month: dates.month.rawValue + months,
		             day: dates.day + days,
		             hour: clocks.hour, minute: clocks.minute, second: clocks.second,
		             nano: Int(nanoseconds), zone: zone)
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
		Self.clockComponents(nanosecondsInZone)
	}

	var year: Int { dateComponents(full: false).year }

	var month: Month { dateComponents(full: true).month }

	var day: Int { dateComponents(full: true).day }

	var yearDay: Int { dateComponents(full: false).yearDay }

	var hour: Int {
		Int(nanosecondsInZone % UInt64(secondsPerDay)) / secondsPerHour
	}

	var minute: Int {
		Int(nanosecondsInZone % UInt64(secondsPerHour)) / secondsPerMinute
	}

	var second: Int { Int(nanosecondsInZone % UInt64(secondsPerMinute)) }
}

extension Time: Equatable, Comparable {
	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.seconds == rhs.seconds && lhs.nanoseconds == rhs.nanoseconds
	}

	public static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.seconds < rhs.seconds || (lhs.seconds == rhs.seconds && lhs.nanoseconds < rhs.nanoseconds)
	}

	public static func + (t: Self, dur: TimeDuration) -> Self {
		var dsec = dur.nanoseconds / TimeDuration.nanosecondsPerSecond
		var nsec = Int64(t.nanoseconds) + dur.nanoseconds % TimeDuration.nanosecondsPerSecond
		if nsec >= TimeDuration.nanosecondsPerSecond {
			dsec += 1
			nsec -= TimeDuration.nanosecondsPerSecond
		} else if nsec < 0 {
			dsec -= 1
			nsec += TimeDuration.nanosecondsPerSecond
		}
		let (sec, _) = t.seconds.addingReportingOverflow(dsec)
		return .init(seconds: sec, nano: nsec, zone: t.zone)
	}

	public static func - (lhs: Self, rhs: Self) -> TimeDuration {
		let (d, _) = ((lhs.seconds - rhs.seconds) * TimeDuration.nanosecondsPerSecond)
			.addingReportingOverflow(Int64(lhs.nanoseconds - rhs.nanoseconds))
		let dur = TimeDuration(d)
		if rhs + dur == lhs {
			return dur
		}
		return .init(lhs < rhs ? .min : .max)
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

		public init(hour: Int, minute: Int, second: Int) {
			self.hour = hour
			self.minute = minute
			self.second = second
		}
	}

	public enum Month: Int, Equatable {
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
	}
}

extension Time {
	/// Get the time as an absolute time, adjusted by the zone offset.
	/// It is called when computing a presentation property like Month or Hour.
	var nanosecondsInZone: UInt64 {
		let zone = self.zone ?? .utc
		let sec = unixSeconds + Int64(zone.secondsFromGMT())
		return UInt64(sec + unixToInternal + internalToAbsolute)
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

		monthIndex += 1 // because January is 1
		Month(rawValue: monthIndex).map { comps.month = $0 }
		comps.day = comps.day - begin + 1
		return comps
	}

	public static func isLeapYear(_ year: Int) -> Bool {
		year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
	}

	static func clockComponents(_ ns: UInt64) -> ClockComponents {
		var sec = Int(ns % UInt64(secondsPerDay))
		let hour = sec / secondsPerHour
		sec -= hour * secondsPerHour
		let min = sec / secondsPerMinute
		sec -= min * secondsPerMinute
		return .init(hour: hour, minute: min, second: sec)
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

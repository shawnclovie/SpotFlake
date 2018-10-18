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

private let nanoMax: Int32 = 1_000_000_000

public enum Clock {
	
	public struct Time: Equatable {
		
		public static func ==(l: Time, r: Time) -> Bool {
			return l.seconds == r.seconds && l.nanoseconds == r.nanoseconds
		}
		
		public var seconds: Int64
		public var nanoseconds: Int32 {
			didSet {normalize()}
		}
		
		public init(unixNano: Int64) {
			seconds = unixNano / Int64(nanoMax)
			nanoseconds = Int32(unixNano % Int64(nanoMax))
		}
		
		public init(seconds: Int64, nanoseconds: Int32) {
			self.seconds = seconds
			self.nanoseconds = nanoseconds
			normalize()
		}
		
		fileprivate init(_ cts: CTimeSpec) {
			seconds = Int64(cts.tv_sec)
			nanoseconds = Int32(cts.tv_nsec)
		}
		
		public mutating func normalize() {
			// `nanoseconds` must be always zero or positive value and less than 1_000_000_000
			if nanoseconds >= nanoMax {
				seconds += Int64(nanoseconds / nanoMax)
				nanoseconds = nanoseconds % nanoMax
			} else if nanoseconds < 0 {
				// For example, (3,-2_123_456_789) -> (0,876_543_211)
				seconds += Int64(nanoseconds / nanoMax) - 1
				nanoseconds = nanoseconds % nanoMax + nanoMax
			}
		}
		
		public var flakeTime: Int64 {
			return (seconds * Int64(nanoMax) + Int64(nanoseconds)) / 1_000_000
		}
	}
	
	case calendar
	case system
	
	public func makeTime() -> Time? {
		var c_timespec = CTimeSpec(tv_sec: 0, tv_nsec: 0)
		var retval: CInt = -1
		#if os(Linux)
		let clockID = self == .calendar ? CLOCK_REALTIME : CLOCK_MONOTONIC
		retval = clock_gettime(clockID, &c_timespec)
		#elseif os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
		var clockName: clock_serv_t = 0
		let clockID = self == .calendar ? CALENDAR_CLOCK : SYSTEM_CLOCK
		retval = host_get_clock_service(mach_host_self(), clockID, &clockName)
		if retval != 0 {
			return nil
		}
		retval = clock_get_time(clockName, &c_timespec)
		_ = mach_port_deallocate(mach_task_self(), clockName)
		#endif
		return retval == 0 ? Time(c_timespec) : nil
	}
}

extension Clock.Time {
	
	public init(_ date: Date) {
		let sec = date.timeIntervalSince1970
		seconds = Int64(sec)
		nanoseconds = Int32((sec - floor(sec)) * TimeInterval(nanoMax))
	}
	
	public var date: Date {
		return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / TimeInterval(nanoMax))
	}
}

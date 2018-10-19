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

extension SpotFlake {

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
		
		public init(seconds: Int64, nano: Int32) {
			self.seconds = seconds
			nanoseconds = nano
			normalize()
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
		
		public static var now: Time {
			var c_timespec = CTimeSpec(tv_sec: 0, tv_nsec: 0)
			var retval: CInt = -1
			repeat {
				#if os(Linux)
				// use CLOCK_MONOTONIC as system clock
				retval = clock_gettime(CLOCK_REALTIME, &c_timespec)
				#elseif os(OSX) || os(iOS) || os(watchOS) || os(tvOS)
				var clockName: clock_serv_t = 0
				// use SYSTEM_CLOCK as system clock
				retval = host_get_clock_service(mach_host_self(), CALENDAR_CLOCK, &clockName)
				guard retval == 0 else {
					break
				}
				retval = clock_get_time(clockName, &c_timespec)
				_ = mach_port_deallocate(mach_task_self(), clockName)
				#endif
				guard retval == 0 else {
					break
				}
				return Time(seconds: Int64(c_timespec.tv_sec), nano: Int32(c_timespec.tv_nsec))
			} while false
			return Time(Date())
		}
	}
}

extension SpotFlake.Time {
	
	public init(_ date: Date) {
		let sec = date.timeIntervalSince1970
		seconds = Int64(sec)
		nanoseconds = Int32((sec - floor(sec)) * TimeInterval(nanoMax))
	}
	
	public var date: Date {
		return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / TimeInterval(nanoMax))
	}
}

import Foundation

public struct TimeDuration: Sendable {
	public enum ParseError: Error {
		case invalidLeadingInt
		case invalidDuration
		case unknownUnit(unit: String)
	}

	public let nanoseconds: Int64

	public init(_ nano: Int64) {
		nanoseconds = nano
	}

	public static func components(
		days: Int64 = 0,
		hours: Int64 = 0,
		minutes: Int64 = 0,
		seconds: Int64 = 0,
		milliseconds: Int64 = 0,
		microseconds: Int64 = 0,
		nanoseconds: Int64 = 0
	) -> Self {
		.init(nanoseconds
			+ microseconds * Self.nanosecondsPerMicrosecond
			+ milliseconds * Self.nanosecondsPerMillisecond
			+ seconds * Self.nanosecondsPerSecond
			+ minutes * Self.nanosecondsPerMinute
			+ hours * Self.nanosecondsPerHour
			+ days * Self.nanosecondsPerDay)
	}

	public static func since(_ t: Time) -> Self {
		Time(offset: t.offset) - t
	}

	public var microseconds: Int64 {
		nanoseconds / Self.nanosecondsPerMicrosecond
	}

	public var milliseconds: Int64 {
		nanoseconds / Self.nanosecondsPerMillisecond
	}

	public var seconds: Double {
		let sec = nanoseconds / Self.nanosecondsPerSecond
		let nsec = nanoseconds % Self.nanosecondsPerSecond
		return Double(sec) + Double(nsec) / Double(Self.nanosecondsPerSecond)
	}

	public var minutes: Double {
		let sec = nanoseconds / Self.nanosecondsPerMinute
		let nsec = nanoseconds % Self.nanosecondsPerMinute
		return Double(sec) + Double(nsec) / Double(Self.nanosecondsPerMinute)
	}

	public var hours: Double {
		let sec = nanoseconds / Self.nanosecondsPerHour
		let nsec = nanoseconds % Self.nanosecondsPerHour
		return Double(sec) + Double(nsec) / Double(Self.nanosecondsPerHour)
	}

	public func truncate(_ d: Self) -> Self {
		d.nanoseconds < 0 ? self : .init(nanoseconds - nanoseconds % d.nanoseconds)
	}
}

extension TimeDuration: CustomStringConvertible {
	public var description: String {
		if nanoseconds == 0 {
			return "0s"
		}
		var buf = [Character](repeating: " ", count: 32)
		var pos = buf.count

		var ns = UInt64(abs(nanoseconds))
		if ns < UInt64(Self.nanosecondsPerSecond) {
			// Special case: if duration is smaller than a second,
			// use smaller units, like 1.2ms
			pos -= 1
			buf[pos] = "s"

			var prec: Int
			pos -= 1
			if ns < UInt64(Self.nanosecondsPerMicrosecond) {
				// print nanoseconds
				prec = 0
				buf[pos] = "n"
			} else if ns < UInt64(Self.nanosecondsPerMillisecond) {
				// print microseconds
				prec = 3
				// U+00B5 'µ' micro sign == 0xC2 0xB5
				pos -= 1 // Need room for two bytes.
				buf[pos] = "µ"
			} else {
				// print milliseconds
				prec = 6
				buf[pos] = "m"
			}
			(pos, ns) = Self.formatFraction(&buf[..<pos], ns, prec)
			pos = Self.formatInt(&buf[..<pos], ns)
		} else {
			pos -= 1
			buf[pos] = "s"

			(pos, ns) = Self.formatFraction(&buf[..<pos], ns, 9)

			// u is now integer seconds
			pos = Self.formatInt(&buf[..<pos], ns % 60)
			ns /= 60

			// u is now integer minutes
			if ns > 0 {
				pos -= 1
				buf[pos] = "m"
				pos = Self.formatInt(&buf[..<pos], ns % 60)
				ns /= 60

				// u is now integer hours
				// Stop at hours because days can be different lengths.
				if ns > 0 {
					pos -= 1
					buf[pos] = "h"
					pos = Self.formatInt(&buf[..<pos], ns)
				}
			}
		}
		if nanoseconds < 0 {
			pos -= 1
			buf[pos] = "-"
		}
		return String(buf[pos...])
	}

	/// Formats the fraction of `ns/10**prec` (e.g., ".12345") into the tail of buf,
	/// omitting trailing zeros. It omits the decimal point too when the fraction is 0.
	///
	/// It returns the index where the output bytes begin and the value `ns/10**prec`.
	private static func formatFraction(_ buf: inout ArraySlice<Character>, _ ns: UInt64, _ prec: Int) -> (Int, UInt64) {
		// Omit trailing zeros up to and including decimal point.
		var pos = buf.count
		var ns = ns
		var print = false
		for _ in 0 ..< prec {
			let digit = ns % 10
			print = print || digit != 0
			if print {
				pos -= 1
				buf[pos] = .init("\(digit)")
			}
			ns /= 10
		}
		if print {
			pos -= 1
			buf[pos] = "."
		}
		return (pos, ns)
	}

	/// Formats `ns` into the tail of buf.
	///
	/// It returns the index where the output begins.
	private static func formatInt(_ buf: inout ArraySlice<Character>, _ ns: UInt64) -> Int {
		var pos = buf.count
		if ns == 0 {
			pos -= 1
			buf[pos] = "0"
		} else {
			var ns = ns
			while ns != 0 {
				pos -= 1
				buf[pos] = .init("\(ns % 10)")
				ns /= 10
			}
		}
		return pos
	}
}

extension TimeDuration {
	public static let defaultParseUnit = "s"
	
	/// Parse string to [Duration].
	///
	/// - Units:
	///   - day: d
	///   - hour: h
	///   - minute: m
	///   - second: s
	///   - milliseconds: ms
	///   - microseconds: us, µs (micro symbol), μs (Greek letter mu)
	///
	/// - Example:
	///   - 1d2h3m4s: Duration(days: 1, hours: 2, minutes: 3, seconds: 4)
	///   - 1.5h: Duration(hours: 1, minutes: 30)
	///   - .5h: Duration(minutes: 30)
	///   - -1h: Duration(hours: -1)
	///   - 0: Duration()
	///   - 1d1d: Duration(days: 2)
	///
	/// - Returns:
	///   - [Duration.zero] would be returned if any error during parse.
	public static func parse(_ s: String, defaultUnit: String = defaultParseUnit) -> TimeDuration {
		do {
			return try tryParse(s, defaultUnit: defaultUnit)
		} catch {
			print("parseDuration failed: \(error), input=\(s)")
			return .zero
		}
	}

	/// Parse string to [Duration], see detail from [parseDuration].
	/// - Throws: if input invalid.
	public static func tryParse(_ s: String, defaultUnit: String = defaultParseUnit) throws -> TimeDuration {
		// [-+]?([0-9]*(\.[0-9]*)?[a-z]+)+
		var d = Int64(0)
		var neg = false

		var s = s[...]
		// Consume [-+]?
		if !s.isEmpty {
			let c = s.first
			if c == "-" || c == "+" {
				neg = c == "-"
				s = s.dropFirst()
			}
		}
		// Special case: if all that is left is "0", this is zero.
		if s.isEmpty { return .zero }
		while !s.isEmpty {
			// integers before, after decimal point
			var v = Int64(0)
			var f = Int64(0)
			var scale = 1.0 // value = v + f/scale

			// The next character must be [0-9.]
			let firstChar = s.utf8[s.startIndex]
			if !(firstChar == codeUnitDot ||
				codeUnit0 <= firstChar && firstChar <= codeUnit9)
			{
				throw ParseError.invalidDuration
			}
			// Consume [0-9]*
			let pl = s.count
			(v, s) = try leadingInt(s)
			let pre = pl != s.count // whether we consumed anything before a period

			// Consume (\.[0-9]*)?
			var post = false
			if !s.isEmpty, s.utf8.first == codeUnitDot {
				s = s.dropFirst()
				let pl = s.count
				(f, scale, s) = leadingFraction(s)
				post = pl != s.count
			}
			// no digits (e.g. ".s" or "-.s")
			if !pre, !post {
				throw ParseError.invalidDuration
			}

			// Consume unit.
			var i = s.startIndex
			while i != s.endIndex {
				let c = s.utf8[i]
				if c == codeUnitDot || codeUnit0 <= c && c <= codeUnit9 {
					break
				}
				i = s.index(after: i)
			}
			let u: String
			if i == s.startIndex {
				u = defaultUnit.lowercased()
			} else {
				u = String(s[..<i])
				s = s[i...]
			}
			guard let unit = durationUnitToNS[u] else {
				throw ParseError.unknownUnit(unit: u)
			}
			// overflow
			if v > Int64.max / unit {
				throw ParseError.invalidDuration
			}
			v *= unit
			if f > 0 {
				// double is needed to be nanosecond accurate for fractions of hours.
				// v >= 0 && (f*unit/scale) <= 3.6e+12 (ns/h, h is the largest unit)
				v += Int64(Double(f) * (Double(unit) / scale))
				// overflow
				if v < 0 {
					throw ParseError.invalidDuration
				}
			}
			d += v
			// overflow
			if d < 0 {
				throw ParseError.invalidDuration
			}
		}
		return .init(neg ? -d : d)
	}
}

extension TimeDuration: Comparable, Equatable {
	public static func < (lhs: TimeDuration, rhs: TimeDuration) -> Bool {
		lhs.nanoseconds < rhs.nanoseconds
	}

	public static func == (lhs: TimeDuration, rhs: TimeDuration) -> Bool {
		lhs.nanoseconds == rhs.nanoseconds
	}
}

extension TimeDuration: Strideable {
	public typealias Stride = Int64

	public func distance(to other: TimeDuration) -> Int64 {
		other.nanoseconds - nanoseconds
	}

	public func advanced(by n: Int64) -> TimeDuration {
		.init(nanoseconds + n)
	}
}

extension TimeDuration: AdditiveArithmetic {
	/// The zero value for `TimeDuration`.
	public static var zero: TimeDuration {
		.init(0)
	}

	public static func + (lhs: Self, rhs: Self) -> Self {
		.init(lhs.nanoseconds + rhs.nanoseconds)
	}

	public static func += (lhs: inout Self, rhs: Self) {
		lhs = lhs + rhs
	}

	@inlinable
	public static prefix func - (lhs: Self) -> Self {
		.init(lhs.nanoseconds)
	}

	public static func - (lhs: Self, rhs: Self) -> Self {
		.init(lhs.nanoseconds - rhs.nanoseconds)
	}

	public static func -= (lhs: inout Self, rhs: Self) {
		lhs = lhs - rhs
	}

	public static func * <T: BinaryInteger>(lhs: T, rhs: Self) -> Self {
		.init(Int64(lhs) * rhs.nanoseconds)
	}

	public static func * <T: BinaryInteger>(lhs: Self, rhs: T) -> Self {
		.init(lhs.nanoseconds * Int64(rhs))
	}

	public static func / <T: BinaryInteger>(lhs: Self, rhs: T) -> Self {
		.init(lhs.nanoseconds / Int64(rhs))
	}

	public static func / (lhs: Self, rhs: Self) -> Double {
		Double(lhs.nanoseconds) / Double(rhs.nanoseconds)
	}
}

public extension TimeDuration {
	static let nanosecondsPerMicrosecond: Int64 = 1000
	static let nanosecondsPerMillisecond: Int64 = 1000 * nanosecondsPerMicrosecond
	static let nanosecondsPerSecond: Int64 = 1000 * nanosecondsPerMillisecond
	static let nanosecondsPerMinute: Int64 = 60 * nanosecondsPerSecond
	static let nanosecondsPerHour: Int64 = 60 * nanosecondsPerMinute
	static let nanosecondsPerDay: Int64 = 24 * nanosecondsPerHour

	private static let codeUnitDot: UInt8 = 46
	private static let codeUnit0: UInt8 = 48
	private static let codeUnit9: UInt8 = 57
	private static let durationUnitToNS = [
		"us": nanosecondsPerMicrosecond,
		"µs": nanosecondsPerMicrosecond, // U+00B5 = micro symbol
		"μs": nanosecondsPerMicrosecond, // U+03BC = Greek letter mu
		"ms": nanosecondsPerMillisecond,
		"s": nanosecondsPerSecond,
		"m": nanosecondsPerMinute,
		"h": nanosecondsPerHour,
		"d": nanosecondsPerDay,
	]

	/// leadingInt consumes the leading [0-9]* from s.
	internal static func leadingInt(_ s: Substring) throws -> (Int64, Substring) {
		var x = Int64(0)
		var index = s.startIndex
		while index != s.endIndex {
			let c = s.utf8[index]
			if c < codeUnit0 || c > codeUnit9 {
				break
			}
			// overflow
			if x > Int64.max / 10 {
				throw ParseError.invalidLeadingInt
			}
			x = x * 10 + Int64(c - codeUnit0)
			// overflow
			if x < 0 {
				throw ParseError.invalidLeadingInt
			}
			index = s.index(after: index)
		}
		return (x, s[index...])
	}

	/// leadingFraction consumes the leading [0-9]* from s.
	/// It is used only for fractions, so does not return an error on overflow,
	/// it just stops accumulating precision.
	internal static func leadingFraction(_ s: Substring) -> (Int64, Double, Substring) {
		var x = Int64(0)
		var scale = 1.0
		var overflow = false
		var index = s.startIndex
		while index != s.endIndex {
			let c = s.utf8[index]
			if c < codeUnit0 || c > codeUnit9 {
				break
			}
			if overflow {
				continue
			}
			if x > Int64.max / 10 {
				// It's possible for overflow to give a positive number, so take care.
				overflow = true
				continue
			}
			let y = x * 10 + Int64(c - codeUnit0)
			if y < 0 {
				overflow = true
				continue
			}
			x = y
			scale *= 10
			index = s.index(after: index)
		}
		return (x, scale, s[index...])
	}
}

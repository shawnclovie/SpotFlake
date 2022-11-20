//
//  flake.swift
//  SpotFlake
//
//  Created by Shawn Clovie on 18/10/2018.
//

import Foundation

/// Number of bits to use for Node
/// Remember, you have a total 22 bits to share between Node/Step
let nodeBits: UInt8 = 10

/// Number of bits to use for Step
/// Remember, you have a total 22 bits to share between Node/Step
let stepBits: UInt8 = 12

let timeShift = nodeBits + stepBits
let nodeMax = Int64(-1 ^ (-1 << nodeBits))
let nodeMask: Int64 = nodeMax << stepBits
let stepMask: Int64 = -1 ^ (-1 << stepBits)

/// Swift version snowflake
public struct Flake {
	/// The epoch is set to the twitter snowflake epoch of Jan 01 2018 00:00:00 UTC.
	///
	/// You may customize this to set a different epoch for your application.
	///
	/// By SpotFlake.Time(Date()).flakeTime, you can calculate the epoch.
	public static var epoch: Int64 = 1514764800000

	// A Node struct holds the basic information needed for a snowflake generator node
	public class Node {
		private let mu: NSLock
		private let node: Int64
		private var time: Int64 = 0
		private var step: Int64 = 0
		
		/// Make new node with a number.
		///
		/// - Parameter node: Node number, should in 0...(-1 ^ (-1 << SpotFlake.nodeBits))
		public init?(node: Int64) {
			guard (0...nodeMax).contains(node) else {
				return nil
			}
			mu = NSLock()
			self.node = node
		}
		
		/// Generate next `ID`.
		public func generate() -> ID {
			mu.lock()
			var now = Self.flakeTimestamp(.init())
			if time == now {
				step = (step + 1) & stepMask
				if step == 0 {
					while now <= time {
						now = Self.flakeTimestamp(.init())
					}
				}
			} else {
				step = 0
			}
			time = now
			let id = ID((now - epoch) << timeShift | (node << stepBits) | step)
			mu.unlock()
			return id
		}
		
		static func flakeTimestamp(_ t: Time) -> Int64 {
			(t.unixSeconds * TimeDuration.nanosecondsPerSecond + Int64(t.nanoseconds)) / TimeDuration.nanosecondsPerMillisecond
		}
	}
	
	public struct ID: CustomStringConvertible, Equatable, Hashable {
		/// Mixed value, contains: nodeID, time in milliseconds, index.
		public let rawValue: Int64
		
		public init(_ rawValue: Int64) {
			self.rawValue = rawValue
		}
		
		public init?(base2: String) {
			guard let v = Int64(base2, radix: 2) else {
				return nil
			}
			rawValue = v
		}
		
		/// Parses a base32 bytes into a snowflake ID
		///
		/// NOTE: There are many different base32 implementations so becareful when doing any interoperation.
		public init?(base32: [UInt8]) {
			var id: Int64 = 0
			for i in base32 {
				if BaseMapping.shared.decodeBase32Map[Int(i)] == 0xFF {
					return nil
				}
				id = id*32 + Int64(BaseMapping.shared.decodeBase32Map[Int(i)])
			}
			rawValue = id
		}
		
		public init?(base36: String) {
			guard let v = Int64(base36, radix: 36) else {
				return nil
			}
			rawValue = v
		}
		
		public init?(base58: [UInt8]) {
			var id: Int64 = 0
			for i in base58 {
				if BaseMapping.shared.decodeBase58Map[Int(i)] == 0xFF {
					return nil
				}
				id = id*58 + Int64(BaseMapping.shared.decodeBase58Map[Int(i)])
			}
			rawValue = id
		}
		
		public init?(base64: String) {
			guard let d = Data(base64Encoded: base64) else {
				return nil
			}
			let s = String(decoding: d, as: UTF8.self)
			guard let v = Int64(s) else {
				return nil
			}
			rawValue = v
		}
		
		public init?(string: String) {
			guard let v = Int64(string) else {
				return nil
			}
			rawValue = v
		}
		
		public func hash(into hasher: inout Hasher) {
			hasher.combine(rawValue)
		}

		public var description: String { String(rawValue, radix: 10) }
		
		/// Base2 form string - longest form.
		public var base2: String { String(rawValue, radix: 2) }
		
		/// Base32 form string - shorter.
		///
		/// `base32` uses the z-base-32 character set but encodes and decodes similar to base58, allowing it to create an even smaller result string.
		///
		/// NOTE: There are many different base32 implementations so becareful when doing any interoperation.
		public var base32: String {
			let base: Int64 = 32
			if rawValue < base {
				return String(encodeBase32Map[Int(rawValue)])
			}
			var b = [Character]()
			b.reserveCapacity(12)
			var f = rawValue
			while f >= base {
				b.append(encodeBase32Map[Int(f%base)])
				f /= base
			}
			b.append(encodeBase32Map[Int(f)])
			var (x, y) = (0, b.count-1)
			while x < y {
				(b[x], b[y]) = (b[y], b[x])
				(x, y) = (x+1, y-1)
			}
			return String(b)
		}
		
		/// Base36 form string - simple and shorter.
		public var base36: String { String(rawValue, radix: 36) }
		
		/// Base58 form string - shortest form.
		public var base58: String {
			let base: Int64 = 58
			if rawValue < base {
				return String(encodeBase58Map[Int(rawValue)])
			}
			var b = [Character]()
			b.reserveCapacity(11)
			var f = rawValue
			while f >= base {
				b.append(encodeBase58Map[Int(f%base)])
				f /= base
			}
			b.append(encodeBase58Map[Int(f)])
			var (x, y) = (0, b.count-1)
			while x < y {
				(b[x], b[y]) = (b[y], b[x])
				(x, y) = (x+1, y-1)
			}
			return String(b)
		}
		
		/// Standard Base64 form string - medium short.
		public var base64: String { bytes.base64EncodedString() }
		
		public var bytes: Data { Data(description.utf8) }
		
		/// Milliseconds since 1970.
		public var time: Int64 { (rawValue >> timeShift) + epoch }
		
		/// Node identity.
		public var node: Int64 { rawValue & nodeMask >> stepBits }
		
		public var step: Int64 { rawValue & nodeMask >> stepBits }
	}
}

private let encodeBase32Map = "ybndrfg8ejkmcpqxot1uwisza345h769".map({$0})

private let encodeBase58Map = "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ".map({$0})

private struct BaseMapping {
	static let shared = BaseMapping()
	
	private(set) var decodeBase32Map = [UInt8](repeating: 0xFF, count: encodeBase32Map.count)

	private(set) var decodeBase58Map = [UInt8](repeating: 0xFF, count: encodeBase58Map.count)

	init() {
		for it in encodeBase58Map.enumerated() {
			decodeBase58Map[Int(it.element.asciiValue!)] = UInt8(it.offset)
		}
		for it in encodeBase32Map.enumerated() {
			decodeBase32Map[Int(it.element.asciiValue!)] = UInt8(it.offset)
		}
	}
}

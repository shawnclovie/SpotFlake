//
//  SpotFlake.swift
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
public struct SpotFlake {
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
			(t.seconds * TimeDuration.nanosecondsPerSecond + Int64(t.nanoseconds)) / TimeDuration.nanosecondsPerMillisecond
		}
	}
	
	public struct ID: CustomStringConvertible, Equatable, Hashable {
		public let rawValue: Int64
		
		public init(_ rawValue: Int64) {
			self.rawValue = rawValue
		}
		
		public init?(base2: String) {
			guard let v = Int64(base2, radix: 2) else { return nil }
			rawValue = v
		}
		
		public init?(base32: [UInt8]) {
			var id: Int64 = 0
			for i in base32 {
				if decodeBase32Map[Int(i)] == 0xFF {
					return nil
				}
				id = id*32 + Int64(decodeBase32Map[Int(i)])
			}
			rawValue = id
		}
		
		public init?(base36: String) {
			guard let v = Int64(base36, radix: 36) else { return nil }
			rawValue = v
		}
		
		public init?(base58: [UInt8]) {
			var id: Int64 = 0
			for i in base58 {
				if decodeBase58Map[Int(i)] == 0xFF {
					return nil
				}
				id = id*58 + Int64(decodeBase58Map[Int(i)])
			}
			rawValue = id
		}
		
		public init?(base64: String) {
			guard let d = Data(base64Encoded: base64) else { return nil }
			let s = String(decoding: d, as: UTF8.self)
			guard let v = Int64(s) else { return nil }
			rawValue = v
		}
		
		public init?(string: String) {
			guard let v = Int64(string) else { return nil }
			rawValue = v
		}
		
		public func hash(into hasher: inout Hasher) {
			hasher.combine(rawValue)
		}

		public var description: String { String(rawValue, radix: 10) }
		
		public var base2: String { String(rawValue, radix: 2) }
		
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
		
		public var base36: String { String(rawValue, radix: 36) }
		
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
		
		public var base64: String { bytes.base64EncodedString() }
		
		public var bytes: Data { Data(description.utf8) }
		
		public var time: Int64 { (rawValue >> timeShift) + epoch }
		
		public var node: Int64 { rawValue & nodeMask >> stepBits }
		
		public var step: Int64 { rawValue & nodeMask >> stepBits }
	}
}

private let encodeBase32Map = "ybndrfg8ejkmcpqxot1uwisza345h769".map({$0})

private var decodeBase32Map = [UInt8](repeating: 0xFF, count: encodeBase32Map.count)

private let encodeBase58Map = "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ".map({$0})

private var decodeBase58Map = [UInt8](repeating: 0xFF, count: encodeBase58Map.count)

private func initMap() {
	for it in encodeBase58Map.enumerated() {
		decodeBase58Map[Int(it.element.asciiValue!)] = UInt8(it.offset)
	}
	for it in encodeBase32Map.enumerated() {
		decodeBase32Map[Int(it.element.asciiValue!)] = UInt8(it.offset)
	}
}

//
//  SpotFlake.swift
//  SpotFlake
//
//  Created by Shawn Clovie on 18/10/2018.
//

import Foundation

/// Swift version snowflake
public struct SpotFlake {
	/// The epoch is set to the twitter snowflake epoch of Jan 01 2018 00:00:00 UTC.
	///
	/// You may customize this to set a different epoch for your application.
	///
	/// By SpotFlake.Time(Date()).flakeTime, you can calculate the epoch.
	public static var epoch: Int64 = 1514764800000
	
	/// Number of bits to use for Node
	/// Remember, you have a total 22 bits to share between Node/Step
	public static var nodeBits: UInt8 = 10

	/// Number of bits to use for Step
	/// Remember, you have a total 22 bits to share between Node/Step
	public static var stepBits: UInt8 = 12
	
	// A Node struct holds the basic information needed for a snowflake generator node
	public class Node {
		private let mu: NSLock
		private let node: Int64
		private var time: Int64 = 0
		private var step: Int64 = 0
		
		private let nodeMax: Int64
		private let nodeMask: Int64
		private let stepMask: Int64
		private let timeShift: UInt8
		private let nodeShift: UInt8
		
		/// Make new node with a number.
		///
		/// - Parameter node: Node number, should in 0...(-1 ^ (-1 << SpotFlake.nodeBits))
		public init?(node: Int64) {
			let nodeMax = Int64(-1 ^ (-1 << SpotFlake.nodeBits))
			guard (0...nodeMax).contains(node) else {
				return nil
			}
			mu = NSLock()
			self.nodeMax = nodeMax
			nodeMask = nodeMax << SpotFlake.stepBits
			stepMask = -1 ^ (-1 << SpotFlake.stepBits)
			timeShift = SpotFlake.nodeBits + SpotFlake.stepBits
			nodeShift = SpotFlake.stepBits
			self.node = node
		}

		public func generate() -> Int64 {
			mu.lock()
			var now = SpotFlake.Time.now.flakeTime
			if time == now {
				step = (step + 1) & stepMask
				if step == 0 {
					while now <= time {
						now = SpotFlake.Time.now.flakeTime
					}
				}
			} else {
				step = 0
			}
			time = now
			let id = (now - SpotFlake.epoch) << timeShift | (node << nodeShift) | step
			mu.unlock()
			return id
		}
		
		public func time(of id: Int64) -> Int64 {
			return (id >> timeShift) + SpotFlake.epoch
		}
		
		public func node(of id: Int64) -> Int64 {
			return id & nodeMask >> nodeShift
		}
		
		public func step(of id: Int64) -> Int64 {
			return id & stepMask
		}
	}
}

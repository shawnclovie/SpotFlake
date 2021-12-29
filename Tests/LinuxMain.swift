import XCTest

import SpotFlakeTests

var tests = [XCTestCaseEntry]()

tests += [
	("generate", SpotFlakeTests.testGenerate),
	("time", TimeTests.testTime),
	("parse_time_duration", TimeTests.testParseTimeDuration),
]
XCTMain(tests)

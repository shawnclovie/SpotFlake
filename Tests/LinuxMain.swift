import XCTest

import SpotFlakeTests

var tests = [XCTestCaseEntry]()
tests += SpotFlakeTests.allTests()
XCTMain(tests)
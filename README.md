# SpotFlake
Swift version snowflake (unique ID generator).

As an application developer, you create an instance of 'SpotFlake.Node' and then generate unique ID.

## Swift version
The latest version of Health works with the `4.2` version of the Swift binaries. You can download this version of the Swift binaries by following this [link](https://swift.org/download/#snapshots).

## Usage
To leverage the SpotFlake package in your Swift application, you should specify a dependency for it in your `Package.swift` file:

```swift
import PackageDescription

let package = Package(name: "MyAwesomeSwiftProject",
     ...
    dependencies: [
      .package(url: "https://github.com/shawnclovie/SpotFlake.git", .from: "0.1.0"),
    ],
```

And this is how you create a `SpotFlake.Node` instance and generate ID:

```swift

import SpotFlake

...

// the index would to mark ID generated source, e.g. server ID or process ID
let nodeIndex: Int64 = 1
// the index should between 0...(-1 ^ (-1 << SpotFlake.nodeBits))
let node = SpotFlake.Node(node: nodeIndex)!

...

// Generate new ID
let id = node.generate()
// Get date from the ID if needed
node.time(of: id) // ID generating time
node.node(of: id) // ID generator's node index
```

## Epoch
SpotFlake use epoch as genrating base, also you can change the base epoch:
```swift
SpotFlake.epoch = 1514764800000
```

To calculate the epoch:
```swift
import Foundation

let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd ZZZ"
print("epoch of custom date:", SpotFlake.Time(formatter.date(from: "2018-01-01 UTC")!).flakeTime)
```

## ID
The type of ID is Int64.

If you want to convert an ID to JSON, it should convert and pass as string, since JavaScript would loss precision for big integer.

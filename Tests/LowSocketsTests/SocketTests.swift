import XCTest
import Libc
@testable import LowSockets

class SocketTests: XCTestCase {
  func testDefaultSocket() throws {
    let sock = try Socket()
    XCTAssertEqual(sock.family, Family.ip4)
    XCTAssertEqual(sock.type, SocketType.stream)
    XCTAssertEqual(sock.proto, SocketProtocol.tcp)
    XCTAssertTrue(sock.fileDescriptor > 0)
    XCTAssertTrue(try sock.isBlocking())
  }

  func testCreateFromFD() throws {
    // create a socket
    let fd = socket(Family.ip6.value, SocketType.datagram.value, SocketProtocol.udp.value)
    try CError.makeAndThrow(fromReturnCode: fd)

    let sock = try Socket(fd: fd)
    #if os(Linux)
      XCTAssertEqual(sock.family, Family.ip6)
      XCTAssertEqual(sock.proto, SocketProtocol.udp)
    #else
      XCTAssertEqual(sock.family, Family.unknown)
      XCTAssertEqual(sock.proto, SocketProtocol.unknown)
    #endif
    XCTAssertEqual(sock.type, SocketType.datagram)
    XCTAssertEqual(sock.fileDescriptor, fd)
  }

  func testSetNonBlocking() throws {
    let sock = try Socket()

    // non-blocking works
    try sock.setNonBlocking()
    XCTAssertFalse(try sock.isBlocking())

    // idempotent operation
    try sock.setNonBlocking()
    XCTAssertFalse(try sock.isBlocking())

    // blocking reverts
    try sock.setBlocking()
    XCTAssertTrue(try sock.isBlocking())

    // idempotent too
    try sock.setBlocking()
    XCTAssertTrue(try sock.isBlocking())

    // non-blocking still works
    try sock.setNonBlocking()
    XCTAssertFalse(try sock.isBlocking())
  }

  func testSetLinger() throws {
    let sock = try Socket()
    try sock.setLinger(timeout: 0)
    XCTAssertEqual(TimeInterval(0), try sock.getLinger())
    try sock.setLinger(timeout: TimeInterval(1.234))
    XCTAssertEqual(TimeInterval(1), try sock.getLinger())
    try sock.setLinger(timeout: TimeInterval(20))
    XCTAssertEqual(TimeInterval(20), try sock.getLinger())
    try sock.setLinger(timeout: nil)
    XCTAssertNil(try sock.getLinger())
  }

  func testSetTimeouts() throws {
    let sock = try Socket()
    let cases: [TimeInterval] = [
      0,
      1.234,
      10,
      20.000499,
      -1,
    ]

    for c in cases {
      try sock.setReadTimeout(c)
      var want = c
      if c < 0 {
        want = 0
      }
      XCTAssertEqual(want, try sock.getReadTimeout())
    }
    for c in cases {
      try sock.setWriteTimeout(c)
      var want = c
      if c < 0 {
        want = 0
      }
      XCTAssertEqual(want, try sock.getWriteTimeout())
    }
  }
}

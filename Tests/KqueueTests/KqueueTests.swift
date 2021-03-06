import XCTest
import OS
import LowSockets
@testable import Kqueue

func tempFile(_ name: String) throws -> (Int32, () -> Void) {
  let file = "/tmp/\(name)"
  let fd = open(file, O_RDWR|O_CREAT, 0o666)
  try CError.makeAndThrow(fromReturnCode: fd)
  return (fd, {
    close(fd)
    unlink(file)
  })
}

class KqueueTests: XCTestCase {
  func testKqueueClose() throws {
    let kq = try Kqueue()
    try kq.close()
  }

  func testKqueueEmpty() throws {
    let kq = try Kqueue()
    defer { try? kq.close() }

    var events = Array<Kevent>()
    do {
      let ret = try kq.poll(with: [], into: &events)
      XCTAssertEqual(0, ret)
    } catch {
      XCTFail("want no error, got \(error)")
    }
  }

  func testKqueueFileWrite() throws {
    let (fd, fn) = try tempFile("filetest.txt")
    defer { fn() }

    // watch for write availability on fd
    var events = Array<Kevent>(repeating: Kevent(), count: 1)
    let ev = Kevent(fd: fd, filter: .write)
    let kq = try Kqueue()
    defer { try? kq.close() }

    // should be immediately available
    let ret = try kq.poll(with: [ev], into: &events)
    XCTAssertEqual(1, ret)
    let ev0 = events[0]
    XCTAssertEqual(ev0.identifier, Int(fd))
  }

  func testKqueueTimeout() throws {
    let (fd, fn) = try tempFile("filetest.txt")
    defer { fn() }

    // watch for read availability on fd, will never happen
    var events = Array(repeating: Kevent(), count: 1)
    let ev = Kevent(fd: fd)
    let kq = try Kqueue()
    defer { try? kq.close() }

    let timeout: TimeInterval = 0.1
    let start = Date()

    let ret = try kq.poll(with: [ev], into: &events, timeout: timeout)

    let dur = Date().timeIntervalSince(start)
    XCTAssertEqual(0, ret)
    XCTAssertGreaterThanOrEqual(dur, timeout)
  }

  func testKqueueTimer() throws {
    let kq = try Kqueue()
    defer { try? kq.close() }

    let ev = Kevent(identifier: 1, filter: .timer, data: 1) // 1ms
    var events = Array(repeating: Kevent(), count: 2)

    let ret = try kq.poll(with: [ev], into: &events)
    XCTAssertEqual(ret, 1)
    let ev0 = events[0]
    XCTAssertGreaterThan(ev0.data, 0)
    XCTAssertEqual(1.0, Double(ev0.data), accuracy: 1.0)

    let expect = expectation(description: "kqueue after 10ms")
    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(10)) {
      do {
        let ret = try kq.poll(with: [], into: &events)
        XCTAssertEqual(ret, 1)
        let ev0 = events[0]
        XCTAssertGreaterThanOrEqual(ev0.data, 10)

        expect.fulfill()
      } catch {
        XCTFail("kqueue failed with \(error)")
      }
    }

    waitForExpectations(timeout: 10)
  }

  func testKqueueSocket() throws {
    let path = "/tmp/test.sock"
    let addr = Address.unix(path: path)

    var sock = try Socket(family: .unix)
    try sock.bind(to: addr)
    try sock.listen()
    defer {
      try? sock.close()
      unlink(path)
    }

    // add the listening socket to the kqueue
    let kq = try Kqueue()
    defer { try? kq.close() }

    let ev = Kevent(fd: sock)
    var events = Array(repeating: Kevent(), count: 2)

    // wait for a connection
    let expect = expectation(description: "kqueue notifies accepted connection")
    DispatchQueue.global(qos: .background).async {
      do {
        let ret = try kq.poll(with: [ev], into: &events)
        XCTAssertEqual(1, ret)
        let ev0 = events[0]
        XCTAssertEqual(ev0.identifier, Int(sock.fileDescriptor))
        XCTAssertEqual(ev0.data, 1)

        let _ = try sock.accept()

        expect.fulfill()
      } catch {
        XCTFail("kqueue failed with \(error)")
      }
    }

    do {
      let sock = try Socket(family: .unix)
      defer { try? sock.close() }

      try sock.connect(to: addr)
    } catch {
      XCTFail("client socket failed with \(error)")
    }

    waitForExpectations(timeout: 10)
  }

  func testKqueueSignal() throws {
    let kq = try Kqueue()
    defer { try? kq.close() }

    let ev = Kevent(signal: .urg)

    let expect = expectation(description: "kqueue notifies signal")
    expect.expectedFulfillmentCount = 2

    DispatchQueue.global(qos: .background).async {
      do{
        var events = Array(repeating: Kevent(), count: 2)
        let ret = try kq.poll(with: [ev], into: &events, timeout: 1)
        XCTAssertEqual(1, ret)
        let ev0 = events[0]
        XCTAssertEqual(ev0.identifier, Int(Signal.urg.value))
        XCTAssertEqual(ev0.data, 1)

        expect.fulfill()
      } catch {
        XCTFail("kqueue failed with \(error)")
      }
    }

    // send the signal
    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(100)) {
      do {
        let pid = getpid()
        let ret = kill(pid, Signal.urg.value)
        try CError.makeAndThrow(fromReturnCode: ret)

        expect.fulfill()
      } catch {
        XCTFail("raise signal failed with \(error)")
      }
    }

    waitForExpectations(timeout: 10)
  }

  func testKqueueUser() throws {
    let kq = try Kqueue()
    defer { try? kq.close() }

    let ev = Kevent(identifier: 1, filter: .user, data: 42)

    // wait for a trigger
    let expect = expectation(description: "kqueue notifies trigger")
    expect.expectedFulfillmentCount = 2

    DispatchQueue.global(qos: .background).async {
      do{
        var events = Array(repeating: Kevent(), count: 2)
        let ret = try kq.poll(with: [ev], into: &events, timeout: 1)
        XCTAssertEqual(1, ret)
        let ev0 = events[0]
        XCTAssertEqual(ev0.identifier, 1)

        expect.fulfill()
      } catch {
        XCTFail("kqueue failed with \(error)")
      }
    }

    // trigger the user event
    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + .milliseconds(100)) {
      do {
        var events = Array(repeating: Kevent(), count: 2)
        let ev = Kevent(identifier: 1, filter: .user, filterFlags: [.trigger])
        let ret = try kq.poll(with: [ev], into: &events)
        XCTAssertEqual(1, ret)
        let ev0 = events[0]
        XCTAssertEqual(ev0.identifier, 1)

        expect.fulfill()
      } catch {
        XCTFail("kqueue trigger failed with \(error)")
      }
    }

    waitForExpectations(timeout: 10)
  }
}

import Libc
import LowSockets

// MARK: - PortServer

class PortServer {
  let port: Int
  let host: String
  private var sock: Socket? = nil

  init(_ host: String, _ port: Int) {
    self.host = host
    self.port = port
  }

  deinit {
    try? sock?.close()
  }

  func listen() throws {
    let sock = try Socket(family: .inet)
    self.sock = sock

    try sock.bind(toHost: host, port: port)
    try sock.listen()
  }

  func serve(_ handler: (Socket) throws -> Bool) throws {
    guard let sock = sock else {
      throw MessageError("no listening socket")
    }
    while true {
      let remote = try sock.accept()
      defer { try? remote.close() }

      if !(try handler(remote)) {
        try sock.close()
        return
      }
    }
  }
}

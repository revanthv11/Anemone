import Foundation

/// An IPv4 UDP socket over BSD sockets. A Network.framework connection only hears from the address
/// it sends to, but the replies to a broadcast come from each server's own address.
final class UDPSocket: Sendable {
    /// A datagram that arrived, with the address to answer it at.
    struct Datagram {
        let data: Data
        let sender: sockaddr_in
    }

    /// Larger than any discovery reply; a longer datagram is cut short and then fails to parse.
    private static let receiveBufferSize = 4096

    private let descriptor: Int32

    /// Opens a socket bound to `host` and `port`. Port 0 lets the system pick a free one.
    init(host: String = "0.0.0.0", port: UInt16 = 0, broadcast: Bool = false) throws(POSIXError) {
        guard let address = Self.address(host, port: port) else { throw POSIXError(.EINVAL) }
        let opened = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard opened >= 0 else { throw Self.lastError() }
        var enabled: Int32 = 1
        let broadcastReady = !broadcast
            || setsockopt(opened, SOL_SOCKET, SO_BROADCAST, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0
        guard broadcastReady, Self.withSocketAddress(address, { bind(opened, $0, $1) }) == 0 else {
            let error = Self.lastError()
            close(opened)
            throw error
        }
        descriptor = opened
    }

    deinit {
        close(descriptor)
    }

    /// The port the socket is bound to, so a test can tell the search where its responder listens.
    var port: UInt16 {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        return result == 0 ? UInt16(bigEndian: address.sin_port) : 0
    }

    /// Sends one datagram. Returns the error when it couldn't be sent.
    func send(_ data: Data, to address: sockaddr_in) -> POSIXError? {
        let sent = data.withUnsafeBytes { bytes in
            Self.withSocketAddress(address) { sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, $1) }
        }
        return sent < 0 ? Self.lastError() : nil
    }

    /// Waits up to `timeout` for a datagram and reads it. Blocks the calling thread meanwhile.
    func receive(timeout: Duration) -> Datagram? {
        var request = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&request, 1, Int32(clamping: timeout.wholeMilliseconds)) > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Self.receiveBufferSize)
        var sender = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = buffer.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &sender) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(descriptor, bytes.baseAddress, bytes.count, 0, $0, &length)
                }
            }
        }
        guard count >= 0 else { return nil }
        return Datagram(data: Data(buffer.prefix(count)), sender: sender)
    }

    /// An IPv4 address in dotted form, such as "192.168.1.255", with a port; nil for anything else.
    static func address(_ host: String, port: UInt16) -> sockaddr_in? {
        var address = sockaddr_in()
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return nil }
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        return address
    }

    private static func withSocketAddress<Result>(
        _ address: sockaddr_in,
        _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result,
    ) -> Result {
        withUnsafePointer(to: address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private static func lastError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private extension Duration {
    var wholeMilliseconds: Int64 {
        components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
    }
}

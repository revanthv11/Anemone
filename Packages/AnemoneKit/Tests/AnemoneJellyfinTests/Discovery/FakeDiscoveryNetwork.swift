@testable import AnemoneJellyfin
import Foundation
import Synchronization

/// Stands in for the network a search talks to, through sockets of its own: each probe a search
/// sends is answered at once with every reply in `replies`, in order, on the search's own thread.
/// So a test needs no UDP, and nothing waits for another thread to answer. It records where the
/// probes went and how long the search waited for replies that didn't come.
final class FakeDiscoveryNetwork: Sendable {
    /// A probe as a search sent it, with where it went, such as "192.168.1.255:7359".
    struct Probe: Equatable {
        let text: String
        let destination: String
    }

    private struct Record {
        var probes: [Probe] = []
        var waits: [Duration] = []
    }

    private let replies: [Data]
    private let unreachable: Set<String>
    private let record = Mutex(Record())
    private let closings: AsyncStream<Void>
    private let closing: AsyncStream<Void>.Continuation

    /// - Parameters:
    ///   - replies: What servers answer each probe with.
    ///   - unreachable: Addresses a probe can't be sent to, as when there's no route.
    init(replies: [String] = [], unreachable: Set<String> = []) {
        self.replies = replies.map { Data($0.utf8) }
        self.unreachable = unreachable
        (closings, closing) = AsyncStream.makeStream()
    }

    /// A search on this network, at Jellyfin's port.
    func discovery(addresses: [String] = ["192.168.1.255"], duration: Duration = .seconds(30)) -> ServerDiscovery {
        ServerDiscovery(broadcastAddresses: addresses, duration: duration) { [self] in Socket(network: self) }
    }

    /// The probes searches sent, in order.
    var probes: [Probe] {
        record.withLock(\.probes)
    }

    /// How long each wait for a reply that didn't come was, in order.
    var waits: [Duration] {
        record.withLock(\.waits)
    }

    /// Returns once a search has closed its socket.
    func socketClosed() async {
        for await _ in closings {
            return
        }
    }

    private final class Socket: DiscoverySocket {
        private let network: FakeDiscoveryNetwork
        private var inbox: [Data] = []

        init(network: FakeDiscoveryNetwork) {
            self.network = network
        }

        deinit {
            network.closing.yield()
        }

        func send(_ data: Data, to address: sockaddr_in) -> POSIXError? {
            let host = InterfaceAddress.dotted(UInt32(bigEndian: address.sin_addr.s_addr))
            guard !network.unreachable.contains(host) else { return POSIXError(.EHOSTUNREACH) }
            let probe = Probe(
                text: String(data: data, encoding: .utf8) ?? "",
                destination: "\(host):\(UInt16(bigEndian: address.sin_port))",
            )
            network.record.withLock { $0.probes.append(probe) }
            inbox += network.replies
            return nil
        }

        func receive(timeout: Duration) -> UDPSocket.Datagram? {
            guard inbox.isEmpty else { return UDPSocket.Datagram(data: inbox.removeFirst(), sender: sockaddr_in()) }
            network.record.withLock { $0.waits.append(timeout) }
            // Waits out the timeout, as a quiet socket would. `Thread.sleep` can wake a hair early.
            let end = ContinuousClock.now + timeout
            while ContinuousClock.now < end {
                Thread.sleep(forTimeInterval: (end - ContinuousClock.now) / .seconds(1))
            }
            return nil
        }
    }
}

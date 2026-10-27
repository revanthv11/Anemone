import Foundation
import Synchronization

public enum ServerDiscoveryError: Error, Equatable, Sendable {
    /// The UDP socket couldn't be opened or set up.
    case socketUnavailable(POSIXErrorCode)
    /// None of the broadcast addresses is an IPv4 address, so the probe had nowhere to go.
    case noBroadcastAddress
    /// The probe couldn't be sent to any address: there's no network, or the system refused, as iOS
    /// does for apps without the multicast entitlement.
    case probeNotSent(POSIXErrorCode)
}

/// Finds Jellyfin servers on the local network, as Wholphin's server list does with
/// jellyfin-sdk-kotlin's `discoverLocalServers()`: it broadcasts Jellyfin's discovery message to
/// UDP port 7359, and each server that hears it answers with a line of JSON naming itself.
///
/// jellyfin-sdk-swift 3.3.0 has `JellyfinClient.discover()`, but it always broadcasts on every
/// network interface, so tests couldn't point it at a responder of their own. Here the port and
/// the addresses can be set, and tests answer on 127.0.0.1 without touching the real network, or
/// stand in for the socket so no network or second thread is involved at all.
///
/// iOS needs Apple's multicast entitlement (`com.apple.developer.networking.multicast`), which
/// Apple grants on request, to send a broadcast; whether tvOS does too is the multicast spike's
/// question. The app doesn't have the entitlement, so nothing calls this yet; see Phase 1 in
/// `docs/PLAN.md`.
public struct ServerDiscovery: Sendable {
    /// The port Jellyfin servers listen on for discovery.
    public static let jellyfinPort: UInt16 = 7359
    /// The message Jellyfin servers listen for, as jellyfin-sdk-swift sends it.
    static let probe = Data("who is JellyfinServer?".utf8)
    /// The limited broadcast. It goes out of one interface only, so each network's own broadcast
    /// address goes first.
    static let limitedBroadcastAddress = "255.255.255.255"
    /// How long a quiet search waits before checking whether it was stopped.
    private static let stopCheckInterval: Duration = .milliseconds(100)

    public let port: UInt16
    public let broadcastAddresses: [String]?
    public let duration: Duration
    /// Opens the socket a search sends its probe from and hears the replies on.
    private let openSocket: @Sendable () throws(POSIXError) -> any DiscoverySocket

    /// - Parameters:
    ///   - port: Where servers listen: Jellyfin's port, or a test responder's.
    ///   - broadcastAddresses: IPv4 addresses the probe goes to. Nil means each network's broadcast
    ///     address on this device, then 255.255.255.255, read when the search starts.
    ///   - duration: How long to listen for replies; jellyfin-sdk-swift also listens for 5 s.
    public init(port: UInt16 = jellyfinPort, broadcastAddresses: [String]? = nil, duration: Duration = .seconds(5)) {
        self.init(port: port, broadcastAddresses: broadcastAddresses, duration: duration) { () throws(POSIXError) in
            try UDPSocket(broadcast: true)
        }
    }

    /// A search that opens its socket with `openSocket`, so tests can stand in for the network.
    init(
        port: UInt16 = jellyfinPort,
        broadcastAddresses: [String]?,
        duration: Duration,
        openSocket: @escaping @Sendable () throws(POSIXError) -> any DiscoverySocket,
    ) {
        self.port = port
        self.broadcastAddresses = broadcastAddresses
        self.duration = duration
        self.openSocket = openSocket
    }

    /// Searches once: yields each server as it first answers, so a list can fill in while the
    /// search runs, and finishes when `duration` is up. A server that answers more than once, such
    /// as on two networks, is yielded once, with its first answer. Ending the iteration early,
    /// or cancelling its task, stops the search within a tenth of a second.
    ///
    /// Throws a `ServerDiscoveryError` when the probe can't go out.
    public func servers() -> AsyncThrowingStream<DiscoveredServer, any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: DiscoveredServer.self)
        let stop = StopSignal()
        continuation.onTermination = { _ in stop.raise() }
        // Reading the socket blocks, so it runs on a Dispatch thread rather than in Swift's
        // cooperative pool, whose threads must not block.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try search(until: stop) { continuation.yield($0) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    private func search(
        until stop: StopSignal,
        found: (DiscoveredServer) -> Void,
    ) throws(ServerDiscoveryError) {
        let targets = (broadcastAddresses ?? Self.localBroadcastAddresses()).compactMap {
            UDPSocket.address($0, port: port)
        }
        guard !targets.isEmpty else { throw .noBroadcastAddress }
        let socket: any DiscoverySocket
        do throws(POSIXError) {
            socket = try openSocket()
        } catch {
            throw .socketUnavailable(error.code)
        }
        let failures = targets.compactMap { socket.send(Self.probe, to: $0) }
        if failures.count == targets.count, let failure = failures.first {
            throw .probeNotSent(failure.code)
        }

        let clock = ContinuousClock()
        let deadline = clock.now + duration
        var answered: Set<DiscoveredServer.ID> = []
        while !stop.isRaised {
            let remaining = deadline - clock.now
            guard remaining > .zero else { return }
            guard let reply = socket.receive(timeout: min(remaining, Self.stopCheckInterval)) else { continue }
            if let server = DiscoveredServer(reply: reply.data), answered.insert(server.id).inserted {
                found(server)
            }
        }
    }
}

/// What a search needs from its socket: a `UDPSocket`, or a test's stand-in. It's only used on the
/// search's own thread.
protocol DiscoverySocket: AnyObject {
    /// Sends one datagram. Returns the error when it couldn't be sent.
    func send(_ data: Data, to address: sockaddr_in) -> POSIXError?
    /// Waits up to `timeout` for a datagram and reads it.
    func receive(timeout: Duration) -> UDPSocket.Datagram?
}

extension UDPSocket: DiscoverySocket {}

/// Tells the search, on its Dispatch thread, that nobody is listening any more.
private final class StopSignal: Sendable {
    private let raised = Atomic(false)

    var isRaised: Bool {
        raised.load(ordering: .relaxed)
    }

    func raise() {
        raised.store(true, ordering: .relaxed)
    }
}

@testable import AnemoneJellyfin
import Foundation
import Testing

/// Most searches run on a `FakeDiscoveryNetwork`, which answers each probe at once on the search's
/// own thread; one goes over UDP to a `DiscoveryResponder` on 127.0.0.1. Searches that expect
/// replies listen for 30 s and are stopped as soon as the replies are in, so a busy machine makes
/// them slower but can't make them miss a reply.
struct ServerDiscoveryTests {
    @Test func `a server's reply becomes a discovered server`() async throws {
        let network = FakeDiscoveryNetwork(replies: [discoveryReply()])

        let servers = try await firstServers(1, of: network.discovery())

        #expect(try servers == [DiscoveredServer(
            id: "0f5e1b9a2c3d4e5f6a7b8c9d0e1f2a3b",
            name: "Living Room",
            url: #require(URL(string: "http://192.168.1.20:8096")),
        )])
        #expect(network.probes == [.init(text: "who is JellyfinServer?", destination: "192.168.1.255:7359")])
    }

    @Test func `each server is listed once, with its first answer`() async throws {
        let network = FakeDiscoveryNetwork(replies: [
            discoveryReply(id: "den", name: "Den"),
            discoveryReply(id: "den", name: "Den", address: "http://10.0.0.5:8096"),
            discoveryReply(id: "attic", name: "Attic", address: "https://attic.example.com/jellyfin"),
        ])

        // A second Den would come before Attic.
        let servers = try await firstServers(2, of: network.discovery())

        #expect(servers.map(\.name) == ["Den", "Attic"])
        #expect(servers.map(\.url.absoluteString) == [
            "http://192.168.1.20:8096",
            "https://attic.example.com/jellyfin",
        ])
    }

    @Test func `datagrams that aren't a server's reply are ignored`() async throws {
        let network = FakeDiscoveryNetwork(replies: [
            "who is JellyfinServer?",
            "{}",
            discoveryReply(id: ""),
            discoveryReply(address: nil),
            discoveryReply(address: "not a url"),
            discoveryReply(address: "ftp://192.168.1.20"),
            discoveryReply(id: "real", name: "Real"),
        ])

        // Any of the others taken for a server would come first.
        let servers = try await firstServers(1, of: network.discovery())

        #expect(servers.map(\.id) == ["real"])
    }

    @Test func `a server without a name goes by its host`() throws {
        let unnamed = try #require(DiscoveredServer(reply: Data(discoveryReply(name: nil).utf8)))
        let blank = try #require(DiscoveredServer(reply: Data(discoveryReply(name: " ").utf8)))

        #expect(unnamed.name == "192.168.1.20")
        #expect(blank.name == "192.168.1.20")
    }

    @Test func `the search ends when its time is up`() async throws {
        let network = FakeDiscoveryNetwork()
        let clock = ContinuousClock()
        let started = clock.now

        let servers = try await collect(network.discovery(duration: .milliseconds(300)))

        #expect(servers.isEmpty)
        #expect(clock.now - started >= .milliseconds(300))
        // It listened for its 300 ms and no longer, a tenth of a second at a time so that it
        // notices when it's stopped.
        #expect(network.waits.reduce(.zero, +) <= .milliseconds(300))
        #expect(network.waits.allSatisfy { $0 <= .milliseconds(100) })
        #expect(network.probes.map(\.text) == ["who is JellyfinServer?"])
    }

    @Test func `stopping early closes the search's socket`() async throws {
        let network = FakeDiscoveryNetwork(replies: [discoveryReply()])

        for try await _ in network.discovery(duration: .seconds(30)).servers() {
            break
        }

        await network.socketClosed()
        // It was stopped, rather than running out its 30 s.
        #expect(network.waits.reduce(.zero, +) < .seconds(30))
    }

    @Test func `addresses that aren't IPv4 are skipped`() async throws {
        let network = FakeDiscoveryNetwork(replies: [discoveryReply()])
        let addresses = ["jellyfin.local", "192.168.1.255", "::1", "255.255.255.255"]

        let servers = try await firstServers(1, of: network.discovery(addresses: addresses))

        #expect(servers.count == 1)
        #expect(network.probes.map(\.destination) == ["192.168.1.255:7359", "255.255.255.255:7359"])
    }

    @Test func `the search fails only when the probe can't go to any address`() async throws {
        let addresses = ["192.168.1.255", "255.255.255.255"]
        let nowhere = FakeDiscoveryNetwork(replies: [discoveryReply()], unreachable: Set(addresses))
        let somewhere = FakeDiscoveryNetwork(replies: [discoveryReply()], unreachable: ["255.255.255.255"])

        await #expect(throws: ServerDiscoveryError.probeNotSent(.EHOSTUNREACH)) {
            try await collect(nowhere.discovery(addresses: addresses))
        }
        #expect(try await firstServers(1, of: somewhere.discovery(addresses: addresses)).count == 1)
    }

    @Test func `a socket that can't be opened fails the search`() async {
        let discovery = ServerDiscovery(
            broadcastAddresses: ["192.168.1.255"],
            duration: .seconds(30),
        ) { () throws(POSIXError) in
            throw POSIXError(.EMFILE)
        }

        await #expect(throws: ServerDiscoveryError.socketUnavailable(.EMFILE)) {
            try await collect(discovery)
        }
    }

    @Test func `a server on this device answers over UDP`() async throws {
        let responder = try DiscoveryResponder(replies: [discoveryReply()])
        defer { responder.stop() }
        let discovery = ServerDiscovery(port: responder.port, broadcastAddresses: ["127.0.0.1"], duration: .seconds(30))

        let servers = try await firstServers(1, of: discovery)

        #expect(servers.map(\.name) == ["Living Room"])
        #expect(responder.probes == ["who is JellyfinServer?"])
    }

    @Test(arguments: [[String](), ["jellyfin.local", "fe80::1"]])
    func `with no IPv4 address to send to, the search fails`(addresses: [String]) async {
        await #expect(throws: ServerDiscoveryError.noBroadcastAddress) {
            try await collect(ServerDiscovery(port: 9, broadcastAddresses: addresses))
        }
    }

    @Test func `the probe goes to each network's broadcast address, then the limited broadcast`() {
        let addresses = ServerDiscovery.broadcastAddresses(for: [
            InterfaceAddress(flags: IFF_UP | IFF_BROADCAST | IFF_RUNNING, broadcast: 0xC0A8_01FF),
            InterfaceAddress(flags: IFF_UP | IFF_LOOPBACK | IFF_RUNNING, broadcast: nil),
            // A VPN: its destination address is the other end of the link, not a broadcast.
            InterfaceAddress(flags: IFF_UP | IFF_POINTOPOINT | IFF_RUNNING, broadcast: 0x0A08_0001),
            // Down.
            InterfaceAddress(flags: IFF_BROADCAST, broadcast: 0x0A00_00FF),
            // A second address on the first network.
            InterfaceAddress(flags: IFF_UP | IFF_BROADCAST | IFF_RUNNING, broadcast: 0xC0A8_01FF),
            InterfaceAddress(flags: IFF_UP | IFF_BROADCAST | IFF_RUNNING, broadcast: 0xAC10_FFFF),
        ])

        #expect(addresses == ["192.168.1.255", "172.16.255.255", "255.255.255.255"])
    }

    @Test func `this device's broadcast addresses leave out loopback`() {
        let addresses = ServerDiscovery.localBroadcastAddresses()

        #expect(addresses.last == "255.255.255.255")
        #expect(!addresses.contains { $0.hasPrefix("127.") })
    }

    /// The first `count` servers a search finds. The search is stopped once they're in.
    private func firstServers(_ count: Int, of discovery: ServerDiscovery) async throws -> [DiscoveredServer] {
        var servers: [DiscoveredServer] = []
        for try await server in discovery.servers() {
            servers.append(server)
            if servers.count == count {
                break
            }
        }
        return servers
    }

    private func collect(_ discovery: ServerDiscovery) async throws -> [DiscoveredServer] {
        var servers: [DiscoveredServer] = []
        for try await server in discovery.servers() {
            servers.append(server)
        }
        return servers
    }
}

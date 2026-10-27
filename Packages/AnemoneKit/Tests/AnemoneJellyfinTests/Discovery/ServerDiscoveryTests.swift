@testable import AnemoneJellyfin
import Foundation
import Testing

/// Searches talk to a `DiscoveryResponder` on 127.0.0.1 at a port of the system's choosing, so no
/// test sends a real broadcast or uses Jellyfin's port.
struct ServerDiscoveryTests {
    @Test func `a server's reply becomes a discovered server`() async throws {
        let responder = try DiscoveryResponder(replies: [discoveryReply()])
        defer { responder.stop() }

        let servers = try await search(responder)

        #expect(try servers == [DiscoveredServer(
            id: "0f5e1b9a2c3d4e5f6a7b8c9d0e1f2a3b",
            name: "Living Room",
            url: #require(URL(string: "http://192.168.1.20:8096")),
        )])
        #expect(responder.probes == ["who is JellyfinServer?"])
    }

    @Test func `each server is listed once, with its first answer`() async throws {
        let responder = try DiscoveryResponder(replies: [
            discoveryReply(id: "den", name: "Den"),
            discoveryReply(id: "den", name: "Den", address: "http://10.0.0.5:8096"),
            discoveryReply(id: "attic", name: "Attic", address: "https://attic.example.com/jellyfin"),
        ])
        defer { responder.stop() }

        let servers = try await search(responder)

        #expect(servers.map(\.name) == ["Den", "Attic"])
        #expect(servers.map(\.url.absoluteString) == [
            "http://192.168.1.20:8096",
            "https://attic.example.com/jellyfin",
        ])
    }

    @Test func `datagrams that aren't a server's reply are ignored`() async throws {
        let responder = try DiscoveryResponder(replies: [
            "who is JellyfinServer?",
            "{}",
            discoveryReply(id: ""),
            discoveryReply(address: nil),
            discoveryReply(address: "not a url"),
            discoveryReply(address: "ftp://192.168.1.20"),
            discoveryReply(id: "real", name: "Real"),
        ])
        defer { responder.stop() }

        let servers = try await search(responder)

        #expect(servers.map(\.id) == ["real"])
    }

    @Test func `a server without a name goes by its host`() throws {
        let unnamed = try #require(DiscoveredServer(reply: Data(discoveryReply(name: nil).utf8)))
        let blank = try #require(DiscoveredServer(reply: Data(discoveryReply(name: " ").utf8)))

        #expect(unnamed.name == "192.168.1.20")
        #expect(blank.name == "192.168.1.20")
    }

    @Test func `the search ends when its time is up`() async throws {
        let responder = try DiscoveryResponder()
        defer { responder.stop() }
        let clock = ContinuousClock()
        let started = clock.now

        let servers = try await search(responder, for: .milliseconds(300))

        #expect(servers.isEmpty)
        #expect(clock.now - started < .seconds(3))
        #expect(responder.probes == ["who is JellyfinServer?"])
    }

    @Test func `stopping early closes the search's socket`() async throws {
        let responder = try DiscoveryResponder(replies: [discoveryReply()])
        defer { responder.stop() }
        let discovery = ServerDiscovery(port: responder.port, broadcastAddresses: ["127.0.0.1"], duration: .seconds(30))

        for try await _ in discovery.servers() {
            break
        }

        // The search's port can be bound again once its socket is closed.
        let port = try #require(responder.probePorts.first)
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        var reopened = try? UDPSocket(port: port)
        while reopened == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            reopened = try? UDPSocket(port: port)
        }
        #expect(reopened != nil)
    }

    @Test func `addresses that aren't IPv4 are skipped`() async throws {
        let responder = try DiscoveryResponder(replies: [discoveryReply()])
        defer { responder.stop() }

        let servers = try await search(responder, addresses: ["jellyfin.local", "::1", "127.0.0.1"])

        #expect(servers.count == 1)
        #expect(responder.probes.count == 1)
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

    private func search(
        _ responder: DiscoveryResponder,
        addresses: [String] = ["127.0.0.1"],
        for duration: Duration = .seconds(1),
    ) async throws -> [DiscoveredServer] {
        try await collect(ServerDiscovery(port: responder.port, broadcastAddresses: addresses, duration: duration))
    }

    private func collect(_ discovery: ServerDiscovery) async throws -> [DiscoveredServer] {
        var servers: [DiscoveredServer] = []
        for try await server in discovery.servers() {
            servers.append(server)
        }
        return servers
    }
}

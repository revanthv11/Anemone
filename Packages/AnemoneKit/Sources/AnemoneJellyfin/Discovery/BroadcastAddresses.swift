import Foundation

public extension ServerDiscovery {
    /// Each IPv4 network's broadcast address on this device, then 255.255.255.255: where a search
    /// sends the probe unless told otherwise.
    static func localBroadcastAddresses() -> [String] {
        broadcastAddresses(for: InterfaceAddress.current())
    }
}

extension ServerDiscovery {
    /// The broadcast addresses of the interfaces that are up and can broadcast, without loopback
    /// and point-to-point links such as VPNs, each once, then 255.255.255.255.
    static func broadcastAddresses(for interfaces: [InterfaceAddress]) -> [String] {
        let required = IFF_UP | IFF_BROADCAST
        var addresses: [String] = []
        for interface in interfaces where interface.flags & required == required {
            guard interface.flags & IFF_LOOPBACK == 0, let broadcast = interface.broadcast else { continue }
            let address = InterfaceAddress.dotted(broadcast)
            if !addresses.contains(address) {
                addresses.append(address)
            }
        }
        if !addresses.contains(limitedBroadcastAddress) {
            addresses.append(limitedBroadcastAddress)
        }
        return addresses
    }
}

/// An IPv4 address on one of the device's network interfaces, as `getifaddrs` lists them.
struct InterfaceAddress: Equatable {
    /// `IFF_UP`, `IFF_BROADCAST`, `IFF_LOOPBACK` and the rest.
    var flags: Int32
    /// The network's broadcast address in host byte order, when the interface has one.
    var broadcast: UInt32?

    static func current() -> [InterfaceAddress] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var interfaces: [InterfaceAddress] = []
        var next = list
        while let entry = next?.pointee {
            next = entry.ifa_next
            guard entry.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            interfaces.append(InterfaceAddress(
                flags: Int32(bitPattern: entry.ifa_flags),
                // `ifa_dstaddr` is also `ifa_broadaddr`: the broadcast address on a broadcast interface.
                broadcast: entry.ifa_dstaddr.flatMap(ipv4),
            ))
        }
        return interfaces
    }

    static func dotted(_ address: UInt32) -> String {
        [24, 16, 8, 0].map { String(address >> $0 & 0xFF) }.joined(separator: ".")
    }

    private static func ipv4(_ address: UnsafeMutablePointer<sockaddr>) -> UInt32? {
        guard address.pointee.sa_family == sa_family_t(AF_INET) else { return nil }
        return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
        }
    }
}

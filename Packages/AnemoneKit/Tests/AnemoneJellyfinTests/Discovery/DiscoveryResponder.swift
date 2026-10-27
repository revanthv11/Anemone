@testable import AnemoneJellyfin
import Foundation
import Synchronization

/// A stand-in Jellyfin server on 127.0.0.1, at a port of the system's choosing. It records each
/// probe it hears and answers it with every reply in `replies`, in order, until it's stopped.
///
/// It answers on a thread of its own rather than a Dispatch queue. On a busy machine, such as a CI
/// runner going through the whole suite, Dispatch can hold queued work back for seconds.
final class DiscoveryResponder: Sendable {
    private let socket: UDPSocket
    private let replies: [Data]
    private let heard = Mutex<[String]>([])
    private let stopped = Atomic(false)

    init(replies: [String] = []) throws {
        socket = try UDPSocket(host: "127.0.0.1")
        self.replies = replies.map { Data($0.utf8) }
        Thread { [self] in
            while !stopped.load(ordering: .relaxed) {
                guard let probe = socket.receive(timeout: .milliseconds(50)) else { continue }
                heard.withLock { $0.append(String(data: probe.data, encoding: .utf8) ?? "") }
                for reply in self.replies {
                    _ = socket.send(reply, to: probe.sender)
                }
            }
        }.start()
    }

    var port: UInt16 {
        socket.port
    }

    /// The probes heard so far, as text.
    var probes: [String] {
        heard.withLock { $0 }
    }

    /// Ends the answering loop, which otherwise keeps the responder alive.
    func stop() {
        stopped.store(true, ordering: .relaxed)
    }
}

/// A reply as Jellyfin 12 sends it.
func discoveryReply(
    id: String = "0f5e1b9a2c3d4e5f6a7b8c9d0e1f2a3b",
    name: String? = "Living Room",
    address: String? = "http://192.168.1.20:8096",
) -> String {
    let fields: [String: Any] = [
        "Address": address ?? NSNull(),
        "Id": id,
        "Name": name ?? NSNull(),
        "EndpointAddress": NSNull(),
    ]
    let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
}

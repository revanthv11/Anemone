import os
#if os(tvOS) || os(iOS)
    import Foundation
    import Libmpv
    import QuartzCore

    /// libmpv itself, from MPVKit, drawing into a Metal layer through MoltenVK. Set up the way
    /// MPVKit's tvOS demo sets up its Metal player (`MPVMetalViewController`, LGPL-3.0).
    @MainActor
    final class LibMPVClient: MPVClient {
        /// The properties the engine follows, with the format libmpv sends each in.
        static let observed: [(String, mpv_format)] = [
            ("pause", MPV_FORMAT_FLAG),
            ("paused-for-cache", MPV_FORMAT_FLAG),
            ("seeking", MPV_FORMAT_FLAG),
            ("eof-reached", MPV_FORMAT_FLAG),
            ("video-params/gamma", MPV_FORMAT_STRING),
        ]

        let events: AsyncStream<MPVEvent>
        private let handle: Handle
        private var isDestroyed = false

        /// libmpv drawing into `layer`, with `options` set before it starts. `nil` when libmpv
        /// can't start.
        init?(layer: CAMetalLayer, options: [(String, String)]) {
            guard let mpv = mpv_create() else { return nil }
            // libmpv takes the layer's address as the window to draw in.
            var window = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
            mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &window)
            for (name, value) in options {
                mpv_set_option_string(mpv, name, value)
            }
            #if DEBUG
                mpv_request_log_messages(mpv, "warn")
            #endif
            guard mpv_initialize(mpv) >= 0 else {
                mpv_terminate_destroy(mpv)
                return nil
            }
            for (name, format) in Self.observed {
                mpv_observe_property(mpv, 0, name, format)
            }
            let (events, continuation) = AsyncStream.makeStream(of: MPVEvent.self)
            self.events = events
            handle = Handle(mpv: mpv, events: continuation)
            handle.start()
        }

        func set(_ name: String, _ value: String) {
            guard !isDestroyed else { return }
            mpv_set_property_string(handle.mpv, name, value)
        }

        func command(_ arguments: [String]) {
            guard !isDestroyed else { return }
            let status = Self.withCStrings(arguments) { mpv_command(handle.mpv, $0) }
            if status < 0 {
                Logger.mpv.warning("\(arguments.first ?? "", privacy: .public): \(Self.describe(status))")
            }
        }

        /// `loadfile` answers with the new entry's `playlist_entry_id` (mpv's input.rst).
        func loadFile(_ arguments: [String]) -> Int64? {
            guard !isDestroyed else { return nil }
            var result = mpv_node()
            let status = Self.withCStrings(arguments) { mpv_command_ret(handle.mpv, $0, &result) }
            guard status >= 0 else {
                Logger.mpv.warning("loadfile: \(Self.describe(status), privacy: .public)")
                return nil
            }
            defer { mpv_free_node_contents(&result) }
            guard result.format == MPV_FORMAT_NODE_MAP, let map = result.u.list?.pointee else { return nil }
            for index in 0 ..< Int(map.num) {
                let value = map.values[index]
                if let key = map.keys[index], String(cString: key) == "playlist_entry_id",
                   value.format == MPV_FORMAT_INT64
                {
                    return value.u.int64
                }
            }
            return nil
        }

        func string(_ name: String) -> String? {
            guard !isDestroyed, let value = mpv_get_property_string(handle.mpv, name) else { return nil }
            defer { mpv_free(value) }
            return String(cString: value)
        }

        func destroy() {
            guard !isDestroyed else { return }
            isDestroyed = true
            handle.destroy()
        }

        nonisolated static func describe(_ status: CInt) -> String {
            String(cString: mpv_error_string(status))
        }

        /// libmpv takes a command as a NULL-terminated array of C strings.
        private static func withCStrings(
            _ strings: [String],
            _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>) -> CInt,
        ) -> CInt {
            var pointers: [UnsafePointer<CChar>?] = strings.map { strdup($0).map { UnsafePointer($0) } }
            pointers.append(nil)
            defer {
                for pointer in pointers {
                    free(UnsafeMutablePointer(mutating: pointer))
                }
            }
            return body(&pointers)
        }
    }

    /// The libmpv handle and its event loop, which runs on a queue of its own: libmpv wakes it
    /// from its own threads, and tearing down waits for playback to stop.
    private final class Handle: @unchecked Sendable {
        let mpv: OpaquePointer
        private let events: AsyncStream<MPVEvent>.Continuation
        private let queue = DispatchQueue(label: "mpv.events", qos: .userInitiated)
        /// Only touched on `queue`.
        private var isDestroyed = false

        init(mpv: OpaquePointer, events: AsyncStream<MPVEvent>.Continuation) {
            self.mpv = mpv
            self.events = events
        }

        func start() {
            // Retained until `destroy()` has torn libmpv down, so a wakeup in flight finds it.
            let context = Unmanaged.passRetained(self).toOpaque()
            mpv_set_wakeup_callback(mpv, { context in
                guard let context else { return }
                Unmanaged<Handle>.fromOpaque(context).takeUnretainedValue().wake()
            }, context)
        }

        func destroy() {
            mpv_set_wakeup_callback(mpv, nil, nil)
            queue.async { [self] in
                isDestroyed = true
                mpv_terminate_destroy(mpv)
                events.finish()
                Unmanaged.passUnretained(self).release()
            }
        }

        private func wake() {
            queue.async { [self] in
                drain()
            }
        }

        private func drain() {
            while !isDestroyed, let event = mpv_wait_event(mpv, 0)?.pointee, event.event_id != MPV_EVENT_NONE {
                if let converted = Self.convert(event) {
                    events.yield(converted)
                }
            }
        }

        private static func convert(_ event: mpv_event) -> MPVEvent? {
            switch event.event_id {
            case MPV_EVENT_START_FILE:
                guard let start = event.data?.assumingMemoryBound(to: mpv_event_start_file.self).pointee else {
                    return nil
                }
                return .startFile(entry: start.playlist_entry_id)
            case MPV_EVENT_PLAYBACK_RESTART:
                return .playbackRestart
            case MPV_EVENT_END_FILE:
                guard let end = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee else {
                    return nil
                }
                return .endFile(entry: end.playlist_entry_id, endReason(of: end))
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee else {
                    return nil
                }
                return .property(String(cString: property.name), value(of: property))
            case MPV_EVENT_SHUTDOWN:
                return .shutdown
            case MPV_EVENT_LOG_MESSAGE:
                log(event)
                return nil
            default:
                return nil
            }
        }

        /// libmpv's warnings and errors, in debug builds, for the console.
        private static func log(_ event: mpv_event) {
            guard let message = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee else { return }
            let prefix = String(cString: message.prefix)
            let text = String(cString: message.text)
            Logger.mpv.warning("[\(prefix, privacy: .public)] \(text, privacy: .public)")
        }

        private static func endReason(of end: mpv_event_end_file) -> MPVEndReason {
            switch end.reason {
            case MPV_END_FILE_REASON_EOF:
                .endOfFile
            case MPV_END_FILE_REASON_ERROR:
                .failed(LibMPVClient.describe(end.error))
            default:
                .stopped
            }
        }

        private static func value(of property: mpv_event_property) -> MPVValue {
            guard let data = property.data else { return .none }
            switch property.format {
            case MPV_FORMAT_FLAG:
                return .flag(data.assumingMemoryBound(to: Int32.self).pointee != 0)
            case MPV_FORMAT_DOUBLE:
                return .double(data.assumingMemoryBound(to: Double.self).pointee)
            case MPV_FORMAT_STRING:
                guard let string = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee else {
                    return .none
                }
                return .string(String(cString: string))
            default:
                return .none
            }
        }
    }

#endif

extension Logger {
    /// libmpv's own messages and what the engine notes about them, in debug builds.
    static let mpv = Logger(subsystem: "com.revanthv11.anemone", category: "mpv")
}

import Darwin
import Foundation
import Network
import ParallaxCore

/// Bonjour + AWDL listener. iPhone “Parallax Track” sends LiDAR / TrueDepth packets.
final class TrackerLink: ObservableObject {
    @Published var connected = false
    @Published var status = "iPhone: warte auf Parallax Track"
    @Published var latest: TrackerPacket?
    @Published var sourceLabel = "—"
    @Published var hostName = Host.current().localizedName ?? "Mac"
    @Published var ipAddress = TrackerLink.firstIPv4() ?? "—"

    private var listener: NWListener?
    private var conn: NWConnection?
    private var buf = Data()
    private let decoder = JSONDecoder()

    func start() {
        stop()
        ipAddress = TrackerLink.firstIPv4() ?? "—"
        hostName = Host.current().localizedName ?? "Mac"
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: TrackerPacket.port)!)
            l.service = NWListener.Service(name: hostName, type: TrackerPacket.bonjourType)
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.status = "Warte auf iPhone · \(self?.ipAddress ?? "") :\(TrackerPacket.port)"
                    case .failed(let err):
                        self?.status = "iPhone: \(err.localizedDescription)"
                        self?.connected = false
                    default:
                        break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] c in
                self?.accept(c)
            }
            l.start(queue: .global(qos: .userInitiated))
            listener = l
        } catch {
            status = "iPhone: \(error.localizedDescription)"
        }
    }

    func stop() {
        conn?.cancel()
        conn = nil
        listener?.cancel()
        listener = nil
        connected = false
        latest = nil
    }

    private func accept(_ c: NWConnection) {
        conn?.cancel()
        conn = c
        c.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.connected = true
                    self?.status = "iPhone verbunden — LiDAR/TrueDepth"
                case .failed, .cancelled:
                    self?.connected = false
                    self?.status = "iPhone: getrennt — suche weiter"
                    self?.latest = nil
                default:
                    break
                }
            }
        }
        c.start(queue: .global(qos: .userInitiated))
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, err in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buf.append(data)
                self.drain()
            }
            if isComplete || err != nil {
                DispatchQueue.main.async {
                    self.connected = false
                    self.status = "iPhone: getrennt — suche weiter"
                }
                return
            }
            self.receive(c)
        }
    }

    private func drain() {
        while let range = buf.firstRange(of: Data([0x0A])) {
            let line = buf.subdata(in: 0..<range.lowerBound)
            buf.removeSubrange(0...range.lowerBound)
            guard !line.isEmpty, let pkt = try? decoder.decode(TrackerPacket.self, from: line) else { continue }
            DispatchQueue.main.async {
                self.latest = pkt
                self.sourceLabel = pkt.source
                self.connected = true
                self.status = pkt.source == "lidar" ? "LiDAR live" : "iPhone-Kamera live"
            }
        }
        if buf.count > 16_384 { buf.removeAll() }
    }

    static func firstIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        var fallback: String?
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            guard let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("lo") { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }
            if name.hasPrefix("en") { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }
}

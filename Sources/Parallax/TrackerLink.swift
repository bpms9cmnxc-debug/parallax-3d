import Foundation
import Network
import ParallaxCore

/// Bonjour listener. The iPhone app “Parallax Track” sends LiDAR eye packets.
final class TrackerLink: ObservableObject {
    @Published var connected = false
    @Published var status = "iPhone: warte"
    @Published var latest: TrackerPacket?
    @Published var sourceLabel = "—"

    private var listener: NWListener?
    private var conn: NWConnection?
    private var buf = Data()
    private let decoder = JSONDecoder()

    func start() {
        stop()
        do {
            let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: TrackerPacket.port)!)
            l.service = NWListener.Service(name: "Parallax", type: TrackerPacket.bonjourType)
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.status = "iPhone: bereit (lokal)"
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
        DispatchQueue.main.async {
            self.connected = false
            self.latest = nil
            self.status = "iPhone: aus"
        }
    }

    private func accept(_ c: NWConnection) {
        conn?.cancel()
        conn = c
        c.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.connected = true
                    self?.status = "iPhone LiDAR verbunden"
                case .failed, .cancelled:
                    self?.connected = false
                    self?.status = "iPhone: getrennt"
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
                    self.status = "iPhone: getrennt"
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
            }
        }
        if buf.count > 16_384 { buf.removeAll() }
    }
}

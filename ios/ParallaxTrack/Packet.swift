import Foundation

struct TrackerPacket: Codable {
    var x: Float
    var y: Float
    var z: Float
    var ipd: Float
    var quality: Float
    var source: String

    static let bonjourType = "_parallax._tcp"
    static let port: UInt16 = 47331
}

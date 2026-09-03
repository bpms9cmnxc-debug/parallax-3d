import Foundation

/// One eye sample from Mac webcam or iPhone LiDAR, in metres.
/// Origin: screen centre. +X right, +Y up, +Z toward the viewer.
public struct TrackerPacket: Codable, Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var ipd: Float
    public var quality: Float
    public var source: String

    public init(x: Float, y: Float, z: Float, ipd: Float, quality: Float, source: String) {
        self.x = x
        self.y = y
        self.z = z
        self.ipd = ipd
        self.quality = quality
        self.source = source
    }

    public var eye: EyeWorld { EyeWorld(x: x, y: y, z: z) }

    public static let bonjourType = "_parallax._tcp"
    public static let port: UInt16 = 47331
}

/// Physical mapping stored after the on-screen wizard.
public struct Calibration: Codable, Equatable, Sendable {
    public var screenW: Float
    public var screenH: Float
    /// Face-mid X in the camera frame when the user sat centred.
    public var centerNX: Float
    public var centerNY: Float
    public var ipdAtCenter: Float
    public var zAtCenter: Float
    /// Face-mid X when the head was aligned with the left / right bezel.
    public var leftNX: Float
    public var rightNX: Float
    /// iPhone rear camera above the screen centre (metres). Default: half screen + 4 cm.
    public var iphoneOffsetY: Float
    /// How far the hologram sits behind the glass (metres).
    public var depth: Float
    public var completed: Bool

    public init(
        screenW: Float = 0.30,
        screenH: Float = 0.19,
        centerNX: Float = 0.5,
        centerNY: Float = 0.5,
        ipdAtCenter: Float = 0.08,
        zAtCenter: Float = 0.58,
        leftNX: Float = 0.28,
        rightNX: Float = 0.72,
        iphoneOffsetY: Float = 0.14,
        depth: Float = 0.12,
        completed: Bool = false
    ) {
        self.screenW = screenW
        self.screenH = screenH
        self.centerNX = centerNX
        self.centerNY = centerNY
        self.ipdAtCenter = ipdAtCenter
        self.zAtCenter = zAtCenter
        self.leftNX = leftNX
        self.rightNX = rightNX
        self.iphoneOffsetY = iphoneOffsetY
        self.depth = depth
        self.completed = completed
    }

    public static let empty = Calibration()

    public static func load() -> Calibration {
        guard let data = UserDefaults.standard.data(forKey: "parallax.calibration.v1"),
              let c = try? JSONDecoder().decode(Calibration.self, from: data)
        else { return .empty }
        return c
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "parallax.calibration.v1")
        }
    }
}

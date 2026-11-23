import Foundation

// A saved light setting ("mode") shown in Favorites and Mode Center. Stored in ModeStore; app bindings refer to it by id.
struct LightMode: Codable, Equatable {
    var id: UUID
    var name: String
    var brightness: Int
    var temperature: Int
    var videoMode: Bool

    init(id: UUID = UUID(), name: String, brightness: Int, temperature: Int, videoMode: Bool) {
        self.id = id
        self.name = name
        self.brightness = max(1, min(100, brightness))
        self.temperature = max(2700, min(6500, temperature))
        self.videoMode = videoMode
    }
}

import Foundation

struct DisplayPreset: Codable {
    var name: String
    var builtinEnabled: Bool
    var rotation: Int
    var builtinPrimary: Bool
}

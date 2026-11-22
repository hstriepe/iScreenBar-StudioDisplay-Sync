import Foundation

let benqVendorID = 0x04A5
let iScreenBarProductID = 0x2501
let appleDisplayVendorID: UInt32 = 0x0610
// Studio Display models report different model numbers (0xAE46, 0xAE3A observed).
let studioDisplayProductIDs: Set<UInt32> = [0xAE46, 0xAE3A]
// USB product IDs of the Studio Display HID interfaces (ambient light sensor). Firmware 17.0 changed 0x1118 to 0x1114.
let studioDisplaySensorProductIDs = [0x1118, 0x1114]
let pollInterval: TimeInterval = 0.25
// Wake on presence: the lamp must have stayed off, with no power/auto-light/presence command from the app, this long
// before it turning itself on counts as someone arriving. While the user is still seated (e.g. right after locking),
// the lamp's presence sensor turns it back on within seconds; that must not wake the display (ADR 0008).
let presenceWakeQuietPeriod: TimeInterval = 60
// If the display is still asleep this long after a presence wake request, give up and apply normal sleep sync.
let presenceWakeTimeout: TimeInterval = 10

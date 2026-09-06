import Foundation
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

enum ArmbandBLE {
    static let advertisedName = "BGM-Armband"
    #if canImport(CoreBluetooth)
    static let serviceUUID = CBUUID(string: "C3A10000-8C3A-4B1E-9F2D-B6A0A1B2C3D4")
    static let jsonCharUUID = CBUUID(string: "C3A10001-8C3A-4B1E-9F2D-B6A0A1B2C3D4")
    #endif
}

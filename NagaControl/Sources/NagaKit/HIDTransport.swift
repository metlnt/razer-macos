import Foundation
import IOKit.hid
import IOUSBHost

public enum RazerError: LocalizedError {
    case io(String)
    case status(UInt8, cls: UInt8, id: UInt8)
    case noResponse(cls: UInt8, id: UInt8)

    public var errorDescription: String? {
        switch self {
        case .io(let msg): return String(localized: "HID error: \(msg)")
        case .status(let s, let c, let i):
            let name = [0x03: "fail", 0x04: "timeout", 0x05: "not supported"][Int(s)] ?? String(format: "0x%02x", s)
            return String(format: String(localized: "Command %02X:%02X rejected (%@)"), c, i, name)
        case .noResponse(let c, let i): return String(format: String(localized: "No response to %02X:%02X"), c, i)
        }
    }
}

/// Feature-report I/O as HID class requests on the default control pipe.
///
/// Going through IOUSBHost instead of IOHIDDeviceOpen avoids the Input Monitoring permission.
public final class USBTransport {
    private let device: IOUSBHostDevice
    private let interface: UInt16 = 0

    public init() throws {
        let match = IOUSBHostDevice.__createMatchingDictionary(
            withVendorID: DeviceMonitor.vendorID as NSNumber, productID: DeviceMonitor.productID as NSNumber,
            bcdDevice: nil, deviceClass: nil, deviceSubclass: nil, deviceProtocol: nil, speed: nil, productIDArray: nil)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, match.takeRetainedValue())
        guard service != 0 else { throw RazerError.io(String(localized: "USB device not found")) }
        defer { IOObjectRelease(service) }
        do {
            device = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch {
            throw RazerError.io(String(localized: "couldn’t open USB: \(error.localizedDescription)"))
        }
    }

    deinit { device.destroy() }

    public func setFeature(_ data: [UInt8]) throws {
        let req = IOUSBDeviceRequest(bmRequestType: 0x21, bRequest: 0x09, wValue: 0x0300, wIndex: interface,
                                     wLength: UInt16(data.count))
        var n = 0
        try device.__send(req, data: NSMutableData(bytes: data, length: data.count), bytesTransferred: &n,
                          completionTimeout: 1.0)
    }

    public func getFeature(length: Int) throws -> [UInt8] {
        let req = IOUSBDeviceRequest(bmRequestType: 0xA1, bRequest: 0x01, wValue: 0x0300, wIndex: interface,
                                     wLength: UInt16(length))
        let buf = NSMutableData(length: length)!
        var n = 0
        try device.__send(req, data: buf, bytesTransferred: &n, completionTimeout: 1.0)
        return Array((buf as Data).prefix(n))
    }
}

/// Watches for the Naga Trinity control interface being plugged/unplugged.
public final class DeviceMonitor {
    public static let vendorID = 0x1532
    public static let productID = 0x0067

    private let manager: IOHIDManager
    public var onChange: (() -> Void)?

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: 0x01,
            kIOHIDPrimaryUsageKey: 0x02,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOHIDDeviceCallback = { ctx, _, _, _ in
            let me = Unmanaged<DeviceMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.onChange?() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, cb, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, cb, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    public var isConnected: Bool {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.isEmpty == false
    }
}

import AppKit
import Darwin
import IOKit
import IOKit.serial

/// Use only the configured CH340 callout. Never substitute another USB serial adapter.
final class KVMSerial {
    private var fd: Int32 = -1
    private(set) var error = ""
    var connected: Bool { fd >= 0 }
    private var saved = termios()
    private let pathKey = "KVMSerialPath"
    var selectedPath: String? { UserDefaults.standard.string(forKey:pathKey) }

    func available() -> [String] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [String] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            func prop(_ key: String) -> Any? {
                IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                     IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
            }
            if (prop("idVendor") as? NSNumber)?.intValue == 0x1a86,
               (prop("idProduct") as? NSNumber)?.intValue == 0x7523,
               let path = prop(kIOCalloutDeviceKey) as? String { result.append(path) }
        }
        return result.sorted()
    }
    func select(_ path: String) { closePort(); UserDefaults.standard.set(path, forKey:pathKey); connect() }
    func connect() {
        guard !connected else { return }
        guard let path = selectedPath, available().contains(path) else { error = "请从「控制」菜单选择 NanoKVM 的 USB 串口。"; return }
        let port = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard port >= 0 else { error = "无法打开串口，请关闭浏览器里的 NanoKVM 控制页，然后重连。"; return }
        var config = termios()
        guard ioctl(port, TIOCEXCL) == 0, tcgetattr(port,&config) == 0 else {
            Darwin.close(port); error = "无法独占串口，请关闭其他 NanoKVM 控制窗口。"; return
        }
        saved = config
        cfmakeraw(&config)
        config.c_cflag |= tcflag_t(CLOCAL | CREAD)
        cfsetspeed(&config, speed_t(B57600))
        guard tcsetattr(port,TCSANOW,&config) == 0 else { Darwin.close(port); error = "无法配置 NanoKVM 串口。"; return }
        fd = port; error = ""
    }
    func closePort() {
        guard fd >= 0 else { return }
        tcdrain(fd); tcsetattr(fd,TCSANOW,&saved); Darwin.close(fd); fd = -1
    }
    private func send(_ command: UInt8,_ data: [UInt8]) {
        guard connected else { return }
        var frame: [UInt8] = [0x57,0xab,0,command,UInt8(data.count)]
        frame += data
        frame.append(frame.reduce(0,&+))
        let written = frame.withUnsafeBytes { Darwin.write(fd,$0.baseAddress!,frame.count) }
        if written != frame.count { closePort(); error = "串口传输中断。请在「控制」菜单中重连。" }
    }
    func keyboard(_ modifiers: UInt8,_ keys: [UInt8]) {
        let down = Array(keys.prefix(6))
        send(2,[modifiers,0] + down + Array(repeating:0,count:6-down.count))
    }
    func mouse(_ point: CGPoint, buttons: UInt8, wheel: Int = 0) {
        func coord(_ v: CGFloat) -> [UInt8] {
            let n = Int((min(1,max(0,v)) * 4095).rounded())
            return [UInt8(n & 255),UInt8(n >> 8)]
        }
        send(4,[2,buttons]+coord(point.x)+coord(point.y)+[UInt8(bitPattern:Int8(clamping:wheel))])
    }
}

import AppKit
import DiskArbitration
import Darwin

struct TransferProblem: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct USBVolume {
    let root: URL
    let name: String
    let uuid: String?
    let device: dev_t

    static func mounted() -> [USBVolume] {
        let keys: Set<URLResourceKey> = [.volumeIsReadOnlyKey, .volumeIsLocalKey, .volumeUUIDStringKey, .volumeLocalizedNameKey]
        guard let session = DASessionCreate(nil),
              let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsLocal == true, values.volumeIsReadOnly == false,
                  let disk = DADiskCreateFromVolumePath(nil, session, url as CFURL),
                  let info = DADiskCopyDescription(disk) as? [String: Any],
                  info[kDADiskDescriptionDeviceProtocolKey as String] as? String == "USB",
                  info[kDADiskDescriptionDeviceInternalKey as String] as? Bool != true,
                  let mount = info[kDADiskDescriptionVolumePathKey as String] as? URL,
                  mount.standardizedFileURL.path == url.standardizedFileURL.path else { return nil }
            var st = stat()
            guard stat(url.path, &st) == 0 else { return nil }
            return USBVolume(root: url, name: values.volumeLocalizedName ?? url.lastPathComponent,
                             uuid: values.volumeUUIDString, device: st.st_dev)
        }.sorted { $0.root.path < $1.root.path }
    }

    func stillMounted() -> Bool {
        Self.mounted().contains { $0.root == root && $0.device == device && $0.uuid == uuid }
    }
}

/// Keep the batch hidden until every copy succeeds. Publish it with one rename on the same volume.
struct USBBatch {
    static func copy(_ sources: [URL], to root: URL, device: dev_t, validate: () throws -> Void) throws -> URL {
        let fm = FileManager.default
        guard !sources.isEmpty else { throw TransferProblem("请从 Finder 拖入文件或文件夹。") }
        try validate()
        let mount = root.resolvingSymlinksInPath().standardizedFileURL.path
        for source in sources {
            let path = source.resolvingSymlinksInPath().standardizedFileURL.path
            var st = stat()
            guard lstat(source.path, &st) == 0 else { throw TransferProblem("找不到「\(source.lastPathComponent)」，请重新拖入。") }
            guard st.st_dev != device, path != "/", path != mount, !mount.hasPrefix(path + "/") else {
                throw TransferProblem("请从中转 U 盘以外的位置拖入文件，并避免选择包含目标 U 盘的文件夹。")
            }
        }
        let id = UUID().uuidString
        let stage = root.appendingPathComponent(".NanoKVM-\(id).partial", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        do {
            for source in sources {
                try validate()
                var name = source.lastPathComponent
                var n = 1
                let ext = source.pathExtension
                while fm.fileExists(atPath: stage.appendingPathComponent(name).path) {
                    n += 1
                    let stem = source.deletingPathExtension().lastPathComponent
                    name = ext.isEmpty ? "\(source.lastPathComponent) (\(n))" : "\(stem) (\(n)).\(ext)"
                }
                try fm.copyItem(at: source, to: stage.appendingPathComponent(name))
            }
            try validate()
            let date = DateFormatter()
            date.locale = Locale(identifier: "en_US_POSIX")
            date.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let batch = root.appendingPathComponent("NanoKVM-\(date.string(from: Date()))-\(id.prefix(8))", isDirectory: true)
            try fm.moveItem(at: stage, to: batch)
            return batch
        } catch {
            if (try? validate()) != nil { try? fm.removeItem(at: stage) }
            throw error
        }
    }

    static func transfer(_ sources: [URL], to volume: USBVolume, validate: () throws -> Void,
                         eject: (URL) throws -> Void) throws -> String {
        let batch = try copy(sources, to: volume.root, device: volume.device, validate: validate)
        do {
            try validate()
            try eject(volume.root)
        } catch {
            throw TransferProblem("文件已经复制到「\(batch.lastPathComponent)」，但未确认安全推出。请保持 H，在 Finder 中推出「\(volume.name)」后再拨到 T。\n\(error.localizedDescription)")
        }
        return batch.lastPathComponent
    }
}

final class USBTransfer {
    let window: NSWindow
    private let diskKey = "TransferVolumeUUID"
    private var selectedMount: USBVolume?
    private var savedUUID: String? { UserDefaults.standard.string(forKey: diskKey) }
    private(set) var busy = false
    var canDrop: Bool { !busy && window.attachedSheet == nil }
    init(window: NSWindow) { self.window = window }

    @discardableResult
    func accept(_ urls: [URL]) -> Bool {
        guard canDrop, !urls.isEmpty else { return false }
        busy = true
        DispatchQueue.main.async {
            let disks = USBVolume.mounted()
            if let uuid = self.savedUUID {
                let matches = disks.filter { $0.uuid == uuid }
                if matches.count == 1 {
                    self.start(urls, volume: matches[0])
                } else {
                    self.busy = false
                    self.alert("找不到已选的中转 U 盘", "请接回原 U 盘，拨到 H 后重新拖入。要换盘，请使用「控制 → 选择中转 U 盘」。")
                }
            } else if let selected = self.selectedMount, selected.stillMounted() {
                self.start(urls, volume: selected)
            } else {
                self.choose(from: disks, sources: urls)
            }
        }
        return true
    }

    func chooseDrive() {
        guard canDrop else { return }
        busy = true
        choose(from: USBVolume.mounted(), sources: [])
    }

    private func choose(from disks: [USBVolume], sources: [URL]) {
        guard !disks.isEmpty else {
            busy = false
            alert("没有可写的 USB 存储盘", "把 U 盘插到 NanoKVM 的 USB-A 口，将拨键切到 H，等 Finder 显示 U 盘后再试。")
            return
        }
        let panel = NSAlert()
        panel.messageText = "选择 NanoKVM 上的中转 U 盘"
        panel.informativeText = "请核对卷名。文件会复制到此盘，每批完成后会推出整个 USB 设备。"
        let list = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
        for disk in disks { list.addItem(withTitle: disk.root.path) }
        panel.accessoryView = list
        panel.addButton(withTitle: sources.isEmpty ? "选择" : "复制到此盘")
        panel.addButton(withTitle: "取消")
        panel.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { self.busy = false; return }
            let volume = disks[list.indexOfSelectedItem]
            self.selectedMount = volume
            UserDefaults.standard.set(volume.uuid, forKey: self.diskKey)
            if sources.isEmpty { self.busy = false }
            else { self.start(sources, volume: volume) }
        }
    }

    private func start(_ sources: [URL], volume: USBVolume) {
        let progress = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 92),
                               styleMask: [.titled], backing: .buffered, defer: false)
        progress.title = "复制到「\(volume.name)」"
        let text = NSTextField(labelWithString: "正在传送 \(sources.count) 项，请保持拨键在 H。")
        text.frame = NSRect(x: 20, y: 46, width: 320, height: 22)
        progress.contentView?.addSubview(text)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 320, height: 14))
        bar.style = .bar; bar.isIndeterminate = true
        progress.contentView?.addSubview(bar); bar.startAnimation(nil)
        window.beginSheet(progress)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try USBBatch.transfer(sources, to: volume, validate: {
                    guard volume.stillMounted() else { throw TransferProblem("所选 U 盘已断开或已更换，传输已中止。") }
                }, eject: { try NSWorkspace.shared.unmountAndEjectDevice(at: $0) })
            }
            DispatchQueue.main.async {
                self.window.endSheet(progress)
                progress.orderOut(nil)
                self.busy = false
                switch result {
                case .success(let name):
                    self.selectedMount = nil
                    self.alert("U 盘已安全推出，现在可以拨到 T", "在 Windows 的 U 盘中打开「\(name)」。下次传输前，请先在 Windows 安全弹出 U 盘，再拨回 H。")
                case .failure(let error):
                    self.alert("传送未完成", error.localizedDescription)
                }
            }
        }
    }
    private func alert(_ title: String, _ detail: String) {
        let panel = NSAlert()
        panel.messageText = title; panel.informativeText = detail
        panel.addButton(withTitle: "好"); panel.beginSheetModal(for: window)
    }
}

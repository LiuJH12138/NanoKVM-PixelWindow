import AppKit
import AVFoundation

final class PixelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PixelView: NSView {
    let serial: KVMSerial
    let preview: AVCaptureVideoPreviewLayer
    private var keys: [UInt8] = []
    private var buttons: UInt8 = 0
    private var lastPoint = CGPoint(x:0.5,y:0.5)
    private var tracking: NSTrackingArea?
    private var modifiers: UInt8 = 0
    private var wheelFraction: CGFloat = 0
    private var drag: (handle: ResizeHandle, frame: NSRect, start: NSPoint, area: NSRect)?
    var canDropFiles: (() -> Bool)?
    var onDropFiles: (([URL]) -> Bool)?
    var onResize: ((CGFloat) -> Void)?
    var onRestore: (() -> Void)?
    var aspect: CGFloat = 16.0 / 9.0
    var live = false
    init(session: AVCaptureSession, serial: KVMSerial) {
        self.serial = serial
        preview = AVCaptureVideoPreviewLayer(session:session)
        super.init(frame:.zero)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspect
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func files(from board: NSPasteboard) -> [URL] {
        board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canDropFiles?() == true, sender.draggingSourceOperationMask.contains(.copy),
              !files(from: sender.draggingPasteboard).isEmpty else { return [] }
        return .copy
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = files(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        releaseInput()
        return onDropFiles?(urls) == true
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        preview.frame = bounds
        window?.invalidateCursorRects(for: self)
        preview.contentsScale = window?.backingScaleFactor ?? 1
        CATransaction.commit()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tracking { removeTrackingArea(old) }
        let area = NSTrackingArea(rect:.zero, options:[.activeInKeyWindow,.mouseMoved,.inVisibleRect,.cursorUpdate],owner:self,userInfo:nil)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if live && serial.connected {
            addCursorRect(bounds.insetBy(dx: ResizeHandle.inset, dy: ResizeHandle.inset),cursor:NSCursor(image:NSImage(size:NSSize(width:1,height:1)),hotSpot:.zero))
        }
        for (handle, rect) in ResizeHandle.zones(in: bounds) {
            addCursorRect(rect, cursor: handle.cursor)
        }
    }
    private func handle(at event: NSEvent) -> ResizeHandle? {
        let p = convert(event.locationInWindow, from: nil)
        return ResizeHandle.zones(in: bounds).first { $0.1.contains(p) }?.0
    }
    func releaseInput() {
        drag = nil
        if !keys.isEmpty || modifiers != 0 { serial.keyboard(0,[]) }
        if buttons != 0 { serial.mouse(lastPoint,buttons:0) }
        keys.removeAll(); buttons=0; modifiers=0; wheelFraction=0
    }
    private func update(_ e:NSEvent) {
        guard live, window?.isKeyWindow == true, bounds.width > 0, bounds.height > 0 else {return}
        let p = convert(e.locationInWindow,from:nil)
        lastPoint = CGPoint(x:p.x/bounds.width,y:1-p.y/bounds.height)
        serial.mouse(lastPoint,buttons:buttons)
    }
    override func mouseMoved(with e:NSEvent) {
        if handle(at: e) == nil { update(e) }
    }
    override func mouseDragged(with e:NSEvent) {
        guard let drag, let window else {
            if buttons & 1 != 0 { update(e) }
            return
        }
        let p = window.convertPoint(toScreen: e.locationInWindow)
        let delta = NSPoint(x: p.x - drag.start.x, y: p.y - drag.start.y)
        let frame = drag.handle.resized(drag.frame, delta: delta, aspect: aspect, area: drag.area)
        window.setFrame(frame, display: true)
        onResize?(window.frame.width)
    }
    override func rightMouseDragged(with e:NSEvent) { update(e) }
    override func otherMouseDragged(with e:NSEvent) { update(e) }
    override func mouseDown(with e:NSEvent) {
        if e.modifierFlags.contains(.option) {
            releaseInput(); window?.performDrag(with:e); return
        }
        if let handle = handle(at: e), let window, let screen = window.screen {
            if e.clickCount == 2 { onRestore?(); return }
            drag = (handle, window.frame, window.convertPoint(toScreen: e.locationInWindow), screen.visibleFrame)
            return
        }
        buttons |= 1; update(e)
    }
    override func mouseUp(with e:NSEvent) { drag = nil; if buttons & 1 != 0 { buttons &= ~1; update(e) } }
    override func rightMouseDown(with e:NSEvent) { buttons |= 2; update(e) }
    override func rightMouseUp(with e:NSEvent) { buttons &= ~2; update(e) }
    override func otherMouseDown(with e:NSEvent) { if e.buttonNumber == 2 {buttons |= 4;update(e)} }
    override func otherMouseUp(with e:NSEvent) { if e.buttonNumber == 2 {buttons &= ~4;update(e)} }
    override func scrollWheel(with e:NSEvent) {
        guard live else {return}
        let delta = e.scrollingDeltaY * (e.isDirectionInvertedFromDevice ? -1 : 1)
        wheelFraction += e.hasPreciseScrollingDeltas ? delta/12 : delta
        let steps = Int(wheelFraction)
        if steps != 0 { wheelFraction -= CGFloat(steps);serial.mouse(lastPoint,buttons:buttons,wheel:steps) }
    }
    // Apple virtual key codes mapped to USB HID keyboard usages.
    private static let usages:[UInt16:UInt8] = [
        0:4,1:22,2:7,3:9,4:11,5:10,6:29,7:27,8:6,9:25,10:100,11:5,
        12:20,13:26,14:8,15:21,16:28,17:23,18:30,19:31,20:32,21:33,22:35,23:34,
        24:46,25:38,26:36,27:45,28:37,29:39,30:48,31:18,32:24,33:47,34:12,
        35:19,36:40,37:15,38:13,39:52,40:14,41:51,42:49,43:54,44:56,45:17,
        46:16,47:55,48:43,49:44,50:53,51:42,53:41,65:99,67:85,69:87,71:83,
        75:84,76:88,78:86,81:103,82:98,83:89,84:90,85:91,86:92,87:93,88:94,
        89:95,91:96,92:97,96:62,97:63,98:64,99:60,100:65,101:66,103:68,105:104,
        106:107,107:105,109:67,111:69,113:106,114:73,115:74,116:75,117:76,118:61,
        119:77,120:59,121:78,122:58,123:80,124:79,125:81,126:82
    ]
    private func flags(_ e:NSEvent)->UInt8 {
        let f=e.modifierFlags
        var m:UInt8=0
        if f.contains(.control){m |= 1}
        if f.contains(.shift){m |= 2}
        if f.contains(.option){m |= 4}
        if f.contains(.command){m |= 8}
        return m
    }
    override func flagsChanged(with e:NSEvent) {
        guard live else{return}
        if e.keyCode == 57 { serial.keyboard(flags(e),[57]);serial.keyboard(flags(e),keys);return }
        modifiers=flags(e);serial.keyboard(modifiers,keys)
    }
    override func keyDown(with e:NSEvent) {
        guard live,let k=Self.usages[e.keyCode],!e.isARepeat else{return}
        if !keys.contains(k){keys.append(k)}
        modifiers=flags(e);serial.keyboard(modifiers,keys)
    }
    override func keyUp(with e:NSEvent) {
        guard live,let k=Self.usages[e.keyCode] else{return}
        keys.removeAll{$0==k};modifiers=flags(e);serial.keyboard(modifiers,keys)
    }
}

import AppKit
import AVFoundation
import CoreGraphics

final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let capture=Capture(), serial=KVMSerial()
    var window:PixelWindow!
    var video:PixelView!
    var pixels=CGSize(width:1920,height:1080)
    var zoom: CGFloat = 1
    let controls=NSMenu(title:"控制")
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu=NSMenu()
        let appMenu=NSMenu()
        let appItem=menu.addItem(withTitle:"NanoKVM",action:nil,keyEquivalent:"")
        appItem.submenu=appMenu
        appMenu.addItem(withTitle:"退出 NanoKVM 原生窗口",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let close=appMenu.addItem(withTitle:"关闭窗口",action:#selector(closeWindow),keyEquivalent:"w");close.target=self
        let item=menu.addItem(withTitle:"控制",action:nil,keyEquivalent:"");item.submenu=controls;controls.delegate=self
        NSApp.mainMenu=menu
        let mouse=NSEvent.mouseLocation
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(mouse)}) ?? NSScreen.main else{return}
        let area=screen.visibleFrame
        let saved=UserDefaults.standard.string(forKey:"frame").map(NSRectFromString)
        let center=saved.flatMap{screen.frame.contains(NSPoint(x:$0.midX,y:$0.midY)) ? NSPoint(x:$0.midX,y:$0.midY) : nil} ?? NSPoint(x:area.midX,y:area.midY)
        window=PixelWindow(contentRect:fittedFrame(pixels:pixels,area:screen.visibleFrame,scale:screen.backingScaleFactor,center:center),styleMask:[.borderless],backing:.buffered,defer:false)
        window.title="NanoKVM 原生窗口";window.isOpaque=true;window.hasShadow=false;window.backgroundColor = .black
        window.isReleasedWhenClosed=false;window.acceptsMouseMovedEvents=true
        video=PixelView(session:capture.session,serial:serial)
        video.onResize = { [weak self] width in
            guard let self else { return }
            self.zoom = width * self.window.backingScaleFactor / self.pixels.width
        }
        video.onRestore = { [weak self] in
            self?.zoom = 1
            self?.fit()
        }
        window.contentView=video;window.delegate=self
        window.makeKeyAndOrderFront(nil);window.makeFirstResponder(video)
        NSApp.activate(ignoringOtherApps:true)
        capture.onSize={ [weak self] size in
            guard let self else {return}; self.pixels=size;self.video.aspect=size.width/size.height;self.video.live=true;self.fit()
            self.serial.connect();self.window.invalidateCursorRects(for:self.video)
            NSLog("NanoKVM ready; capture %.0fx%.0f, backing %@, serial %@",size.width,size.height,NSStringFromRect(self.video.convertToBacking(self.video.bounds)),self.serial.connected ? "connected":"unavailable")
            if !self.serial.connected {self.notice(self.serial.error)}
        }
        capture.onError={ [weak self] message in self?.notice(message) }
        NotificationCenter.default.addObserver(self,selector:#selector(layoutChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(captureLost),name:AVCaptureDevice.wasDisconnectedNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(captureStopped),name:AVCaptureSession.runtimeErrorNotification,object:capture.session)
        capture.start()
    }
    func fit() {
        guard let screen=window.screen ?? NSScreen.main else{return}
        let f=window.frame
        let scaledPixels = CGSize(width: pixels.width * zoom, height: pixels.height * zoom)
        let target=fittedFrame(pixels:scaledPixels,area:screen.visibleFrame,scale:screen.backingScaleFactor,center:NSPoint(x:f.midX,y:f.midY))
        if !f.equalTo(target){window.setFrame(target,display:true)}
        video.needsLayout=true
    }
    @objc func captureLost(_ n:Notification) {
        guard let device=n.object as? AVCaptureDevice,device.modelID.contains("VendorID_13407 ProductID_8497") else{return}
        DispatchQueue.main.async { self.video.releaseInput();self.video.live=false; self.notice("NanoKVM 已断开，请接回 Host USB 线并重新打开窗口。") }
    }
    @objc func captureStopped(_ n:Notification) {
        DispatchQueue.main.async { self.video.releaseInput();self.video.live=false;self.notice("视频采集中断，请检查 NanoKVM 的 USB 连接后重新打开窗口。") }
    }
    @objc func layoutChanged(){fit()}
    func windowDidChangeBackingProperties(_ n:Notification){fit()}
    func windowDidChangeScreen(_ n:Notification){fit()}
    func windowDidMove(_ n:Notification){ UserDefaults.standard.set(NSStringFromRect(window.frame),forKey:"frame") }
    func windowDidResignKey(_ n:Notification){video.releaseInput()}
    func windowWillClose(_ n:Notification){NSApp.terminate(nil)}
    func applicationWillTerminate(_ n:Notification){video.releaseInput();serial.closePort()}
    @objc func closeWindow(){window.close()}
    func notice(_ text:String){
        guard window.attachedSheet == nil else{return}
        let a=NSAlert();a.messageText="NanoKVM 原生窗口";a.informativeText=text;a.addButton(withTitle:"好");a.beginSheetModal(for:window)
    }
    func menuNeedsUpdate(_ menu:NSMenu) {
        controls.removeAllItems()
        for path in serial.available(){
            let item=controls.addItem(withTitle:"连接 "+path,action:#selector(portSelected(_:)),keyEquivalent:"")
            item.target=self;item.representedObject=path
            item.state=(serial.connected && path==serial.selectedPath) ? .on:.off
        }
        if controls.items.isEmpty {controls.addItem(withTitle:"未找到 NanoKVM 串口",action:nil,keyEquivalent:"")}
    }
    @objc func portSelected(_ sender:NSMenuItem){
        guard let path=sender.representedObject as? String else{return}
        video.releaseInput();serial.select(path);window.invalidateCursorRects(for:video)
        if !serial.connected{notice(serial.error)}
    }
}
let app=NSApplication.shared
let controller=Controller()
app.setActivationPolicy(.regular)
app.delegate=controller
app.run()

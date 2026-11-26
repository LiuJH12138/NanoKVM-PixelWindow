import AppKit

func fittedFrame(pixels:CGSize,area:NSRect,scale:CGFloat,center:NSPoint)->NSRect {
    let native=CGSize(width:pixels.width/scale,height:pixels.height/scale)
    let fit=min(1,area.width/native.width,area.height/native.height)
    let w=floor(native.width*fit*scale)/scale, h=floor(native.height*fit*scale)/scale
    let x=min(max(area.minX,center.x-w/2),area.maxX-w)
    let y=min(max(area.minY,center.y-h/2),area.maxY-h)
    return NSRect(x:(x*scale).rounded()/scale,y:(y*scale).rounded()/scale,width:w,height:h)
}

/// A side or corner of the borderless window. Coordinates use AppKit's upward y-axis.
struct ResizeHandle: Equatable {
    let x: CGFloat
    let y: CGFloat
    static let inset: CGFloat = 7

    static func zones(in bounds: NSRect) -> [(ResizeHandle, NSRect)] {
        let b = inset
        let xs = [bounds.minX, bounds.minX + b, bounds.maxX - b, bounds.maxX]
        let ys = [bounds.minY, bounds.minY + b, bounds.maxY - b, bounds.maxY]
        var zones: [(ResizeHandle, NSRect)] = []
        for i in 0..<3 {
            for j in 0..<3 where i != 1 || j != 1 {
                let region = NSRect(x: xs[i], y: ys[j], width: xs[i+1]-xs[i], height: ys[j+1]-ys[j])
                zones.append((ResizeHandle(x: CGFloat(i-1), y: CGFloat(j-1)), region))
            }
        }
        return zones
    }

    var cursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch (x,y) {
            case (-1,-1): position = .bottomLeft
            case (-1, 1): position = .topLeft
            case ( 1,-1): position = .bottomRight
            case ( 1, 1): position = .topRight
            case (-1, 0): position = .left
            case ( 1, 0): position = .right
            case ( 0,-1): position = .bottom
            default:      position = .top
            }
            return .frameResize(position: position, directions: .all)
        }
        return x == 0 ? .resizeUpDown : .resizeLeftRight
    }

    func resized(_ frame: NSRect, delta: NSPoint, aspect: CGFloat, area: NSRect) -> NSRect {
        let anchorX = frame.midX - x * frame.width/2
        let anchorY = frame.midY - y * frame.height/2
        func span(anchor: CGFloat, direction: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
            if direction < 0 { return anchor - low }
            if direction > 0 { return high - anchor }
            return 2 * min(anchor - low, high - anchor)
        }
        let limitW = span(anchor: anchorX, direction: x, low: area.minX, high: area.maxX)
        let limitH = span(anchor: anchorY, direction: y, low: area.minY, high: area.maxY)
        // Project the pointer movement onto the permitted drag direction.
        let dy = y / aspect
        let change = (x * delta.x + dy * delta.y) / (x*x + dy*dy)
        let width = min(max(160, frame.width + change), max(1, min(limitW, limitH * aspect)))
        let height = width / aspect
        return NSRect(x: anchorX + (x-1)*width/2, y: anchorY + (y-1)*height/2, width: width, height: height)
    }
}

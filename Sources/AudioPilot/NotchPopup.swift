import AppKit
import SwiftUI

/// Schwarzes Popup, für das die Notch seitlich aufgeht (wie macOS „Stromsparmodus“): links Symbol + Titel,
/// rechts Knopf bzw. Status – gleiche Höhe wie die Notch, nichts hängt nach unten.
/// `duration: .infinity` → bleibt, bis man klickt oder ✕ drückt.
/// Das Fenster hat gleich die Endgröße; die Form selbst federt in SwiftUI aus der Notch auf und wieder zu.
@MainActor
final class NotchPopup {
    static let shared = NotchPopup()
    private var panel: NSPanel?
    private var model: PopupModel?
    private var hideWork: DispatchWorkItem?

    func show(symbol: String, title: String, subtitle: String, action: (title: String, run: () -> Void)? = nil, duration: Double = 6) {
        hide(animated: false)
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let notch = max(screen.safeAreaInsets.top, 32)
        var notchWidth: CGFloat = 200
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchWidth = min(max(screen.frame.width - l.width - r.width, 120), 300)
        }
        let m = PopupModel(notch: NSSize(width: notchWidth, height: notch),
                           open: NSSize(width: notchWidth + 2 * PopupModel.wing, height: notch))
        let view = PopupView(model: m, symbol: symbol, title: title, subtitle: subtitle,
                             actionTitle: action?.title,
                             onAction: { [weak self] in action?.run(); self?.hide() },
                             onClose: { [weak self] in self?.hide() })
        // Platz für Schultern und Schatten rundherum.
        let size = NSSize(width: m.open.width + 2 * PopupModel.shoulder + 40, height: m.open.height + 24)
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Über dem schwarzen Notch-Streifen, den macOS im Vollbild oben einblendet (Ebene 26) – .statusBar (25) läge darunter.
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: view)
        p.orderFrontRegardless()
        panel = p
        model = m
        DispatchQueue.main.async { withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { m.isOpen = true } }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        if duration.isFinite { DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work) }
    }

    func hide(animated: Bool = true) {
        hideWork?.cancel()
        guard let p = panel else { return }
        panel = nil
        let m = model
        model = nil
        guard animated, let m else { p.orderOut(nil); return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { m.isOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { p.orderOut(nil) }
    }
}

@MainActor
private final class PopupModel: ObservableObject {
    static let shoulder: CGFloat = 8
    static let wing: CGFloat = 215   // Breite links/rechts neben der Notch
    let notch: NSSize, open: NSSize
    @Published var isOpen = false
    init(notch: NSSize, open: NSSize) { self.notch = notch; self.open = open }
}

/// Notch-Form: oben nach außen geschwungene Schultern, die in die Bildschirmkante übergehen, unten große Rundung.
private struct NotchShape: Shape {
    var shoulder: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, radius) }
        set { shoulder = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let s = shoulder, w = rect.width, h = rect.height
        let r = min(radius, (w - 2 * s) / 2, h - s)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: s, y: s), control: CGPoint(x: s, y: 0))
        p.addLine(to: CGPoint(x: s, y: h - r))
        p.addQuadCurve(to: CGPoint(x: s + r, y: h), control: CGPoint(x: s, y: h))
        p.addLine(to: CGPoint(x: w - s - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - s, y: h - r), control: CGPoint(x: w - s, y: h))
        p.addLine(to: CGPoint(x: w - s, y: s))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - s, y: 0))
        p.closeSubpath()
        return p.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct PopupView: View {
    @ObservedObject var model: PopupModel
    let symbol: String, title: String, subtitle: String
    let actionTitle: String?
    let onAction: () -> Void, onClose: () -> Void

    var body: some View {
        let open = model.isOpen
        let size = open ? model.open : model.notch
        let s = PopupModel.shoulder
        ZStack(alignment: .top) {
            NotchShape(shoulder: s, radius: min(14, model.notch.height / 2.4))
                .fill(.black)
                .frame(width: size.width + 2 * s, height: size.height)
                .shadow(color: .black.opacity(open ? 0.3 : 0), radius: 8, y: 2)
            HStack(spacing: 0) {
                left.frame(width: PopupModel.wing - 18, alignment: .leading)
                Spacer(minLength: model.notch.width)
                right.frame(width: PopupModel.wing - 18, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .frame(width: model.open.width, height: model.notch.height)
            .opacity(open ? 1 : 0)
            .blur(radius: open ? 0 : 4)
            .animation(open ? .easeOut(duration: 0.25).delay(0.12) : .easeIn(duration: 0.1), value: open)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var left: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.white)
            Text(verbatim: title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
        }
    }

    private var right: some View {
        HStack(spacing: 8) {
            if let actionTitle {
                Button(action: onAction) {
                    Text(verbatim: actionTitle).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(.white)).foregroundStyle(.black)
                }.buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                }.buttonStyle(.plain)
            } else {
                Text(verbatim: subtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
        }
    }
}

import AppKit
import SwiftUI

/// Kleines schwarzes Popup, das aus der Notch „herauswächst“ (wie bei AirPods am iPhone).
/// `duration: .infinity` → bleibt, bis man klickt oder ✕ drückt.
/// Das Fenster hat gleich die Endgröße; die Form selbst federt in SwiftUI aus der Notch auf und wieder hinein.
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
                           open: NSSize(width: 380, height: notch + 64))
        let view = PopupView(model: m, symbol: symbol, title: title, subtitle: subtitle,
                             actionTitle: action?.title,
                             onAction: { [weak self] in action?.run(); self?.hide() },
                             onClose: { [weak self] in self?.hide() })
        // Platz für Schultern und Schatten rundherum.
        let size = NSSize(width: m.open.width + 2 * PopupModel.shoulder + 40, height: m.open.height + 30)
        let p = NSPanel(contentRect: NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                                            width: size.width, height: size.height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
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
    static let shoulder: CGFloat = 12
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
            NotchShape(shoulder: open ? s : 6, radius: open ? 26 : 10)
                .fill(.black)
                .frame(width: size.width + 2 * s, height: size.height)
                .shadow(color: .black.opacity(open ? 0.35 : 0), radius: 12, y: 4)
            content
                .padding(.horizontal, 20)
                .padding(.top, model.notch.height)
                .frame(width: model.open.width, height: model.open.height)
                .opacity(open ? 1 : 0)
                .scaleEffect(open ? 1 : 0.6, anchor: .top)
                .blur(radius: open ? 0 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(verbatim: subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let actionTitle {
                Button(action: onAction) {
                    Text(verbatim: actionTitle).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.white)).foregroundStyle(.black)
                }.buttonStyle(.plain)
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }.buttonStyle(.plain)
        }
    }
}

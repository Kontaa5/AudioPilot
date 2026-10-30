import AppKit
import SwiftUI

/// Kleines schwarzes Popup, das aus der Notch „herauswächst“ (wie bei AirPods am iPhone).
@MainActor
final class NotchPopup {
    static let shared = NotchPopup()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(symbol: String, title: String, subtitle: String, action: (title: String, run: () -> Void)? = nil, duration: Double = 6) {
        hide(animated: false)
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let notch = max(screen.safeAreaInsets.top, 32)
        let size = NSSize(width: 380, height: notch + 64)
        let small = NSSize(width: 200, height: notch)
        func frame(_ s: NSSize) -> NSRect {
            NSRect(x: screen.frame.midX - s.width / 2, y: screen.frame.maxY - s.height, width: s.width, height: s.height)
        }

        let view = PopupView(symbol: symbol, title: title, subtitle: subtitle, topInset: notch,
                             actionTitle: action?.title,
                             onAction: { [weak self] in action?.run(); self?.hide() },
                             onClose: { [weak self] in self?.hide() })
        let p = NSPanel(contentRect: frame(small), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: view)
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.2, 0.4, 1)
            p.animator().setFrame(frame(size), display: true)
            p.animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide(animated: Bool = true) {
        hideWork?.cancel()
        guard let p = panel else { return }
        panel = nil
        guard animated else { p.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }
}

private struct PopupView: View {
    let symbol: String, title: String, subtitle: String, topInset: CGFloat
    let actionTitle: String?
    let onAction: () -> Void, onClose: () -> Void

    var body: some View {
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
        .padding(.horizontal, 20)
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24).fill(.black))
    }
}

import AppKit

final class ProgressBarView: NSView {
    private let fillLayer = CALayer()
    private var progress: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        fillLayer.backgroundColor = NSColor.controlAccentColor.cgColor
        fillLayer.anchorPoint = .zero
        layer?.addSublayer(fillLayer)
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateFillFrame(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fillLayer.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }

    func setProgress(_ value: Double, animated: Bool) {
        let clamped = max(0, min(1, value))
        let wasZero = progress == 0
        progress = clamped

        if clamped >= 1 {
            updateFillFrame(animated: animated)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                animator().alphaValue = 0
            } completionHandler: { [weak self] in
                guard let self, self.progress >= 1 else { return }
                self.progress = 0
                self.updateFillFrame(animated: false)
            }
            return
        }

        if wasZero {
            alphaValue = 1
        }
        updateFillFrame(animated: animated)
    }

    private func updateFillFrame(animated: Bool) {
        let width = bounds.width * CGFloat(progress)
        let newFrame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(0.15)
        }
        fillLayer.frame = newFrame
        CATransaction.commit()
    }
}

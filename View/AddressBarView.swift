import AppKit

protocol AddressBarViewDelegate: AnyObject {
    func addressBar(_ addressBar: AddressBarView, didSubmitURL url: URL)
}

final class AddressBarView: NSView {
    weak var delegate: AddressBarViewDelegate?

    private let textField = NSTextField()
    private let progressBar = ProgressBarView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        textField.placeholderString = "Enter URL"
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        progressBar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)
        addSubview(progressBar)
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    func setProgress(_ value: Double, animated: Bool) {
        progressBar.setProgress(value, animated: animated)
    }

    var text: String {
        get { textField.stringValue }
        set { textField.stringValue = newValue }
    }

    @discardableResult
    func focus() -> Bool {
        window?.makeFirstResponder(textField) ?? false
    }

    fileprivate func submit() {
        let raw = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let normalized = Self.normalize(raw)
        guard let url = URL(string: normalized) else { return }
        delegate?.addressBar(self, didSubmitURL: url)
    }

    static func normalize(_ input: String) -> String {
        if input.contains("://") { return input }
        return "https://\(input)"
    }
}

extension AddressBarView: NSTextFieldDelegate {
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        return false
    }
}

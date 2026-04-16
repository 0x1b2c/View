import AppKit
import ViewCore

protocol AddressBarViewDelegate: AnyObject {
    func addressBar(_ addressBar: AddressBarView, didSubmitURL url: URL)
}

final class AddressBarView: NSView {
    weak var delegate: AddressBarViewDelegate?

    var suggestionProvider: ((String) -> [HistoryEntry])?

    private let textField = NSTextField()
    private let progressBar = ProgressBarView()
    private let suggestions = SuggestionsPopover()

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

        setUpSuggestions()
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

    private func setUpSuggestions() {
        suggestions.onSelect = { [weak self] entry in
            guard let self, let url = URL(string: entry.url) else { return }
            self.textField.stringValue = entry.url
            self.delegate?.addressBar(self, didSubmitURL: url)
        }
    }

    private func updateSuggestions() {
        guard let provider = suggestionProvider else { return }
        let query = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            suggestions.hide()
            return
        }
        let items = provider(query)
        suggestions.setItems(items)
        if items.isEmpty {
            suggestions.hide()
        } else {
            suggestions.show(relativeTo: textField)
        }
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
        if let entry = suggestions.highlightedEntry, suggestions.isShown,
            let url = URL(string: entry.url)
        {
            textField.stringValue = entry.url
            suggestions.hide()
            delegate?.addressBar(self, didSubmitURL: url)
            return
        }
        let raw = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let url = Self.resolve(raw) else { return }
        suggestions.hide()
        delegate?.addressBar(self, didSubmitURL: url)
    }

    static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.contains("://") {
            return URL(string: trimmed)
        }

        if trimmed == "localhost" || trimmed.hasPrefix("localhost:")
            || trimmed.hasPrefix("localhost/")
        {
            return URL(string: "http://\(trimmed)")
        }

        if trimmed.rangeOfCharacter(from: .whitespaces) == nil,
            looksLikeHost(trimmed)
        {
            return URL(string: "https://\(trimmed)")
        }

        return searchURL(for: trimmed)
    }

    private static func looksLikeHost(_ s: String) -> Bool {
        guard let dotIndex = s.firstIndex(of: ".") else { return false }
        let afterDot = s[s.index(after: dotIndex)...]
        if afterDot.isEmpty { return false }
        if afterDot.contains(".") { return true }
        return afterDot.count >= 2 && afterDot.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func searchURL(for query: String) -> URL? {
        guard
            let encoded = query.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }
}

extension AddressBarView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        updateSuggestions()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            submit()
            return true
        case #selector(NSResponder.moveDown(_:)):
            if suggestions.isShown {
                suggestions.moveHighlight(by: 1)
                return true
            }
            return false
        case #selector(NSResponder.moveUp(_:)):
            if suggestions.isShown {
                suggestions.moveHighlight(by: -1)
                return true
            }
            return false
        case #selector(NSResponder.cancelOperation(_:)):
            if suggestions.isShown {
                suggestions.hide()
                return true
            }
            return false
        default:
            return false
        }
    }
}

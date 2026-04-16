import AppKit
import ViewCore

final class SuggestionsListView: NSView {
    var onSelect: ((HistoryEntry) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var items: [HistoryEntry] = []
    private var highlightedRow: Int = -1

    private static let rowHeight: CGFloat = 36
    private static let maxRows = 10

    var highlightedEntry: HistoryEntry? {
        guard items.indices.contains(highlightedRow) else { return nil }
        return items[highlightedRow]
    }

    var itemCount: Int { items.count }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("s"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
    }

    func setItems(_ newItems: [HistoryEntry]) {
        items = newItems
        tableView.reloadData()
        if !items.isEmpty {
            highlightedRow = 0
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            highlightedRow = -1
        }
        isHidden = items.isEmpty
    }

    func clear() {
        items = []
        highlightedRow = -1
        tableView.reloadData()
        isHidden = true
    }

    func moveHighlight(by delta: Int) {
        guard !items.isEmpty else { return }
        let next = max(0, min(items.count - 1, highlightedRow + delta))
        highlightedRow = next
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    var intrinsicHeight: CGFloat {
        let visible = min(items.count, Self.maxRows)
        return CGFloat(visible) * Self.rowHeight + 8
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: intrinsicHeight)
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        onSelect?(items[row])
    }
}

extension SuggestionsListView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowHeight
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SuggestionCell")
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
            ?? Self.makeCell(identifier: identifier)
        let entry = items[row]
        cell.textField?.stringValue = entry.title?.isEmpty == false ? entry.title! : entry.url
        if let urlLabel = cell.subviews.compactMap({ $0 as? NSTextField }).dropFirst().first {
            urlLabel.stringValue = entry.url
        }
        return cell
    }

    private static func makeCell(
        identifier: NSUserInterfaceItemIdentifier
    ) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let titleField = NSTextField(labelWithString: "")
        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: 13, weight: .regular)
        titleField.translatesAutoresizingMaskIntoConstraints = false

        let urlField = NSTextField(labelWithString: "")
        urlField.lineBreakMode = .byTruncatingTail
        urlField.font = .systemFont(ofSize: 11)
        urlField.textColor = .secondaryLabelColor
        urlField.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(titleField)
        cell.addSubview(urlField)
        cell.textField = titleField

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            titleField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
            urlField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            urlField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            urlField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 0),
            urlField.bottomAnchor.constraint(
                lessThanOrEqualTo: cell.bottomAnchor, constant: -4),
        ])

        return cell
    }
}

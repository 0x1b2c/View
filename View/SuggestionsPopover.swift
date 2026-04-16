import AppKit
import ViewCore

final class SuggestionsPopover: NSObject {
    private let popover = NSPopover()
    private let controller: SuggestionsViewController
    private weak var anchorView: NSView?

    var onSelect: ((HistoryEntry) -> Void)?

    var isShown: Bool { popover.isShown }
    var highlightedEntry: HistoryEntry? { controller.highlightedEntry }
    var itemCount: Int { controller.items.count }

    override init() {
        self.controller = SuggestionsViewController()
        super.init()
        popover.behavior = .transient
        popover.contentViewController = controller
        controller.onClick = { [weak self] entry in
            self?.onSelect?(entry)
            self?.hide()
        }
    }

    func setItems(_ items: [HistoryEntry]) {
        controller.items = items
        controller.reload()
    }

    func show(relativeTo view: NSView) {
        guard !controller.items.isEmpty else {
            hide()
            return
        }
        anchorView = view
        if !popover.isShown {
            popover.show(
                relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    func hide() {
        if popover.isShown { popover.close() }
        controller.clearHighlight()
    }

    func moveHighlight(by delta: Int) {
        controller.moveHighlight(by: delta)
    }
}

final class SuggestionsViewController: NSViewController {
    var items: [HistoryEntry] = []
    var onClick: ((HistoryEntry) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var highlightedRow: Int = -1

    var highlightedEntry: HistoryEntry? {
        guard items.indices.contains(highlightedRow) else { return nil }
        return items[highlightedRow]
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 220))
        container.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("s"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .medium
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        self.view = container
    }

    func reload() {
        tableView.reloadData()
        if !items.isEmpty {
            highlightedRow = 0
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            highlightedRow = -1
        }
        adjustSize()
    }

    func moveHighlight(by delta: Int) {
        guard !items.isEmpty else { return }
        let next = max(0, min(items.count - 1, highlightedRow + delta))
        highlightedRow = next
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func clearHighlight() {
        highlightedRow = -1
        tableView.deselectAll(nil)
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard items.indices.contains(row) else { return }
        onClick?(items[row])
    }

    private func adjustSize() {
        let rowHeight: CGFloat = 36
        let maxRows = 10
        let visible = min(items.count, maxRows)
        let height = max(CGFloat(visible) * rowHeight, 36)
        view.setFrameSize(NSSize(width: 520, height: height))
        preferredContentSize = view.frame.size
    }
}

extension SuggestionsViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
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

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        36
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

    func tableView(
        _ tableView: NSTableView,
        selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
    ) -> IndexSet {
        proposedSelectionIndexes
    }
}

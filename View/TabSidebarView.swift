import AppKit

struct TabSidebarItem {
    var title: String
    var favicon: NSImage?
}

protocol TabSidebarViewDelegate: AnyObject {
    func sidebarDidSelectTab(at index: Int)
    func sidebarDidRequestCloseTab(at index: Int)
    func sidebarDidReorderTab(from source: Int, to destination: Int)
}

final class TabSidebarView: NSView {
    weak var delegate: TabSidebarViewDelegate?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var items: [TabSidebarItem] = []

    private let pasteboardType = NSPasteboard.PasteboardType("io.protoss.view.tabIndex")
    private var isProgrammaticallyUpdating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.title = ""
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .medium
        tableView.style = .sourceList
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.action = #selector(tableViewClicked)
        tableView.target = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([pasteboardType])

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func reloadItems(_ newItems: [TabSidebarItem], selectedIndex: Int) {
        isProgrammaticallyUpdating = true
        defer { isProgrammaticallyUpdating = false }
        items = newItems
        tableView.reloadData()
        if selectedIndex >= 0 && selectedIndex < newItems.count {
            tableView.selectRowIndexes(
                IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }
    }

    @objc private func tableViewClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        delegate?.sidebarDidSelectTab(at: row)
    }
}

extension TabSidebarView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("TabCell")
        let cell =
            tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView
            ?? Self.makeCell(identifier: identifier)
        cell.textField?.stringValue = items[row].title
        cell.imageView?.image = items[row].favicon ?? Self.placeholderImage
        return cell
    }

    private static let placeholderImage: NSImage? = {
        NSImage(
            systemSymbolName: "globe",
            accessibilityDescription: nil
        )
    }()

    private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.imageView = imageView

        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isProgrammaticallyUpdating else { return }
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        delegate?.sidebarDidSelectTab(at: row)
    }

    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString("\(row)", forType: pasteboardType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        dropOperation == .above ? .move : []
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard
            let item = info.draggingPasteboard.pasteboardItems?.first,
            let sourceString = item.string(forType: pasteboardType),
            let source = Int(sourceString)
        else { return false }
        let destination = source < row ? row - 1 : row
        delegate?.sidebarDidReorderTab(from: source, to: destination)
        return true
    }
}

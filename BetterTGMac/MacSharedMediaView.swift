// MacSharedMediaView.swift

import AppKit
import SwiftUI
import TDLibKit

// MARK: - MacSharedMediaView

struct MacSharedMediaView: View {
    // MARK: Lifecycle

    init(
        model: MacSessionModel,
        chat: ChatListItemState,
        onOpenMessage: @escaping (Int64) -> Void,
    ) {
        self.model = model
        self.chat = chat
        self.onOpenMessage = onOpenMessage
        self._store = State(initialValue: TelegramSharedMediaStore(chatId: chat.chatId, service: model.service))
    }

    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Shared Media")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top])

            Picker(selection: $selection) {
                ForEach(TelegramSharedMediaCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()
            content
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 500, idealHeight: 680)
        .navigationTitle("Shared Media")
        .task(id: selection) { await store.load(selection) }
    }

    // MARK: Private

    @Bindable private var model: MacSessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection = TelegramSharedMediaCategory.media
    @State private var store: TelegramSharedMediaStore

    private let chat: ChatListItemState
    private let onOpenMessage: (Int64) -> Void

    private var page: TelegramSharedMediaPage { store.page(for: selection) }

    @ViewBuilder private var content: some View {
        if !page.hasLoaded, page.isLoading {
            ProgressView("Loading \(selection.title.lowercased())…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = page.error, page.messages.isEmpty {
            ContentUnavailableView(
                "Couldn't Load \(selection.title)",
                systemImage: "exclamationmark.triangle",
                description: Text(error),
            )
            Button("Try Again") { Task { await store.load(selection, reset: true) } }
        } else if page.messages.isEmpty {
            ContentUnavailableView(
                "No \(selection.title)",
                systemImage: selection.systemImage,
                description: Text("No \(selection.title.lowercased()) were found in \(chat.title)."),
            )
        } else if selection == .media {
            mediaGrid
        } else {
            MacSharedMediaTable(
                messages: page.messages,
                category: selection,
                onActivate: activate,
                onLoadMore: { Task { await store.load(selection) } },
            )
        }
    }

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 3)], spacing: 3) {
                ForEach(page.messages, id: \.id) { message in
                    Button { onOpenMessage(message.id) } label: {
                        MacSharedMediaThumbnail(model: model, message: message)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(telegramSharedMediaTitle(message)), \(telegramSharedMediaSubtitle(message))",
                    )
                    .onAppear { loadNextIfNeeded(message) }
                }
                if page.isLoading {
                    ProgressView().padding()
                }
            }
            .padding(3)
        }
    }

    private func activate(_ message: Message) {
        if selection == .links,
           let formattedText = telegramMessageFormattedText(message),
           let link = TelegramTextFormatting.links(in: formattedText).first
        {
            NSWorkspace.shared.open(link.url)
        } else {
            onOpenMessage(message.id)
        }
    }

    private func loadNextIfNeeded(_ message: Message) {
        guard page.messages.suffix(8).contains(where: { $0.id == message.id }) else { return }
        Task { await store.load(selection) }
    }
}

// MARK: - MacSharedMediaThumbnail

private struct MacSharedMediaThumbnail: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let message: Message

    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.15))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
            if case .messageVideo = message.content {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
        .task(id: telegramSharedMediaThumbnailFileId(message)) {
            guard let fileId = telegramSharedMediaThumbnailFileId(message),
                  let path = await model.localPhotoPath(fileId: fileId)
            else { return }
            image = NSImage(contentsOfFile: path)
        }
    }

    // MARK: Private

    @State private var image: NSImage?
}

// MARK: - MacSharedMediaTable

private struct MacSharedMediaTable: NSViewRepresentable {
    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        // MARK: Lifecycle

        init(parent: MacSharedMediaTable) { self.parent = parent }

        // MARK: Internal

        var parent: MacSharedMediaTable
        weak var table: NSTableView?
        var selectedMessageId: Int64?

        func numberOfRows(in _: NSTableView) -> Int { parent.messages.count }

        func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            guard parent.messages.indices.contains(row) else { return nil }
            let message = parent.messages[row]
            let identifier = NSUserInterfaceItemIdentifier("SharedMediaCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? SharedMediaCell)
                ?? SharedMediaCell()
            cell.identifier = identifier
            cell.configure(
                title: telegramSharedMediaTitle(message),
                subtitle: telegramSharedMediaSubtitle(message),
                icon: parent.category.systemImage,
            )
            if row >= parent.messages.count - 8 {
                DispatchQueue.main.async { [parent] in parent.onLoadMore() }
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Foundation.Notification) {
            guard let table = notification.object as? NSTableView,
                  parent.messages.indices.contains(table.selectedRow)
            else { return }
            selectedMessageId = parent.messages[table.selectedRow].id
        }

        @objc func activateSelection() {
            guard let table, parent.messages.indices.contains(table.selectedRow) else { return }
            parent.onActivate(parent.messages[table.selectedRow])
        }
    }

    let messages: [Message]
    let category: TelegramSharedMediaCategory
    let onActivate: (Message) -> Void
    let onLoadMore: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = ActivatingTableView()
        let column = NSTableColumn(identifier: .init("SharedMedia"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.usesAutomaticRowHeights = true
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.activateSelection)
        table.onActivate = context.coordinator.activateSelection
        table.setAccessibilityLabel("\(category.title) in \(messages.count) results")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_: NSScrollView, context: Context) {
        let categoryChanged = context.coordinator.parent.category != category
        let oldSelection = context.coordinator.selectedMessageId
        context.coordinator.parent = self
        context.coordinator.table?.setAccessibilityLabel("\(category.title), \(messages.count) results")
        context.coordinator.table?.reloadData()
        if categoryChanged {
            context.coordinator.table?.deselectAll(nil)
        } else if let oldSelection, let row = messages.firstIndex(where: { $0.id == oldSelection }) {
            context.coordinator.table?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }
}

// MARK: - ActivatingTableView

private final class ActivatingTableView: NSTableView {
    override var acceptsFirstResponder: Bool { true }

    var onActivate: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function]).isEmpty,
           event.keyCode == 36 || event.keyCode == 49
        {
            onActivate?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - SharedMediaCell

private final class SharedMediaCell: NSTableCellView {
    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleField.font = .preferredFont(forTextStyle: .body)
        titleField.lineBreakMode = .byTruncatingTail
        subtitleField.font = .preferredFont(forTextStyle: .caption1)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [titleField, subtitleField])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        let stack = NSStackView(views: [iconView, labels])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            iconView.widthAnchor.constraint(equalToConstant: 24),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        iconView.setAccessibilityHidden(true)
        titleField.setAccessibilityHidden(true)
        subtitleField.setAccessibilityHidden(true)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) { nil }

    // MARK: Internal

    func configure(title: String, subtitle: String, icon: String) {
        titleField.stringValue = title
        subtitleField.stringValue = subtitle
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        setAccessibilityLabel([title, subtitle].filter { !$0.isEmpty }.joined(separator: ", "))
    }

    // MARK: Private

    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
}

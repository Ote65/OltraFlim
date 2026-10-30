import SwiftUI
import AppKit

extension PhotoColorLabel {
    var color: Color {
        switch self {
        case .red: return Color(hex: 0xD76A5B)
        case .yellow: return Color(hex: 0xD9B45D)
        case .green: return Color(hex: 0x7CAE6B)
        case .blue: return Color(hex: 0x6E9BC6)
        case .purple: return Color(hex: 0x9A82BE)
        }
    }
}

/// The library is the front door of OltraFlim. It behaves like a small Finder:
/// folders and photographs share the root, opening a folder pushes a breadcrumb
/// level, and View / Group / filter controls shape the wall without changing
/// files on disk.
struct HomeLibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingPhotoRemoval: Photo?
    @State private var pendingFolderRemoval: LibraryFolder?

    var body: some View {
        ZStack {
            DS.surface0
            if isRootEmpty {
                LibraryEmptyState()
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
            } else {
                library
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            SettingsFloatingButton {
                SettingsPanelController.shared.show(model: model)
            }
            .padding(24)
        }
        .confirmationDialog(
            T("从照片库移除照片？", "Remove photograph from library?"),
            isPresented: Binding(
                get: { pendingPhotoRemoval != nil },
                set: { if !$0 { pendingPhotoRemoval = nil } }
            ),
            presenting: pendingPhotoRemoval
        ) { photo in
            Button(T("移除", "Remove"), role: .destructive) {
                model.removePhoto(photo.id)
                model.showToast(
                    T("已从照片库移除", "Removed from library"),
                    detail: photo.name,
                    symbol: "rectangle.stack.badge.minus"
                )
                pendingPhotoRemoval = nil
            }
            Button(T("取消", "Cancel"), role: .cancel) { pendingPhotoRemoval = nil }
        } message: { photo in
            Text(T("只移除照片库中的记录，不会删除 \(photo.name) 原文件。",
                   "This removes the library entry only; \(photo.name) is not deleted."))
        }
        .confirmationDialog(
            T("从照片库移除文件夹？", "Remove folder from library?"),
            isPresented: Binding(
                get: { pendingFolderRemoval != nil },
                set: { if !$0 { pendingFolderRemoval = nil } }
            ),
            presenting: pendingFolderRemoval
        ) { folder in
            Button(T("移除文件夹", "Remove folder"), role: .destructive) {
                model.removeFolder(folder)
                pendingFolderRemoval = nil
            }
            Button(T("取消", "Cancel"), role: .cancel) { pendingFolderRemoval = nil }
        } message: { folder in
            Text(T("只会移除照片库里的文件夹索引，不会删除磁盘上的 \(folder.name)。",
                   "This removes the library index only; \(folder.name) stays on disk."))
        }
    }

    private var isRootEmpty: Bool {
        model.folderTrail.isEmpty && model.visibleFolders.isEmpty && model.libraryPhotos.isEmpty
    }

    private var library: some View {
        VStack(spacing: 0) {
            header
            toolbar
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if model.visibleFolders.isEmpty && model.libraryPhotos.isEmpty {
                        folderEmpty
                    } else {
                        if !model.visibleFolders.isEmpty {
                            sectionHeader(
                                T("文件夹", "FOLDERS"),
                                count: model.visibleFolders.count,
                                symbol: "folder"
                            )
                            folderSection
                        }

                        if model.libraryPhotos.isEmpty {
                            if !model.visibleFolders.isEmpty {
                                folderOnlyHint
                            }
                        } else if model.filteredLibraryPhotos.isEmpty {
                            noResults
                        } else {
                            if model.libraryGrouping == .none {
                                sectionHeader(
                                    T("照片", "PHOTOGRAPHS"),
                                    count: model.filteredLibraryPhotos.count,
                                    symbol: "photo"
                                )
                            }
                            photoSection
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 46)
            }
            .scrollIndicators(.never)
        }
        .animation(DS.snappy, value: model.libraryDisplay)
        .animation(DS.snappy, value: model.libraryGrouping)
        .animation(DS.easeQuick, value: model.libraryFilter)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(DS.snappy) { model.goUpFolder() }
            } label: {
                LibraryBackButton()
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .disabled(model.folderTrail.isEmpty)
            .opacity(model.folderTrail.isEmpty ? 0.32 : 1)
            .help(T("返回上一级", "Back one level"))
            VStack(alignment: .leading, spacing: 4) {
                if model.folderTrail.isEmpty {
                    Text(T("照片库", "PHOTO LIBRARY"))
                        .font(DS.font(21, .semibold))
                        .tracking(0.2)
                        .foregroundStyle(DS.textPrimary)
                } else {
                    breadcrumb
                    Text(model.currentFolderName ?? model.libraryTitle)
                        .font(DS.font(21, .semibold))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                }
                Text(T("点击照片进入显影；支持文件夹、收藏与颜色标签。",
                       "Click a photograph to develop. Folders, favorites and colour labels are supported."))
                    .font(DS.label(11))
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 20)
            HStack(spacing: 8) {
                ImportPhotoButton(title: T("导入照片", "Import photos"))
                FolderImportButton()
            }
        }
        .padding(.horizontal, 26)
        .frame(height: 86)
        .background(DS.surface1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button {
                model.goToLibraryRoot()
            } label: {
                Text(T("照片库", "Library"))
                    .font(DS.font(9.5, .medium))
                    .foregroundStyle(DS.textTertiary)
            }
            .buttonStyle(.plain)
            ForEach(Array(model.folderTrail.enumerated()), id: \.offset) { index, url in
                Image(systemName: "chevron.right")
                    .font(DS.font(7, .semibold))
                    .foregroundStyle(DS.textQuaternary)
                Button {
                    model.navigateToTrail(index)
                } label: {
                    Text(url.lastPathComponent)
                        .font(DS.font(9.5, index == model.folderTrail.count - 1
                                      ? .medium : .regular))
                        .foregroundStyle(index == model.folderTrail.count - 1
                                         ? DS.textSecondary : DS.textTertiary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
        .lineLimit(1)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(LibraryFilter.allCases) { filter in
                        LibraryFilterChip(filter: filter)
                    }
                }
                .padding(.vertical, 1)
            }
            Spacer(minLength: 8)
            SearchField(
                text: Binding(
                    get: { model.librarySearch },
                    set: { model.librarySearch = $0 }
                ),
                placeholder: T("搜索照片、胶片、标签", "Search photos, film, labels")
            )
            .frame(width: 200)
            Rectangle().fill(DS.hairlineStrong).frame(width: 1, height: 18)
            viewMenu
            groupMenu
        }
        .padding(.horizontal, 26)
        .frame(height: 48)
        .background(DS.surface1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
    }

    private var viewMenu: some View {
        Menu {
            ForEach(LibraryDisplayMode.allCases) { mode in
                Button {
                    model.libraryDisplay = mode
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.symbol)
                        Text(mode.title)
                        if model.libraryDisplay == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            LibraryMenuLabel(
                title: T("显示", "View"),
                value: model.libraryDisplay.title,
                symbol: model.libraryDisplay.symbol
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(T("切换网格或列表显示", "Switch between grid and list"))
    }

    private var groupMenu: some View {
        Menu {
            ForEach(LibraryGrouping.allCases) { grouping in
                Button {
                    model.libraryGrouping = grouping
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: grouping.symbol)
                        Text(grouping.title)
                        if model.libraryGrouping == grouping {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            LibraryMenuLabel(
                title: T("群组", "Group"),
                value: model.libraryGrouping.title,
                symbol: model.libraryGrouping.symbol
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(T("按胶片、收藏或颜色标签群组", "Group by film, favorites or colour label"))
    }

    // MARK: Sections

    private func sectionHeader(_ title: String, count: Int, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(DS.font(9, .medium))
                .foregroundStyle(DS.textQuaternary)
            Text(title)
                .font(DS.font(8.5, .medium))
                .tracking(1.2)
                .foregroundStyle(DS.textTertiary)
            Text("\(count)")
                .font(DS.mono(8.5))
                .foregroundStyle(DS.textQuaternary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var folderSection: some View {
        Group {
            if model.libraryDisplay == .grid {
                LazyVGrid(columns: folderColumns, spacing: 18) {
                    ForEach(model.visibleFolders) { folder in
                        LibraryFolderCard(
                            folder: folder,
                            onRemove: { pendingFolderRemoval = folder },
                            canRemove: model.currentFolderURL == nil
                        )
                    }
                }
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(model.visibleFolders) { folder in
                        LibraryFolderRow(
                            folder: folder,
                            onRemove: { pendingFolderRemoval = folder },
                            canRemove: model.currentFolderURL == nil
                        )
                        Rectangle().fill(DS.hairline).frame(height: 1)
                    }
                }
                .background(DS.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.hairline, lineWidth: 1)
                )
            }
        }
    }

    private var photoSection: some View {
        Group {
            if model.libraryDisplay == .grid {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(model.libraryGroups) { group in
                        if let title = group.title {
                            LibraryGroupHeader(title: title, count: group.photos.count)
                        }
                        LazyVGrid(columns: photoColumns, spacing: 22) {
                            ForEach(group.photos) { photo in
                                LibraryPhotoCard(photo: photo) {
                                    pendingPhotoRemoval = photo
                                }
                            }
                        }
                    }
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.libraryGroups) { group in
                        if let title = group.title {
                            LibraryGroupHeader(title: title, count: group.photos.count)
                                .padding(.top, 4)
                                .padding(.bottom, 8)
                        }
                        ForEach(group.photos) { photo in
                            LibraryPhotoRow(photo: photo) {
                                pendingPhotoRemoval = photo
                            }
                            Rectangle().fill(DS.hairline).frame(height: 1)
                        }
                    }
                }
                .background(DS.surface1)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.hairline, lineWidth: 1)
                )
            }
        }
    }

    private var folderOnlyHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .font(DS.font(10, .light))
                .foregroundStyle(DS.textQuaternary)
            Text(T("当前层没有直接导入的照片；打开文件夹浏览其中的照片。",
                   "No loose photographs at this level. Open a folder to browse its photographs."))
                .font(DS.label(10.5))
                .foregroundStyle(DS.textTertiary)
        }
        .padding(.vertical, 14)
    }

    private var folderEmpty: some View {
        VStack(spacing: 11) {
            Image(systemName: "folder")
                .font(DS.font(26, .light))
                .foregroundStyle(DS.textQuaternary)
            Text(T("这个文件夹里没有照片", "This folder has no photographs"))
                .font(DS.font(13, .medium))
                .foregroundStyle(DS.textSecondary)
            Text(T("放入受支持的图片或子文件夹后，重新打开文件夹即可刷新。",
                   "Add supported images or subfolders, then reopen the folder to refresh."))
                .font(DS.label(10))
                .foregroundStyle(DS.textTertiary)
            HStack(spacing: 10) {
                Button(T("上一级", "Back one level")) { model.goUpFolder() }
                    .buttonStyle(.plain)
                    .font(DS.label(10))
                    .foregroundStyle(DS.textSecondary)
                Button(T("回到照片库", "Library root")) { model.goToLibraryRoot() }
                    .buttonStyle(.plain)
                    .font(DS.label(10))
                    .foregroundStyle(DS.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(DS.font(22, .light))
                .foregroundStyle(DS.textQuaternary)
            Text(T("没有符合筛选的照片", "No photographs match the filter"))
                .font(DS.font(12, .medium))
                .foregroundStyle(DS.textSecondary)
            Button(T("清除筛选与搜索", "Clear filters and search")) {
                withAnimation(DS.easeQuick) {
                    model.libraryFilter = .all
                    model.librarySearch = ""
                }
            }
            .buttonStyle(.plain)
            .font(DS.label(10))
            .foregroundStyle(DS.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    // MARK: Layout constants

    private var photoColumns: [GridItem] { libraryColumns }

    private var folderColumns: [GridItem] { libraryColumns }

    /// One shared grid so folder rows and photo rows line up vertically.
    private var libraryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 18)]
    }
}

// MARK: - Back button

struct LibraryBackButton: View {
    @State private var hovering = false

    var body: some View {
        Image(systemName: "chevron.left")
            .font(DS.font(11, .semibold))
            .foregroundStyle(hovering ? DS.accent : DS.textSecondary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                    .fill(hovering ? DS.surface3 : DS.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                    .stroke(hovering ? DS.accent.opacity(0.35) : DS.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous))
            .animation(DS.easeQuick, value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Filter chips

struct LibraryFilterChip: View {
    @Environment(AppModel.self) private var model
    let filter: LibraryFilter

    var body: some View {
        Button {
            withAnimation(DS.easeQuick) { model.libraryFilter = filter }
        } label: {
            HStack(spacing: 5) {
                if let label = filter.colorLabel {
                    Circle().fill(label.color).frame(width: 6, height: 6)
                } else if let symbol = filter.symbol {
                    Image(systemName: symbol)
                        .font(DS.font(8.5, .medium))
                        .foregroundStyle(selected ? DS.accent : DS.textTertiary)
                }
                Text(filter.title)
                    .font(DS.font(9.5, .medium))
                    .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
                let count = model.libraryFilterCount(filter)
                if count > 0 {
                    Text("\(count)")
                        .font(DS.mono(8))
                        .foregroundStyle(selected ? DS.accent : DS.textQuaternary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(
                Capsule().fill(selected ? DS.surface3 : DS.surface0)
            )
            .overlay(
                Capsule().stroke(
                    selected ? (filter.colorLabel?.color.opacity(0.7) ?? DS.accent.opacity(0.55))
                             : DS.hairline,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .animation(DS.easeQuick, value: selected)
    }

    private var selected: Bool { model.libraryFilter == filter }
}

struct LibraryMenuLabel: View {
    let title: String
    let value: String
    let symbol: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(DS.font(9, .medium))
                .foregroundStyle(hovering ? DS.accent : DS.textTertiary)
            Text(title)
                .font(DS.font(9.5, .medium))
                .foregroundStyle(DS.textSecondary)
            Text(value)
                .font(DS.font(9))
                .foregroundStyle(DS.textQuaternary)
            Image(systemName: "chevron.down")
                .font(DS.font(6.5, .semibold))
                .foregroundStyle(DS.textQuaternary)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? DS.surface2 : DS.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DS.hairline, lineWidth: 1)
        )
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
        }
    }
}

// MARK: - Folder cards

struct LibraryFolderCard: View {
    @Environment(AppModel.self) private var model
    let folder: LibraryFolder
    let onRemove: () -> Void
    var canRemove = true
    @State private var hovering = false

    var body: some View {
        Button {
            model.enterFolder(folder)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                folderThumb
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(folder.name)
                            .font(DS.font(12, .medium))
                            .foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Text(folder.countText)
                            .font(DS.mono(8.5))
                            .foregroundStyle(DS.textTertiary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(DS.font(8, .medium))
                        .foregroundStyle(hovering ? DS.accent : DS.textQuaternary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering ? DS.surface2 : DS.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(hovering ? DS.accent.opacity(0.34) : DS.hairlineStrong, lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.34 : 0.14),
                    radius: hovering ? 18 : 9, y: hovering ? 10 : 5)
            .scaleEffect(hovering ? 1.008 : 1)
        }
        .buttonStyle(PressableStyle(scale: 0.992))
        .onAppear { model.requestFolderCover(folder) }
        .contextMenu {
            Button(T("打开文件夹", "Open folder")) { model.enterFolder(folder) }
            Button(T("刷新内容", "Refresh")) { model.refreshFolder(folder) }
            if canRemove {
                Divider()
                Button(T("从照片库移除文件夹", "Remove Folder from Library"), role: .destructive) {
                    onRemove()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering && canRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "folder.badge.minus")
                        .font(DS.font(10, .medium))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(DS.surface3.opacity(0.9)))
                        .overlay(Circle().stroke(DS.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .padding(10)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .help(T("从照片库移除文件夹", "Remove folder from library"))
            }
        }
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
            if value { model.requestFolderCover(folder) }
        }
        .animation(DS.snappy, value: hovering)
    }

    private var folderThumb: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                ZStack {
                    DS.surface2
                    if let cover = folder.cover {
                        Image(decorative: cover, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(0.58)
                        LinearGradient(
                            colors: [.black.opacity(0.18), .black.opacity(0.52)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    VStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .font(DS.font(30, .light))
                            .foregroundStyle(DS.accent.opacity(0.9))
                        if folder.cover == nil {
                            Text(T("文件夹", "Folder"))
                                .font(DS.font(8, .medium))
                                .tracking(0.8)
                                .foregroundStyle(DS.textTertiary)
                        }
                    }
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            }
    }
}

struct LibraryFolderRow: View {
    @Environment(AppModel.self) private var model
    let folder: LibraryFolder
    let onRemove: () -> Void
    var canRemove = true
    @State private var hovering = false

    var body: some View {
        Button {
            model.enterFolder(folder)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(DS.surface2)
                    if let cover = folder.cover {
                        Image(decorative: cover, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .opacity(0.55)
                    }
                    Image(systemName: "folder.fill")
                        .font(DS.font(14, .light))
                        .foregroundStyle(DS.accent.opacity(0.9))
                }
                .frame(width: 48, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(DS.font(11.5, .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(folder.countText)
                        .font(DS.mono(8.5))
                        .foregroundStyle(DS.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DS.font(8.5, .medium))
                    .foregroundStyle(DS.textQuaternary)
                    .padding(.trailing, 2)
                    .opacity(hovering ? 0 : 1)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .contentShape(Rectangle())
            .background(hovering ? DS.surface2 : .clear)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if hovering && canRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "folder.badge.minus")
                        .font(DS.font(10, .medium))
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .help(T("从照片库移除文件夹", "Remove folder from library"))
            }
        }
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
            if value { model.requestFolderCover(folder) }
        }
        .onAppear { model.requestFolderCover(folder) }
        .contextMenu {
            Button(T("打开文件夹", "Open folder")) { model.enterFolder(folder) }
            Button(T("刷新内容", "Refresh")) { model.refreshFolder(folder) }
            if canRemove {
                Divider()
                Button(T("从照片库移除文件夹", "Remove Folder from Library"), role: .destructive) {
                    onRemove()
                }
            }
        }
    }
}

// MARK: - Photo cards

struct LibraryPhotoCard: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            model.openPhoto(photo.id)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                caption
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering ? DS.surface2 : DS.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(hovering ? DS.accent.opacity(0.34) : DS.hairlineStrong, lineWidth: 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.38 : 0.16),
                    radius: hovering ? 20 : 10, y: hovering ? 12 : 6)
            .scaleEffect(hovering ? 1.008 : 1)
        }
        .buttonStyle(PressableStyle(scale: 0.992))
        .onAppear { model.requestThumbnail(photo.id) }
        .onChange(of: photo.thumbnail == nil) { _, missing in
            if missing { model.requestThumbnail(photo.id) }
        }
        .overlay(alignment: .topTrailing) {
            cardControls
                .allowsHitTesting(hovering)
        }
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
            if value { model.requestThumbnail(photo.id) }
        }
        .contextMenu {
            Button(T("进入显影", "Develop")) { model.openPhoto(photo.id) }
            Button(photo.isFavorite
                   ? T("取消收藏", "Remove from favorites")
                   : T("收藏", "Add to favorites")) {
                model.toggleFavorite(photo.id)
            }
            Button(T("在访达中显示", "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([photo.url])
            }
            if photo.folder == nil {
                Divider()
                Button(T("从照片库移除", "Remove from Library"), role: .destructive) {
                    onRemove()
                }
            }
        }
        .animation(DS.snappy, value: hovering)
    }

    private var cardControls: some View {
        HStack(spacing: 5) {
            if hovering {
                LibraryFavoriteButton(photo: photo)
                LibraryColorMenu(photo: photo)
                if photo.folder == nil {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "rectangle.stack.badge.minus")
                            .font(DS.font(9.5, .medium))
                            .foregroundStyle(DS.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(DS.surface3.opacity(0.9)))
                            .overlay(Circle().stroke(DS.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                    .help(T("从照片库移除", "Remove from library"))
                }
            } else if photo.isFavorite {
                Image(systemName: "star.fill")
                    .font(DS.font(9, .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.black.opacity(0.34)))
            }
        }
        .padding(10)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay {
                ZStack {
                    LinearGradient(
                        colors: [DS.surface2, DS.surface3, DS.surface2],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    if let image = photo.thumbnail {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        VStack(spacing: 9) {
                            Image(systemName: "photo")
                                .font(DS.font(22, .light))
                                .foregroundStyle(DS.textQuaternary)
                            Text(T("正在读取", "Loading"))
                                .font(DS.label(9))
                                .foregroundStyle(DS.textQuaternary)
                        }
                    }
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.58)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 74)
                    }
                    VStack {
                        HStack(spacing: 5) {
                            if let label = photo.colorLabel {
                                Circle().fill(label.color).frame(width: 7, height: 7)
                            }
                            Text(model.stockLabel(for: photo).uppercased())
                                .font(DS.font(8.5, .medium))
                                .tracking(0.7)
                                .foregroundStyle(DS.textPrimary.opacity(0.9))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .frame(height: 19)
                                .background(Capsule().fill(.black.opacity(0.32)))
                                .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                            Spacer()
                            if photo.edit.adjustments.activeCount > 0 {
                                Text("\(photo.edit.adjustments.activeCount)")
                                    .font(DS.mono(8.5))
                                    .foregroundStyle(DS.accent)
                                    .padding(.horizontal, 6)
                                    .frame(height: 19)
                                    .background(Capsule().fill(.black.opacity(0.32)))
                            }
                        }
                        Spacer()
                    }
                    .padding(11)
                }
            }
            .clipped()
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
            }
    }

    private var caption: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(photo.name)
                    .font(DS.font(12, .medium))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(detailLine)
                    .font(DS.mono(8.5))
                    .foregroundStyle(DS.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "arrow.up.right")
                .font(DS.font(8.5, .medium))
                .foregroundStyle(hovering ? DS.accent : DS.textQuaternary)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(hovering ? DS.accent.opacity(0.10) : .clear)
                )
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    private var detailLine: String {
        var parts: [String] = []
        if photo.pixelSize.width > 0 {
            parts.append("\(Int(photo.pixelSize.width)) × \(Int(photo.pixelSize.height))")
        }
        if let camera = photo.metadata.camera, !camera.isEmpty {
            parts.append(camera)
        }
        if let iso = photo.metadata.iso, !iso.isEmpty {
            parts.append("ISO \(iso)")
        }
        if parts.isEmpty {
            parts.append(photo.url.pathExtension.uppercased())
        }
        parts.append(photo.edit.adjustments.activeCount > 0
                     ? T("\(photo.edit.adjustments.activeCount) 项调整", "\(photo.edit.adjustments.activeCount) edits")
                     : T("未调整", "Unedited"))
        return parts.joined(separator: " · ")
    }
}

struct LibraryPhotoRow: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            model.openPhoto(photo.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(DS.surface2)
                    if let image = photo.thumbnail {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo")
                            .font(DS.font(12, .light))
                            .foregroundStyle(DS.textQuaternary)
                    }
                }
                .frame(width: 56, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.name)
                        .font(DS.font(11.5, .medium))
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text("\(model.stockLabel(for: photo)) · \(detailLine)")
                        .font(DS.mono(8.5))
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: hovering ? 100 : 8)
                if !hovering {
                    if let label = photo.colorLabel {
                        Circle().fill(label.color).frame(width: 7, height: 7)
                    }
                    Text(photo.edit.adjustments.activeCount > 0
                         ? T("\(photo.edit.adjustments.activeCount) 项", "\(photo.edit.adjustments.activeCount) edits")
                         : T("未调整", "Unedited"))
                        .font(DS.mono(8.5))
                        .foregroundStyle(DS.textQuaternary)
                        .frame(width: 74, alignment: .trailing)
                    if photo.isFavorite {
                        Image(systemName: "star.fill")
                            .font(DS.font(9, .semibold))
                            .foregroundStyle(DS.accent)
                            .frame(width: 20)
                    }
                    Image(systemName: "chevron.right")
                        .font(DS.font(8.5, .medium))
                        .foregroundStyle(DS.textQuaternary)
                        .padding(.trailing, 2)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .contentShape(Rectangle())
            .background(hovering ? DS.surface2 : .clear)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if hovering {
                HStack(spacing: 2) {
                    LibraryFavoriteButton(photo: photo, compact: true)
                    LibraryColorMenu(photo: photo, compact: true)
                    if photo.folder == nil {
                        Button {
                            onRemove()
                        } label: {
                            Image(systemName: "rectangle.stack.badge.minus")
                                .font(DS.font(9.5, .medium))
                                .foregroundStyle(DS.textSecondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(T("从照片库移除", "Remove from library"))
                    }
                }
                .padding(.trailing, 12)
            }
        }
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
            if value { model.requestThumbnail(photo.id) }
        }
        .onAppear { model.requestThumbnail(photo.id) }
        .onChange(of: photo.thumbnail == nil) { _, missing in
            if missing { model.requestThumbnail(photo.id) }
        }
        .contextMenu {
            Button(T("进入显影", "Develop")) { model.openPhoto(photo.id) }
            Button(photo.isFavorite
                   ? T("取消收藏", "Remove from favorites")
                   : T("收藏", "Add to favorites")) {
                model.toggleFavorite(photo.id)
            }
            Button(T("在访达中显示", "Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([photo.url])
            }
            if photo.folder == nil {
                Divider()
                Button(T("从照片库移除", "Remove from Library"), role: .destructive) {
                    onRemove()
                }
            }
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if photo.pixelSize.width > 0 {
            parts.append("\(Int(photo.pixelSize.width)) × \(Int(photo.pixelSize.height))")
        }
        if let camera = photo.metadata.camera, !camera.isEmpty {
            parts.append(camera)
        }
        if let iso = photo.metadata.iso, !iso.isEmpty {
            parts.append("ISO \(iso)")
        }
        if parts.isEmpty { parts.append(photo.url.pathExtension.uppercased()) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Favorite / colour controls

struct LibraryFavoriteButton: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    var compact = false

    var body: some View {
        Button {
            model.toggleFavorite(photo.id)
        } label: {
            Image(systemName: photo.isFavorite ? "star.fill" : "star")
                .font(DS.font(compact ? 9.5 : 10, .medium))
                .foregroundStyle(photo.isFavorite ? DS.accent : DS.textSecondary)
                .frame(width: compact ? 24 : 24, height: compact ? 24 : 24)
                .background(
                    Circle().fill(compact ? .clear : DS.surface3.opacity(0.9))
                )
                .overlay(
                    Circle().stroke(compact ? .clear : DS.hairlineStrong, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .help(photo.isFavorite
              ? T("取消收藏", "Remove from favorites")
              : T("收藏", "Add to favorites"))
    }
}

struct LibraryColorMenu: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    var compact = false

    var body: some View {
        Menu {
            ForEach(PhotoColorLabel.allCases) { label in
                Button {
                    model.setColorLabel(label, for: photo.id)
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(label.color).frame(width: 8, height: 8)
                        Text(label.title)
                        if photo.colorLabel == label {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button(T("清除标签", "Clear label")) {
                model.setColorLabel(nil, for: photo.id)
            }
            .disabled(photo.colorLabel == nil)
        } label: {
            ZStack {
                Circle()
                    .fill(photo.colorLabel?.color ?? DS.textQuaternary)
                    .frame(width: compact ? 8 : 9, height: compact ? 8 : 9)
                    .opacity(photo.colorLabel == nil ? 0.5 : 1)
                Circle()
                    .stroke(DS.hairlineStrong, lineWidth: 0.5)
                    .frame(width: compact ? 8 : 9, height: compact ? 8 : 9)
            }
            .frame(width: compact ? 24 : 24, height: compact ? 24 : 24)
            .background(Circle().fill(compact ? .clear : DS.surface3.opacity(0.9)))
            .overlay(Circle().stroke(compact ? .clear : DS.hairlineStrong, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(T("颜色标签", "Colour label"))
    }
}

// MARK: - Group header

struct LibraryGroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(DS.font(10, .medium))
                .foregroundStyle(DS.textSecondary)
                .lineLimit(1)
            Text("\(count)")
                .font(DS.mono(8.5))
                .foregroundStyle(DS.textQuaternary)
            Rectangle().fill(DS.hairline).frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - Empty state

struct LibraryEmptyState: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)
            ZStack {
                Circle()
                    .stroke(DS.accent.opacity(0.16), lineWidth: 1)
                    .frame(width: 154, height: 154)
                Circle()
                    .stroke(DS.accent.opacity(0.34), lineWidth: 1)
                    .frame(width: 112, height: 112)
                Circle()
                    .fill(DS.accent.opacity(0.06))
                    .frame(width: 70, height: 70)
                Image(systemName: "photo.on.rectangle.angled")
                    .font(DS.font(27, .light))
                    .foregroundStyle(DS.accent)
            }
            .padding(.bottom, 30)

            Text(T("照片库还是空的", "Your library is empty"))
                .font(DS.font(25, .medium))
                .foregroundStyle(DS.textPrimary)
                .padding(.bottom, 9)

            Text(T("导入照片或整个文件夹后，它们会留在这里。点击任意一张，再进入调色与胶片显影。",
                   "Import photographs or a whole folder. Click any photograph to enter the darkroom."))
                .font(DS.label(12))
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 470)
                .padding(.bottom, 24)

            HStack(spacing: 10) {
                ImportPhotoButton(title: T("导入照片", "Import photos"), large: true)
                FolderImportButton(large: true)
            }

            Text("JPEG · PNG · TIFF · HEIC · RAW · DNG")
                .font(DS.label(9))
                .tracking(1.2)
                .foregroundStyle(DS.textQuaternary)
                .padding(.top, 16)

            Spacer(minLength: 30)
            Text(T("也可以把照片或文件夹拖到窗口任意位置", "Or drop photographs or folders anywhere in the window"))
                .font(DS.label(9.5))
                .foregroundStyle(DS.textQuaternary)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(
                colors: [DS.accent.opacity(0.035), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 330
            )
        )
    }
}

// MARK: - Import buttons

struct ImportPhotoButton: View {
    @Environment(AppModel.self) private var model
    let title: String
    var large = false
    @State private var hovering = false

    var body: some View {
        Button {
            model.chooseFiles()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(DS.font(large ? 11 : 9.5, .semibold))
                Text(title)
                    .font(DS.font(large ? 12.5 : 11, .medium))
            }
            .foregroundStyle(Color(hex: 0x14120E))
            .padding(.horizontal, large ? 18 : 13)
            .frame(height: large ? 36 : 31)
            .background(
                RoundedRectangle(cornerRadius: large ? 8 : 7, style: .continuous)
                    .fill(hovering ? DS.accentStrong : DS.accent)
            )
        }
        .buttonStyle(PressableStyle())
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
        }
        .help(T("导入照片（⌘O）", "Import photographs (⌘O)"))
    }
}

struct FolderImportButton: View {
    @Environment(AppModel.self) private var model
    var large = false
    @State private var hovering = false

    var body: some View {
        Button {
            model.chooseFolder()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.plus")
                    .font(DS.font(large ? 10.5 : 9, .medium))
                Text(T("导入文件夹", "Import folder"))
                    .font(DS.font(large ? 12 : 10.5, .medium))
            }
            .foregroundStyle(hovering ? DS.textPrimary : DS.textSecondary)
            .padding(.horizontal, large ? 14 : 10)
            .frame(height: large ? 36 : 31)
            .background(
                RoundedRectangle(cornerRadius: large ? 8 : 7, style: .continuous)
                    .fill(hovering ? DS.surface3 : DS.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: large ? 8 : 7, style: .continuous)
                    .stroke(DS.hairlineStrong, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
        }
        .help(T("把整个文件夹加入照片库", "Add a folder to the library"))
    }
}

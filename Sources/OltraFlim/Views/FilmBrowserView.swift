import SwiftUI
import AppKit

struct FilmBrowserView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 14)
                .padding(.top, 12)
            if model.libraryMode == .films {
                brandChips
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                activeFilterRow
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("libraryTop")
                    content
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                        .id(model.libraryMode)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                .scrollIndicators(.never)
                .animation(DS.snappy, value: model.libraryMode)
                .onChange(of: model.libraryMode) { _, _ in
                    withAnimation(DS.snappy) {
                        proxy.scrollTo("libraryTop", anchor: .top)
                    }
                }
                .onChange(of: model.currentStockID) { _, newValue in
                    guard model.libraryMode == .films, let newValue else { return }
                    withAnimation(DS.easeOutExpo) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onAppear {
                    if model.libraryMode == .films, let id = model.currentStockID {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
            footer
        }
        .background(DS.surface1)
    }

    @ViewBuilder
    private var content: some View {
        if model.libraryMode == .films {
            if let lut = model.currentImportedLUT {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DS.accent)
                    Text(T("当前使用 LUT：\(lut.name)", "LUT active: \(lut.name)"))
                        .font(DS.label(9))
                        .foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button(T("查看", "View")) {
                        model.libraryMode = .luts
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.accent)
                }
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                )
            }
            if model.filteredStocks.isEmpty {
                EmptyFilmResults()
                    .padding(.top, 54)
            } else {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(model.filteredStocks) { stock in
                        FilmCard(
                            stock: stock,
                            selected: stock.id == model.currentStockID && model.currentImportedLUT == nil,
                            favorite: model.isFavorite(stock),
                            image: model.thumbnail(for: stock)
                        )
                        .id(stock.id)
                    }
                }
            }
        } else {
            lutContent
        }
    }

    @ViewBuilder
    private var lutContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.currentImportedLUT != nil {
                Button {
                    model.clearLUT()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.accent)
                        Text(T("移除当前 LUT，回到胶片显影", "Remove LUT and return to film"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DS.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(DS.accent.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if model.filteredLUTs.isEmpty {
                if model.importedLUTs.isEmpty {
                    EmptyLUTLibrary()
                } else {
                    EmptyLUTResults()
                }
            } else {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(model.filteredLUTs) { lut in
                        ImportedLUTCard(
                            lut: lut,
                            selected: lut.id == model.currentImportedLUT?.id,
                            image: model.importedThumbs[lut.id]
                        )
                    }
                    ImportLUTTile()
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    private var header: some View {
        HStack(spacing: 6) {
            ModeTab(title: T("胶片", "Films"), count: model.catalog.stocks.count,
                    selected: model.libraryMode == .films) {
                withAnimation(DS.snappy) {
                    model.searchText = ""
                    model.libraryMode = .films
                }
            }
            ModeTab(title: "LUT", count: model.importedLUTs.count,
                    selected: model.libraryMode == .luts) {
                withAnimation(DS.snappy) {
                    model.searchText = ""
                    model.libraryMode = .luts
                }
            }
            Spacer(minLength: 4)
            if model.libraryMode == .films {
                Button {
                    model.favoritesOnly.toggle()
                } label: {
                    Image(systemName: model.favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(model.favoritesOnly ? DS.accent : DS.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(model.favoritesOnly ? DS.surface2 : .clear)
                        )
                }
                .buttonStyle(PressableStyle())
                .help(T("只看收藏", "Show favorites only"))

                filterMenu
            } else {
                Button {
                    model.chooseLUTFiles()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(T("导入", "Import"))
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.accent.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.accent.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.isImportingLUT)
                .help(T("导入 .cube 3D LUT", "Import a .cube 3D LUT"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private var filterMenu: some View {
        Menu {
            Section(T("类型", "Type")) {
                Button(T("全部类型", "All types")) { model.typeFilter = nil }
                ForEach(FilmType.allCases.filter { $0 != .lut }, id: \.self) { type in
                    Button {
                        model.typeFilter = type
                    } label: {
                        if model.typeFilter == type {
                            Label(type.localizedLabel, systemImage: "checkmark")
                        } else {
                            Text(type.localizedLabel)
                        }
                    }
                }
            }
            Section(T("引擎", "Engine")) {
                Button(T("全部引擎", "All engines")) { model.engineFilter = nil }
                ForEach(model.engines, id: \.self) { engine in
                    Button {
                        model.engineFilter = engine
                    } label: {
                        if model.engineFilter == engine {
                            Label(engine, systemImage: "checkmark")
                        } else {
                            Text(engine)
                        }
                    }
                }
            }
            Divider()
            Toggle(T("仅收藏", "Favorites only"), isOn: Binding(
                get: { model.favoritesOnly },
                set: { model.favoritesOnly = $0 }
            ))
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(model.activeFilterCount > 0 ? DS.accent : DS.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(model.activeFilterCount > 0 ? DS.surface2 : .clear)
                    )
                if model.activeFilterCount > 0 {
                    Circle().fill(DS.accent).frame(width: 4, height: 4)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(T("筛选胶片", "Filter films"))
    }

    private var searchField: some View {
        SearchField(
            text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
            placeholder: model.libraryMode == .films
                ? T("搜索胶片、品牌、ISO", "Search film, brand, ISO")
                : T("搜索导入的 LUT", "Search imported LUTs")
        )
    }

    private var brandChips: some View {
        HStack(spacing: 5) {
            FilterChip(title: T("全部", "All"), selected: model.brandFilter == nil) {
                model.brandFilter = nil
            }
            ForEach(model.brands, id: \.self) { brand in
                FilterChip(title: brand, selected: model.brandFilter == brand) {
                    model.brandFilter = model.brandFilter == brand ? nil : brand
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var activeFilterRow: some View {
        if model.activeFilterCount > 0 {
            HStack(spacing: 6) {
                if let type = model.typeFilter {
                    ActiveFilterChip(title: type.localizedLabel) { model.typeFilter = nil }
                }
                if let engine = model.engineFilter {
                    ActiveFilterChip(title: engine) { model.engineFilter = nil }
                }
                if model.favoritesOnly {
                    ActiveFilterChip(title: T("收藏", "Favorites")) { model.favoritesOnly = false }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle().fill(DS.hairline).frame(height: 1)
            HStack(spacing: 6) {
                statusDot
                switch model.libraryState {
                case .loading(let progress, let phase):
                    Text("\(phase) · \(Int(progress * 100))%")
                        .font(DS.label(9))
                        .foregroundStyle(DS.textTertiary)
                case .failed(let message):
                    Text(message)
                        .font(DS.label(9))
                        .foregroundStyle(DS.danger)
                        .lineLimit(1)
                case .ready:
                    if model.libraryMode == .films {
                        Text(T("\(lookCount) 个外观 · \(model.catalog.stocks.count) 种胶片",
                               "\(lookCount) looks · \(model.catalog.stocks.count) stocks"))
                            .font(DS.label(9))
                            .foregroundStyle(DS.textTertiary)
                    } else {
                        Text(T("\(model.importedLUTs.count) 个自定义 LUT · Rec.709 显示方式",
                               "\(model.importedLUTs.count) custom LUTs · Rec.709 display"))
                            .font(DS.label(9))
                            .foregroundStyle(DS.textTertiary)
                    }
                case .idle:
                    Text(T("胶片库准备中", "Readying film pack"))
                        .font(DS.label(9))
                        .foregroundStyle(DS.textTertiary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/andreavolpato/spektrafilm")!)
                } label: {
                    Text("spektrafilm")
                        .font(DS.label(8.5))
                        .foregroundStyle(DS.textQuaternary)
                }
                .buttonStyle(.plain)
                .help(T("胶片模型由 spektrafilm 驱动", "Film modeling powered by spektrafilm"))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 9)
        }
        .padding(.top, 7)
        .background(DS.surface1)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 4, height: 4)
    }

    private var statusColor: Color {
        switch model.libraryState {
        case .ready: return DS.accent
        case .failed: return DS.danger
        case .loading: return DS.textTertiary
        case .idle: return DS.textQuaternary
        }
    }

    private var lookCount: Int {
        model.catalog.stocks.reduce(0) { $0 + $1.variants.count }
    }
}

// MARK: - Mode tabs

struct ModeTab: View {
    let title: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 10, weight: selected ? .medium : .regular))
                Text("\(count)")
                    .font(DS.mono(8))
                    .opacity(selected ? 0.8 : 0.55)
            }
            .foregroundStyle(selected ? DS.accent : (hovering ? DS.textSecondary : DS.textTertiary))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? DS.surface2 : (hovering ? DS.surface2.opacity(0.7) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? DS.accent.opacity(0.3) : DS.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Search

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(focused ? DS.accent : DS.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DS.textPrimary)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                .fill(DS.surface0)
                .shadow(color: .black.opacity(focused ? 0.48 : 0), radius: 12, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                .stroke(DS.hairline, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rSmall, style: .continuous)
                .stroke(Color.white.opacity(focused ? 0.07 : 0), lineWidth: 1)
        )
        .animation(DS.easeQuick, value: focused)
    }
}

// MARK: - Chips

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? DS.accent : (hovering ? DS.textSecondary : DS.textTertiary))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? DS.surface2 : (hovering ? DS.surface2.opacity(0.7) : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(selected ? DS.accent.opacity(0.3) : DS.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }
}

struct ActiveFilterChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(DS.accent.opacity(0.1)))
            .overlay(Capsule().stroke(DS.accent.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cards

struct FilmCard: View {
    @Environment(AppModel.self) private var model
    let stock: FilmStock
    let selected: Bool
    let favorite: Bool
    let image: CGImage?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                model.selectStock(stock)
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stock.name)
                            .font(.system(size: 11, weight: selected ? .medium : .regular))
                            .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if selected {
                                Circle().fill(DS.accent).frame(width: 3.5, height: 3.5)
                            }
                            Text(stock.brand)
                                .font(.system(size: 8.5, weight: .medium))
                                .tracking(0.4)
                                .foregroundStyle(DS.textTertiary)
                            Text(stock.type.localizedShortLabel)
                                .font(.system(size: 7.5, weight: .semibold))
                                .tracking(0.2)
                                .foregroundStyle(DS.textQuaternary)
                            Spacer(minLength: 0)
                            if let iso = stock.iso {
                                Text("\(iso)")
                                    .font(DS.mono(8))
                                    .foregroundStyle(DS.textQuaternary)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? DS.surface2 : (hovering ? DS.surface2.opacity(0.66) : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(selected ? DS.accent.opacity(0.72) : DS.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(favorite ? T("取消收藏", "Remove from Favorites") : T("加入收藏", "Add to Favorites")) {
                    model.toggleFavorite(stock)
                }
                Button(T("应用 \(stock.name)", "Apply \(stock.name)")) {
                    model.selectStock(stock)
                }
            }

            if favorite || hovering {
                Button {
                    model.toggleFavorite(stock)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(favorite ? DS.accent : DS.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.42)))
                }
                .buttonStyle(.plain)
                .padding(10)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(DS.easeQuick, value: hovering)
        .animation(DS.snappy, value: selected)
        .help("\(stock.brand) \(stock.name) · \(stock.type.localizedLabel)")
    }

    private var thumbnail: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: swatchColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private var swatchColors: [Color] {
        let colors = stock.swatch.compactMap { Color(hexString: $0) }
        if colors.count >= 3 { return [colors[0], colors[1], colors[2]] }
        return [DS.surface2, DS.surface3, DS.surface4]
    }
}

struct ImportedLUTCard: View {
    @Environment(AppModel.self) private var model
    let lut: ImportedLUT
    let selected: Bool
    let image: CGImage?
    @State private var hovering = false

    var body: some View {
        Button {
            model.selectImportedLUT(lut)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: swatchColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(height: 72)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(lut.name)
                        .font(.system(size: 11, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if selected {
                            Circle().fill(DS.accent).frame(width: 3.5, height: 3.5)
                        }
                        Text("LUT")
                            .font(.system(size: 7.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(DS.accent.opacity(0.8))
                        Text(lut.subtitle)
                            .font(.system(size: 8))
                            .foregroundStyle(DS.textQuaternary)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 1)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? DS.surface2 : (hovering ? DS.surface2.opacity(0.66) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(selected ? DS.accent.opacity(0.72) : DS.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DS.snappy, value: selected)
        .contextMenu {
            Button(T("应用 \(lut.name)", "Apply \(lut.name)")) {
                model.selectImportedLUT(lut)
            }
            Divider()
            Button(T("删除这个 LUT", "Delete this LUT"), role: .destructive) {
                model.deleteImportedLUT(lut)
            }
        }
        .help(T("导入的 Rec.709 显示 LUT", "Imported Rec.709 display LUT"))
    }

    private var swatchColors: [Color] {
        let colors = lut.swatch.compactMap { Color(hexString: $0) }
        if colors.count >= 2 { return colors }
        return [DS.surface2, DS.surface4]
    }
}

struct ImportLUTTile: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.chooseLUTFiles()
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? DS.surface3 : DS.surface2)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(hovering ? DS.accent : DS.textTertiary)
                }
                .frame(height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.hairline, lineWidth: 1)
                )
                Text(T("导入 .cube", "Import .cube"))
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(DS.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 1)
                    .padding(.bottom, 9)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? DS.surface2.opacity(0.66) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(DS.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(model.isImportingLUT)
        .help(T("导入 .cube 3D LUT", "Import a .cube 3D LUT"))
    }
}

// MARK: - Empty states

struct EmptyFilmResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(DS.textTertiary)
            Text(T("没有匹配的胶片", "No films match"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
            Text(T("试试其他关键词，或清除当前筛选。", "Try another search, or clear the active filters."))
                .font(DS.label(9.5))
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
            Button {
                withAnimation(DS.easeQuick) {
                    model.searchText = ""
                    model.brandFilter = nil
                    model.typeFilter = nil
                    model.engineFilter = nil
                    model.favoritesOnly = false
                }
            } label: {
                Text(T("清除筛选", "Clear filters"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 25)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.accent.opacity(0.24), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyLUTLibrary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DS.textTertiary)
            Text(T("还没有导入 LUT", "No imported LUTs yet"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
            Text(T("导入 .cube 3D LUT 后，它会出现在这里，并可作为 Rec.709 显示 LUT 作用于当前照片。",
                    "Import a .cube 3D LUT and it will appear here, applied as a Rec.709 display LUT."))
                .font(DS.label(9.5))
                .foregroundStyle(DS.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 210)
            Button {
                model.chooseLUTFiles()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                    Text(T("导入 .cube LUT", "Import .cube LUT"))
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DS.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DS.accent.opacity(0.24), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }
}

struct EmptyLUTResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(DS.textTertiary)
            Text(T("没有匹配的 LUT", "No LUTs match"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textSecondary)
            Button {
                model.searchText = ""
            } label: {
                Text(T("清除搜索", "Clear search"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 25)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.surface2)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }
}

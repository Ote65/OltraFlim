import SwiftUI
import AppKit

struct FilmstripView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(T("照片", "PHOTOS"))
                    .font(DS.font(8.5, .medium))
                    .tracking(1.4)
                    .foregroundStyle(DS.textTertiary)
                Text("\(model.collectionPhotos.count)")
                    .font(DS.mono(9))
                    .foregroundStyle(DS.textQuaternary)
            }
            .frame(width: 44, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 7) {
                    ForEach(model.collectionPhotos) { photo in
                        PhotoStripTile(
                            photo: photo,
                            selected: photo.id == model.selectedPhotoID
                        )
                    }
                    AddPhotoTile()
                }
                .padding(.vertical, 9)
            }
            Spacer(minLength: 0)
            if let photo = model.currentPhoto {
                Text(photo.metadata.captured.map(Self.dateText) ?? "")
                    .font(DS.mono(8.5))
                    .foregroundStyle(DS.textQuaternary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 88)
        .background(DS.surface1)
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

struct PhotoStripTile: View {
    @Environment(AppModel.self) private var model
    let photo: Photo
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            model.selectPhoto(photo.id)
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DS.surface2)
                if let thumbnail = photo.thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(DS.font(12, .light))
                        .foregroundStyle(DS.textQuaternary)
                }
                if hovering {
                    Text(photo.name)
                        .font(DS.font(7.5))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 15)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.72)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .transition(.opacity)
                }
            }
            .frame(width: 66, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? DS.accent : (hovering ? DS.hairlineStrong : DS.hairline),
                            lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(hovering ? 0.42 : 0), radius: 8, y: 4)
            .offset(y: hovering ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onAppear { model.requestThumbnail(photo.id) }
        .onChange(of: photo.thumbnail == nil) { _, missing in
            if missing { model.requestThumbnail(photo.id) }
        }
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
        }
        .animation(DS.snappy, value: selected)
        .contextMenu {
            Button(T("在访达中显示", "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([photo.url])
            }
            Divider()
            Button(T("移除照片", "Remove Photograph")) {
                model.removePhoto(photo.id)
            }
        }
        .help(photo.name)
    }
}

struct AddPhotoTile: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        Button {
            model.chooseFiles()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(hovering ? DS.surface3 : DS.surface2)
                    .overlay(
                        Image(systemName: "plus")
                            .font(DS.font(12, .medium))
                            .foregroundStyle(hovering ? DS.accent : DS.textTertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(DS.hairline, lineWidth: 1)
                    )
            }
            .frame(width: 66, height: 46)
            .offset(y: hovering ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(DS.easeQuick) { hovering = value }
        }
        .help(T("继续导入照片", "Import more photographs"))
    }
}

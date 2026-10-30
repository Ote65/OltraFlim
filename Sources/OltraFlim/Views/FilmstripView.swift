import SwiftUI
import AppKit

struct FilmstripView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(T("照片", "PHOTOS"))
                    .font(.system(size: 8.5, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(DS.textTertiary)
                Text("\(model.collectionPhotos.count)")
                    .font(DS.mono(9))
                    .foregroundStyle(DS.textQuaternary)
            }
            .frame(width: 44, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
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
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DS.surface2)
                    if let thumbnail = photo.thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(DS.textQuaternary)
                    }
                }
                .frame(width: 64, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(selected ? DS.accent.opacity(0.7) : (hovering ? DS.hairlineStrong : DS.hairline), lineWidth: 1)
                )
                Text(photo.name)
                    .font(.system(size: 8))
                    .foregroundStyle(selected ? DS.textSecondary : DS.textQuaternary)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(hovering ? DS.surface3 : DS.surface2)
                    .frame(width: 64, height: 42)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(hovering ? DS.accent : DS.textTertiary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(DS.hairline, lineWidth: 1)
                    )
                Text(T("导入", "Import"))
                    .font(.system(size: 8))
                    .foregroundStyle(DS.textQuaternary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(T("继续导入照片", "Import more photographs"))
    }
}

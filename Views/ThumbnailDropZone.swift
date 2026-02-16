import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ThumbnailDropZone: View {
    let title: String
    @Binding var image: NSImage?
    @State private var isTargeted = false
    @Binding var showImporter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.black.opacity(0.86))

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isTargeted ? Color(red: 1.0, green: 0.0, blue: 0.0).opacity(0.75) : Color.black.opacity(0.12),
                                style: StrokeStyle(lineWidth: 1.4, dash: [7, 5])
                            )
                    )

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.45))
                        Text("Drag & Drop Image")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.75))
                        Button("Choose File") { showImporter = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            .frame(height: 176)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                loadFromProviders(providers)
            }

            if image != nil {
                Button("Replace File") { showImporter = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func loadFromProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  let nsImage = NSImage(contentsOf: url) else {
                return
            }
            DispatchQueue.main.async {
                self.image = nsImage
            }
        }
        return true
    }
}

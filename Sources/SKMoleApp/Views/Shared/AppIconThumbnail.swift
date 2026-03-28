import AppKit
import SwiftUI

struct AppIconThumbnail: View {
    private let icon: NSImage
    private let size: CGFloat
    private let cornerRadius: CGFloat

    init(url: URL, size: CGFloat = 40, cornerRadius: CGFloat = 10) {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: size, height: size)
        self.icon = image
        self.size = size
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}

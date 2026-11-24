import SwiftUI
import UIKit

struct FeedbackAttachmentImage<Content: View>: View {
    let attachment: FeedbackAttachment
    let baseURL: URL
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase = AsyncImagePhase.empty

    var body: some View {
        if let url = attachment.productionImageURL(baseURL: baseURL) {
            content(phase)
                .task(id: url) { await load(url) }
        } else {
            AsyncImage(url: attachment.resolvedURL(baseURL: baseURL), content: content)
        }
    }

    private func load(_ url: URL) async {
        phase = .empty
        do {
            let request = URLRequest(url: url, timeoutInterval: 10)
            let (data, response) = try await URLSession.shared.sumlyData(for: request, baseURL: baseURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            phase = .success(Image(uiImage: image))
        } catch {
            if !Task.isCancelled { phase = .failure(error) }
        }
    }
}

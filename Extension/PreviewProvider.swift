import EDLKit
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL)
        let html = HTMLRenderer().render(EDLParser.parse(data: data), fileName: request.fileURL.lastPathComponent)
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 1000, height: 720)) { _ in
            Data(html.utf8)
        }
        reply.stringEncoding = .utf8
        return reply
    }
}

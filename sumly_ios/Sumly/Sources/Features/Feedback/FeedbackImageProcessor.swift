import CoreGraphics
import Foundation
import UIKit

/// 反馈截图压缩工具：缩放至长边 <= 1600px，JPEG 质量 0.78，确保远小于后端 3MB 上限。
enum FeedbackImageProcessor {
    static let maxLongEdge: CGFloat = 1600
    static let defaultCompressionQuality: CGFloat = 0.78
    static let targetMaxBytes: Int = 2_800_000

    enum ProcessingError: Error, LocalizedError, Equatable, Sendable {
        case unreadableImage
        case encodingFailed
        case exceedsSizeLimit

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "无法读取所选图片，请重新选择。"
            case .encodingFailed: "图片压缩失败，请尝试其他图片。"
            case .exceedsSizeLimit: "图片体积过大，请选择更小的截图。"
            }
        }
    }

    /// 计算按长边等比缩放后的像素尺寸（不放大小图）。
    static func targetPixelSize(for originalSize: CGSize, maxLongEdge: CGFloat = maxLongEdge) -> CGSize {
        guard originalSize.width > 0, originalSize.height > 0, maxLongEdge > 0 else {
            return originalSize
        }
        let longEdge = max(originalSize.width, originalSize.height)
        guard longEdge > maxLongEdge else {
            return CGSize(width: originalSize.width.rounded(), height: originalSize.height.rounded())
        }
        let ratio = maxLongEdge / longEdge
        return CGSize(
            width: max(1, (originalSize.width * ratio).rounded()),
            height: max(1, (originalSize.height * ratio).rounded())
        )
    }

    /// 将任意图片原始字节压缩为符合要求的 JPEG 数据。
    static func compressToJPEG(
        rawData: Data,
        maxLongEdge: CGFloat = maxLongEdge,
        quality: CGFloat = defaultCompressionQuality,
        maxBytes: Int = targetMaxBytes
    ) throws -> Data {
        guard let image = UIImage(data: rawData) else {
            throw ProcessingError.unreadableImage
        }
        return try compressToJPEG(
            image: image,
            maxLongEdge: maxLongEdge,
            quality: quality,
            maxBytes: maxBytes
        )
    }

    /// 将 `UIImage` 缩放并编码为 JPEG 数据（自动处理 EXIF 方向）。
    static func compressToJPEG(
        image: UIImage,
        maxLongEdge: CGFloat = maxLongEdge,
        quality: CGFloat = defaultCompressionQuality,
        maxBytes: Int = targetMaxBytes
    ) throws -> Data {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let targetSize = targetPixelSize(for: pixelSize, maxLongEdge: maxLongEdge)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        let qualitySteps: [CGFloat] = [quality, 0.65, 0.50, 0.35].filter { $0 > 0 && $0 <= 1 }
        var lastData: Data?
        for step in qualitySteps {
            guard let data = rendered.jpegData(compressionQuality: step) else {
                continue
            }
            lastData = data
            if data.count <= maxBytes {
                return data
            }
        }
        if let lastData, lastData.count <= FeedbackValidation.maxAttachmentBytes {
            return lastData
        }
        throw lastData == nil ? ProcessingError.encodingFailed : ProcessingError.exceedsSizeLimit
    }
}

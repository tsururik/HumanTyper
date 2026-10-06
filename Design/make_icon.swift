// Генерирует иконку приложения из Design/logo.png: знак (рука + клавиша) без надписи
// на белой плашке в форме иконки macOS.
//
// Запуск из корня проекта:  swift Design/make_icon.swift
import AppKit

let logoURL = URL(fileURLWithPath: "Design/logo.png")
let masterURL = URL(fileURLWithPath: "Design/AppIcon-1024.png")
let iconSetURL = URL(fileURLWithPath: "HumanTyper/Assets.xcassets/AppIcon.appiconset")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil) -> CGContext {
    CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - 1. Вырезаем знак и убираем белый фон

guard let source = NSImage(contentsOf: logoURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Не удалось открыть \(logoURL.path)")
}
let width = source.width
let height = source.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { buffer in
    let context = makeContext(width: width, height: height, data: buffer.baseAddress)
    context.setFillColor(.white)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
}

// Знак зелёный, надпись чёрная: границы знака ищем только по зелёным пикселям.
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        if g > r + 40, g > b + 10 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
let margin = 4
minX = max(minX - margin, 0); minY = max(minY - margin, 0)
maxX = min(maxX + margin, width - 1); maxY = min(maxY + margin, height - 1)
let cropWidth = maxX - minX + 1
let cropHeight = maxY - minY + 1

// «Цвет в прозрачность» относительно белого: чистые края без белого ореола и шума сжатия.
var mark = [UInt8](repeating: 0, count: cropWidth * cropHeight * 4)
for y in 0..<cropHeight {
    for x in 0..<cropWidth {
        let s = ((y + minY) * width + (x + minX)) * 4
        let d = (y * cropWidth + x) * 4
        let channels = (0..<3).map { Double(pixels[s + $0]) }
        var alpha = channels.map { (255 - $0) / 255 }.max()!
        if alpha < 0.06 { alpha = 0 }
        for c in 0..<3 {
            // Предумноженный цвет: c − 255·(1 − α).
            mark[d + c] = UInt8(max(0, min(255, channels[c] - 255 * (1 - alpha))).rounded())
        }
        mark[d + 3] = UInt8((alpha * 255).rounded())
    }
}
let markImage = mark.withUnsafeMutableBytes { buffer in
    makeContext(width: cropWidth, height: cropHeight, data: buffer.baseAddress).makeImage()!
}

// MARK: - 2. Иконка 1024×1024 по сетке macOS: плашка 824×824 с отступом 100

let size = 1024
let canvas = makeContext(width: size, height: size)
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

canvas.saveGState()
canvas.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
canvas.addPath(platePath)
canvas.setFillColor(.white)
canvas.fillPath()
canvas.restoreGState()

// Тонкая граница, чтобы белая иконка не терялась на белом фоне Finder.
canvas.addPath(platePath)
canvas.setStrokeColor(CGColor(gray: 0, alpha: 0.08))
canvas.setLineWidth(2)
canvas.strokePath()

let markSide: CGFloat = 560
let scale = markSide / CGFloat(max(cropWidth, cropHeight))
let markSize = CGSize(width: CGFloat(cropWidth) * scale, height: CGFloat(cropHeight) * scale)
canvas.interpolationQuality = .high
canvas.draw(markImage, in: CGRect(
    x: (CGFloat(size) - markSize.width) / 2,
    y: (CGFloat(size) - markSize.height) / 2,
    width: markSize.width,
    height: markSize.height
))
let master = canvas.makeImage()!
writePNG(master, to: masterURL)

// MARK: - 3. Набор размеров для Assets.xcassets

try FileManager.default.createDirectory(at: iconSetURL, withIntermediateDirectories: true)
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scaleFactor in [1, 2] {
        let pixelsSide = points * scaleFactor
        let name = "icon_\(points)x\(points)\(scaleFactor == 2 ? "@2x" : "").png"
        let context = makeContext(width: pixelsSide, height: pixelsSide)
        context.interpolationQuality = .high
        context.draw(master, in: CGRect(x: 0, y: 0, width: pixelsSide, height: pixelsSide))
        writePNG(context.makeImage()!, to: iconSetURL.appendingPathComponent(name))
        entries.append("""
            { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scaleFactor)x", "size" : "\(points)x\(points)" }
        """)
    }
}
let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contents.write(to: iconSetURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try """
{
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: iconSetURL.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("Знак: \(cropWidth)×\(cropHeight) px из (\(minX), \(minY)); иконка: \(masterURL.path), \(entries.count) размеров")

// main.swift
import Foundation
import Vision
import AppKit

// MARK: - Region Selector View
class RegionSelectorView: NSView {
    var image: NSImage
    var selection: NSRect?
    var startPoint: NSPoint?
    var completion: ((CGRect) -> Void)?

    init(image: NSImage, completion: @escaping (CGRect) -> Void) {
        self.image = image
        self.completion = completion
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        if let selection = selection {
            NSColor.red.setStroke()
            NSBezierPath(rect: selection).stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, current.x),
                           y: min(start.y, current.y),
                           width: abs(current.x - start.x),
                           height: abs(current.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection = selection else { return }
        completion?(selection)
    }
}

// MARK: - Load CGImage
func loadImage(from path: String) -> NSImage? {
    let url = URL(fileURLWithPath: path)
    return NSImage(contentsOf: url)
}

func cgImage(from nsImage: NSImage) -> CGImage? {
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
    return bitmap.cgImage
}

// MARK: - OCR
func performOCR(on cgImage: CGImage, region: CGRect?, imageSize: CGSize, outputURL: URL, completion: @escaping (String) -> Void) {
    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            print("OCR error: \(error.localizedDescription)")
            completion("")
            return
        }

        let results = (request.results as? [VNRecognizedTextObservation]) ?? []
        let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")

        do {
            try text.write(to: outputURL, atomically: true, encoding: .utf8)
            print("✅ Saved OCR result to \(outputURL.path)")
        } catch {
            print("❌ Failed to save output: \(error.localizedDescription)")
        }

        completion(text)
    }

    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.minimumTextHeight = 0.01

    var handler: VNImageRequestHandler
    if let region = region {
        let normalized = CGRect(x: region.minX / imageSize.width,
                                y: region.minY / imageSize.height,
                                width: region.width / imageSize.width,
                                height: region.height / imageSize.height)
	request.regionOfInterest = normalized
    }
    handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

    do {
        try handler.perform([request])
    } catch {
        print("Failed to perform OCR: \(error.localizedDescription)")
        completion("")
    }
}

// MARK: - Entry Point
let args = CommandLine.arguments

guard args.count == 2 else {
    print("Usage: SwiftOCR <image_path>")
    exit(1)
}

let imagePath = args[1]
let inputURL = URL(fileURLWithPath: imagePath)
let outputURL = inputURL.deletingPathExtension().appendingPathExtension("txt")

guard let nsImage = loadImage(from: imagePath),
      let cgImage = cgImage(from: nsImage) else {
    print("❌ Failed to load image from \(imagePath)")
    exit(1)
}

DispatchQueue.main.async {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: nsImage.size),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
    window.title = "Select Region"
    window.makeKeyAndOrderFront(nil)

    let selectorView = RegionSelectorView(image: nsImage) { selectedRect in
        performOCR(on: cgImage, region: selectedRect, imageSize: nsImage.size, outputURL: outputURL) { text in
            print("\n🔍 OCR Result:\n\(text)")
            NSApp.terminate(nil)
        }
    }

    window.contentView = selectorView
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()

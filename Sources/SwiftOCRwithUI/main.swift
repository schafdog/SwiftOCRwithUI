import AppKit
import Foundation
import Vision

// MARK:  Region Selector View
class RegionSelectorView: NSView {
    var image: NSImage
    var scaledImage: NSImage
    var scale: CGFloat
    var selection: NSRect?
    var startPoint: NSPoint?
    var completion: ((CGRect) -> Void)?

    init(
        image: NSImage, scaleToFit maxSize: CGSize, allowScaling: Bool = true,
        completion: @escaping (CGRect) -> Void
    ) {
        self.image = image

        if allowScaling {
            let widthRatio = maxSize.width / image.size.width
            let heightRatio = maxSize.height / image.size.height
            self.scale = 0.9 * min(1.0, min(widthRatio, heightRatio))
        } else {
            self.scale = 1.0
        }

        let newSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        self.scaledImage = NSImage(size: newSize)
        self.scaledImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .sourceOver,
            fraction: 1.0)
        self.scaledImage.unlockFocus()

        super.init(frame: NSRect(origin: .zero, size: newSize))
        self.completion = completion
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        scaledImage.draw(in: bounds)
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
        selection = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection = selection else { return }
        let unscaled = NSRect(
            x: selection.origin.x / scale,
            y: selection.origin.y / scale,
            width: selection.size.width / scale,
            height: selection.size.height / scale)
        print("Selection \(selection) / \(scale) = $\(unscaled)")
        completion?(unscaled)
    }
}

func saveRegionAsJPEG(from cgImage: CGImage, region: CGRect, to url: URL) {
    guard let cropped = cgImage.cropping(to: region) else {
        print("❌ Failed to crop region for JPEG")
        return
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cropped)
    guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [:]) else {
        print("❌ Failed to create JPEG data")
        return
    }

    do {
        try jpegData.write(to: url)
        print("🖼 Saved cropped region as JPEG to \(url.path)")
    } catch {
        print("❌ Failed to write JPEG: \(error.localizedDescription)")
    }
}

// MARK: - Load CGImage
func loadImage(from path: String) -> NSImage? {
    let url = URL(fileURLWithPath: path)
    return NSImage(contentsOf: url)
}

// MARK: - Helper Functions
func cgImage(from nsImage: NSImage) -> CGImage? {
    guard let tiffData = nsImage.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData)
    else { return nil }
    return bitmap.cgImage
}

func performOCR(
    on cgImage: CGImage, region: CGRect?, imageSize: CGSize, outputURL: URL,
    completion: @escaping (String) -> Void
) {
    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            print("OCR error: \(error.localizedDescription)")
            completion("")
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
        let normalized = CGRect(
            x: region.minX / imageSize.width,
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

if args.count < 2 {
    print("Usage: SwiftOCR <image_path> [--noscale]")
    exit(1)
}

let path = args[1]
let noscale = args.contains("--noscale")

let url = URL(fileURLWithPath: path)
let basename = url.deletingPathExtension()
let regionOutputURL = basename.appendingPathExtension("region.txt")
let outputURL = basename.appendingPathExtension("txt")
let croppedImageURL = basename.appendingPathExtension("cropped.jpg")

guard let image = NSImage(contentsOf: url), let cg = cgImage(from: image) else {
    print("Failed to load image")
    exit(1)
}

DispatchQueue.main.async {
    let screenSize = NSScreen.main?.visibleFrame.size ?? NSSize(width: 800, height: 600)
    let selectorView = RegionSelectorView(
        image: image, scaleToFit: screenSize, allowScaling: !noscale
    ) {
        selectedRect in

        // Save region to file
        let regionString = String(
            format: "%.2f %.2f %.2f %.2f",
            selectedRect.origin.x,
            selectedRect.origin.y,
            selectedRect.size.width,
            selectedRect.size.height)
        do {
            try regionString.write(to: regionOutputURL, atomically: true, encoding: .utf8)
            print("Region selected \(regionString)")
            print("📐 Saved region to \(regionOutputURL.path)")
        } catch {
            print("❌ Failed to save region: \(error.localizedDescription)")
        }

        // Flip coordinates
        let flippedRect = NSRect(
            x: selectedRect.origin.x,
            y: image.size.height - selectedRect.origin.y - selectedRect.height,
            width: selectedRect.width,
            height: selectedRect.height
        )
        print("📍 Selected Rect: \(selectedRect)")
        print("↕️ Flipped Rect: \(flippedRect)")
        saveRegionAsJPEG(from: cg, region: flippedRect, to: croppedImageURL)
        performOCR(on: cg, region: selectedRect, imageSize: image.size, outputURL: outputURL) {
            text in
            print("\n🔍 OCR Result:\n\(text)")
            NSApp.terminate(nil)
        }
    }

    let window = NSWindow(
        contentRect: selectorView.frame,
        styleMask: [.titled, .closable],
        backing: .buffered, defer: false)
    window.title = "Select Region"
    window.contentView = selectorView
    window.makeKeyAndOrderFront(nil)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()

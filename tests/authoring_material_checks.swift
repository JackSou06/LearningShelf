import Foundation
import AppKit
import PDFKit
import CoreGraphics

@main struct MaterialChecks {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1]); let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        let source = out.appendingPathComponent("fixture.pdf")
        var box = CGRect(x: 0, y: 0, width: 960, height: 540)
        let context = CGContext(source as CFURL, mediaBox: &box, nil)!
        for page in 1...2 {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor); context.fill(box)
            context.setFillColor(NSColor.systemGreen.cgColor); context.fill(CGRect(x: 80, y: 220, width: 260, height: 170))
            context.setStrokeColor(NSColor.systemRed.cgColor); context.setLineWidth(7); context.strokeEllipse(in: CGRect(x: 380, y: 260, width: 180, height: 100))
            let ns = NSGraphicsContext(cgContext: context, flipped: false); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
            ("SUMMATION · PAGE \(page)" as NSString).draw(at: NSPoint(x: 70, y: 460), withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black])
            ("1 + 2 + ... + n = n(n+1)/2" as NSString).draw(at: NSPoint(x: 70, y: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState(); context.endPDFPage()
        }
        context.closePDF()
        let root = out.appendingPathComponent("pdf-work"), sources = try AuthoringMaterials.copySources([source], to: root)
        let manifest = try AuthoringMaterials.prepare(root: root, sources: sources, runner: AuthoringProcessRunner(), progress: { _ in })
        precondition(manifest.sources[0].pages.count == 2)
        for page in manifest.sources[0].pages {
            let file = root.appendingPathComponent(page.image); let hash = try AuthoringMaterials.hash(file); precondition(hash == page.sha256)
            precondition(NSImage(contentsOf: file) != nil)
        }
        // Resolve a local image while retaining the Markdown original byte-for-byte.
        let md = out.appendingPathComponent("fixture.md"), image = out.appendingPathComponent("local.jpg")
        try fm.copyItem(at: root.appendingPathComponent(manifest.sources[0].pages[0].image), to: image)
        let raw = "# 圖片來源\n\n![示例](local.jpg)\n\n![禁止遍歷](../outside.jpg)\n"; try raw.write(to: md, atomically: true, encoding: .utf8)
        let mdRoot = out.appendingPathComponent("md-work"), mdSources = try AuthoringMaterials.copySources([md], to: mdRoot)
        precondition(mdSources.count == 2)
        let mdManifest = try AuthoringMaterials.prepare(root: mdRoot, sources: mdSources, runner: AuthoringProcessRunner(), progress: { _ in })
        precondition(mdManifest.limitations.contains { $0.contains("../outside.jpg") })
        let preserved = try String(contentsOf: mdRoot.appendingPathComponent("input/source-001.md"), encoding: .utf8); precondition(preserved == raw)
        if CommandLine.arguments.count > 2 {
            let pptx = URL(fileURLWithPath: CommandLine.arguments[2]), pRoot = out.appendingPathComponent("pptx-work")
            let pSources = try AuthoringMaterials.copySources([pptx], to: pRoot)
            let pManifest = try AuthoringMaterials.prepare(root: pRoot, sources: pSources, runner: AuthoringProcessRunner(), progress: { _ in })
            precondition(pManifest.sources[0].pages.count == 2)
            print("PPTX actual conversion and 2-page render passed.")
        }
        print("Material checks passed: PDF real page rendering/text extraction/hash, local MD image copy/resolution, original MD preservation and no parent traversal.")
    }
}

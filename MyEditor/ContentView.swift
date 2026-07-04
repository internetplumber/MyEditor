import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum ThemeSetting: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { self.rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}
struct ContentView: View {
    @State private var text = ""
    @State private var lastSavedText = ""
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var isLineWrapped = true // Default to wrapped layout
    @State private var fontSize: CGFloat = 13.0 // Scalable editor context base

    
    // Feature Visibility States
    @State private var showSearch = false
    @State private var showGutter = true
    @State private var useRegex = false
    @State private var currentTheme: ThemeSetting = .system
    
    // Converted to Bindings linked from your App Lifecycle Menu Scene
    @Binding var showImporter: Bool
    @Binding var showExporter: Bool
    
    // Disk Tracking States
    @State private var currentFileURL: URL? = nil
    @State private var showAlertFileChanged = false
    @State private var activeFileMonitor: FileNotificationMonitor? = nil
    
    // Cursor Tracking Coordinates
    @State private var cursorLine = 1
    @State private var cursorColumn = 1
    
    private var isModified: Bool { text != lastSavedText }
    
    var body: some View {
        VStack(spacing: 0) {
            if showSearch { searchBar }
            
            HStack(spacing: 0) {
                if showGutter {
                    LineGutterView(text: text, fontSize: fontSize) // Passed font parameter here
                }
                
                NativeTextView(
                    text: $text,
                    cursorLine: $cursorLine,
                    cursorColumn: $cursorColumn,
                    theme: currentTheme,
                    isLineWrapped: isLineWrapped,
                    fontSize: fontSize // Passed font parameter here
                )
            }
            
            statusBar
        }
        .frame(minWidth: 700, minHeight: 480)
        .preferredColorScheme(currentTheme.colorScheme)
        .toolbar {
            ToolbarItemGroup {
                Button(action: { showImporter = true }) { Label("Open", systemImage: "doc.badge.plus") }
                Button(action: { showExporter = true }) { Label("Save As", systemImage: "doc.badge.arrow.up") }
                Button(action: { showGutter.toggle() }) { Label("Toggle Gutter", systemImage: "sidebar.left") }
                Button(action: { showSearch.toggle() }) { Label("Find", systemImage: "magnifyingglass") }
                Button(action: { isLineWrapped.toggle() }) {
                    Label("Toggle Wrap", systemImage: isLineWrapped ? "text.alignleft" : "line.3.horizontal")
                }
                // Streamlined Theme Popover Selection Menu
                Menu {
                    ForEach(ThemeSetting.allCases) { setting in
                        Button(action: { currentTheme = setting }) {
                            HStack {
                                Text(setting.rawValue)
                                if currentTheme == setting {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Theme", systemImage: "paintbrush")
                }
                .menuStyle(.borderlessButton) // Strips the bulky picker wrapper padding
                .frame(width: 38) // Locks structural boundaries to standard square icon proportions

            }
        }
        // .commands block has been cleanly extracted from here
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText], allowsMultipleSelection: false, onCompletion: loadFile)
        .fileExporter(isPresented: $showExporter, document: TextDocument(text: text), contentType: .plainText, defaultFilename: "Untitled", onCompletion: saveFinished)
        .alert("File Changed Externally", isPresented: $showAlertFileChanged) {
            Button("Reload from Disk", role: .destructive) { reloadCurrentFile() }
            Button("Keep Editor Version", role: .cancel) { rearmFileMonitor() }
        } message: {
            Text("This file has been modified by another program. Would you like to reload it?")
        }
    }
    
    private var searchBar: some View {
        HStack {
            TextField("Find", text: $findText).textFieldStyle(.roundedBorder)
            TextField("Replace", text: $replaceText).textFieldStyle(.roundedBorder)
            
            Toggle(isOn: $useRegex) {
                Text("Regex").font(.subheadline)
            }
            .toggleStyle(.checkbox)
            
            Button("Replace All", action: replaceAll).buttonStyle(.borderedProminent)
            Button("Hide") { showSearch = false }.buttonStyle(.borderless)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var statusBar: some View {
        HStack(spacing: 15) {
            Text("\(text.count) chars")
            Text("\(wordCount()) words")
            Text("Ln \(cursorLine), Col \(cursorColumn)")
            if currentFileURL != nil {
                Text("📁 Locked to Disk File").font(.caption2).foregroundColor(.green)
            }
            
            Spacer()
            
            // CUSTOM FONT-SIZE SLIDER CONTROL COMPONENT
            HStack(spacing: 5) {
                Image(systemName: "textformat.size.smaller")
                Slider(value: $fontSize, in: 9...24, step: 1)
                    .frame(width: 80)
                Image(systemName: "textformat.size.larger")
            }
            .padding(.trailing, 10)
            
            if isModified {
                Text("Modified").foregroundColor(.secondary).italic()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .font(.system(size: 11, design: .monospaced))
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func wordCount() -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
    
    private func replaceAll() {
        guard !findText.isEmpty else { return }
        if useRegex {
            if let regex = try? NSRegularExpression(pattern: findText, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replaceText)
            }
        } else {
            text = text.replacingOccurrences(of: findText, with: replaceText)
        }
    }
    
    private func loadFile(result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        setupFileTracking(url: url)
    }
    
    private func saveFinished(result: Result<URL, Error>) {
        if case .success(let url) = result {
            lastSavedText = text
            setupFileTracking(url: url)
        }
    }
    
    private func setupFileTracking(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        if let contents = try? String(contentsOf: url, encoding: .utf8) {
            text = contents
            lastSavedText = contents
            currentFileURL = url
            
            activeFileMonitor?.stop()
            activeFileMonitor = FileNotificationMonitor(url: url) {
                DispatchQueue.main.async {
                    self.showAlertFileChanged = true
                }
            }
            activeFileMonitor?.start()
        }
        url.stopAccessingSecurityScopedResource()
    }
    
    private func reloadCurrentFile() {
        guard let url = currentFileURL, url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let contents = try? String(contentsOf: url, encoding: .utf8) {
            text = contents
            lastSavedText = contents
        }
        rearmFileMonitor()
    }
    
    private func rearmFileMonitor() {
        activeFileMonitor?.start()
    }
}


import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Native Text View & Logic
struct NativeTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorLine: Int
    @Binding var cursorColumn: Int
    var theme: ThemeSetting
    var isLineWrapped: Bool
    var fontSize: CGFloat // Dynamic scaling variable binding
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        
        let textView = NSTextView()
        textView.isRichText = false
        textView.autoresizingMask = [.width, .height]
        textView.delegate = context.coordinator
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }
        
        // Dynamically scale structural font targets
        let targetFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != targetFont {
            textView.font = targetFont
        }
        
        if textView.string != text {
            textView.string = text
        }
        
        if isLineWrapped {
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width, .height]
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: nsView.bounds.width, height: CGFloat.infinity)
        } else {
            textView.isHorizontallyResizable = true
            textView.autoresizingMask = [.height]
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.infinity, height: CGFloat.infinity)
        }
        
        layoutManager.textContainerChangedGeometry(container)
        
        switch theme {
        case .light:
            textView.textColor = .textColor
            textView.backgroundColor = .textBackgroundColor
        case .dark:
            textView.textColor = .white
            textView.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
        case .system:
            textView.textColor = .textColor
            textView.backgroundColor = .textBackgroundColor
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextView
        private let brackets: [Character: Character] = ["(": ")", "{": "}", "[": "]", ")": "(", "}": "{", "]": "["]
        
        init(_ parent: NativeTextView) { self.parent = parent }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
            updateCursorAndHighlight(in: textView)
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updateCursorAndHighlight(in: textView)
        }
        
        // INTERCEPT RETURN KEY OPERATIONS FOR AUTOMATIC INDENTATION
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let selectedRange = textView.selectedRange()
                let content = textView.string as NSString
                
                // Identify start of the current row block
                let lineRange = content.lineRange(for: NSRange(location: selectedRange.location, length: 0))
                let currentLineStr = content.substring(with: lineRange)
                
                // Extract leading tab/space structures
                var indentation = ""
                for char in currentLineStr {
                    if char == " " || char == "\t" {
                        indentation.append(char)
                    } else {
                        break
                    }
                }
                
                // Manually inject structural breaks + matching preceding indent spaces
                if textView.shouldChangeText(in: selectedRange, replacementString: "\n" + indentation) {
                    textView.insertText("\n" + indentation, replacementRange: selectedRange)
                    textView.didChangeText()
                    return true // Intercepted successfully
                }
            }
            return false // Pass control down to standard operational systems
        }
        
        private func updateCursorAndHighlight(in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let content = textView.string
            
            let index = content.index(content.startIndex, offsetBy: selectedRange.location, limitedBy: content.endIndex) ?? content.startIndex
            let prefix = content[..<index]
            let lines = prefix.components(separatedBy: "\n")
            parent.cursorLine = lines.count
            parent.cursorColumn = (lines.last?.count ?? 0) + 1
            
            textView.textStorage?.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: content.count))
            
            let cursorLoc = selectedRange.location
            guard cursorLoc > 0 && cursorLoc <= content.count else { return }
            
            let absoluteIndex = content.index(content.startIndex, offsetBy: cursorLoc - 1)
            let charAtCursor = content[absoluteIndex]
            
            guard let targetPartner = brackets[charAtCursor] else { return }
            let isClosing = [")", "}", "]"].contains(charAtCursor)
            
            if let matchedIndex = findMatchingPair(in: content, from: cursorLoc - 1, target: targetPartner, isClosing: isClosing) {
                let currentHighlightColor = NSColor.systemOrange.withAlphaComponent(0.25)
                textView.textStorage?.addAttribute(.backgroundColor, value: currentHighlightColor, range: NSRange(location: cursorLoc - 1, length: 1))
                textView.textStorage?.addAttribute(.backgroundColor, value: currentHighlightColor, range: NSRange(location: matchedIndex, length: 1))
            }
        }
        
        private func findMatchingPair(in text: String, from startPos: Int, target: Character, isClosing: Bool) -> Int? {
            let nsString = text as NSString
            var depth = 0
            let step = isClosing ? -1 : 1
            var current = startPos + step
            let triggerChar = nsString.substring(with: NSRange(location: startPos, length: 1))
            
            while current >= 0 && current < nsString.length {
                let charStr = nsString.substring(with: NSRange(location: current, length: 1))
                if charStr == triggerChar {
                    depth += 1
                } else if charStr == String(target) {
                    if depth == 0 { return current }
                    depth -= 1
                }
                current += step
            }
            return nil
        }
    }
}

// MARK: - File System Monitor Layer
class FileNotificationMonitor {
    private let url: URL
    private let callback: () -> Void
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    
    init(url: URL, callback: @escaping () -> Void) {
        self.url = url
        self.callback = callback
    }
    
    func start() {
        stop()
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.global(qos: .background)
        )
        
        source?.setEventHandler { [weak self] in
            self?.stop()
            self?.callback()
        }
        
        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
        }
        source?.resume()
    }
    
    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
    
    deinit { stop() }
}

// MARK: - Structural UI Gutter Component
struct LineGutterView: View {
    let text: String
    var fontSize: CGFloat // Tracks font size to compute precise line heights
    
    var body: some View {
        let lineCount = max(1, text.components(separatedBy: "\n").count)
        let rowHeight = fontSize * 1.45
        
        // 1. Calculate how many digits are in the highest line number
        let maxDigits = String(lineCount).count
        
        // 2. Compute dynamic layout width based on font size and active digits
        let dynamicWidth = fontSize * CGFloat(maxDigits) * 0.7 + 16
        
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...lineCount, id: \.self) { line in
                Text("\(line)")
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(height: rowHeight, alignment: .trailing)
            }
            Spacer()
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .padding(.top, 2)
        .frame(width: max(40, dynamicWidth)) // Clamped to a minimum sensible width
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }
}

// MARK: - Disk Serialization Engine Document Map Object
struct TextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { self.text = "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: Data(text.utf8))
    }
}
#Preview {
    ContentView(showImporter: .constant(false), showExporter: .constant(false))
}

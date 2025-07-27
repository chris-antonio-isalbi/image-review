import Cocoa
import Foundation

// MARK: - Data Models
struct ImageFeedback: Codable {
    let filename: String
    let approved: String // "Yes" or "No"
    let reviewer: String?
    let comments: String?
    let timestamp: String?
    
    enum CodingKeys: String, CodingKey {
        case filename = "Image Name"
        case approved = "Approved"
        case reviewer = "Reviewer"
        case comments = "Comments"
        case timestamp = "Timestamp"
    }
}

struct ReviewData: Codable {
    let feedback: [ImageFeedback]
}

// MARK: - File Organization Service
class FileOrganizationService {
    
    enum OrganizationError: Error {
        case sourcePathNotFound
        case destinationCreationFailed
        case fileNotFound
        case moveOperationFailed
        case invalidJSON
        case permissionDenied
    }
    
    private let fileManager = FileManager.default
    
    func organizeFiles(jsonPath: String, sourceFolderPath: String) throws {
        // Read and parse JSON data
        guard let jsonData = fileManager.contents(atPath: jsonPath) else {
            throw OrganizationError.sourcePathNotFound
        }
        
        let feedbackData: [ImageFeedback]
        do {
            // Try to decode as array first, then as ReviewData wrapper
            if let directArray = try? JSONDecoder().decode([ImageFeedback].self, from: jsonData) {
                feedbackData = directArray
            } else {
                let reviewData = try JSONDecoder().decode(ReviewData.self, from: jsonData)
                feedbackData = reviewData.feedback
            }
        } catch {
            throw OrganizationError.invalidJSON
        }
        
        // Create organization folders
        let sourceURL = URL(fileURLWithPath: sourceFolderPath)
        let approvedURL = sourceURL.appendingPathComponent("Approved")
        let notApprovedURL = sourceURL.appendingPathComponent("Not Approved")
        let pendingURL = sourceURL.appendingPathComponent("Pending Review")
        
        try createDirectoryIfNeeded(at: approvedURL)
        try createDirectoryIfNeeded(at: notApprovedURL)
        try createDirectoryIfNeeded(at: pendingURL)
        
        // Process each file
        var movedCount = 0
        var errorCount = 0
        
        for feedback in feedbackData {
            do {
                try organizeFile(feedback: feedback, sourceURL: sourceURL, 
                               approvedURL: approvedURL, notApprovedURL: notApprovedURL)
                movedCount += 1
            } catch {
                print("Error organizing file \(feedback.filename): \(error)")
                errorCount += 1
            }
        }
        
        print("Organization complete: \(movedCount) files moved, \(errorCount) errors")
    }
    
    private func createDirectoryIfNeeded(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private func organizeFile(feedback: ImageFeedback, sourceURL: URL, 
                            approvedURL: URL, notApprovedURL: URL) throws {
        // Find the file in source directory (handle various extensions)
        let possibleExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic"]
        var sourceFileURL: URL?
        
        // First try exact filename
        let exactFileURL = sourceURL.appendingPathComponent(feedback.filename)
        if fileManager.fileExists(atPath: exactFileURL.path) {
            sourceFileURL = exactFileURL
        } else {
            // Try different extensions
            let baseFilename = (feedback.filename as NSString).deletingPathExtension
            for ext in possibleExtensions {
                let testURL = sourceURL.appendingPathComponent("\(baseFilename).\(ext)")
                if fileManager.fileExists(atPath: testURL.path) {
                    sourceFileURL = testURL
                    break
                }
            }
        }
        
        guard let sourceFile = sourceFileURL else {
            throw OrganizationError.fileNotFound
        }
        
        // Determine destination based on approval status
        let destinationFolder: URL
        switch feedback.approved.lowercased() {
        case "yes", "approved", "true":
            destinationFolder = approvedURL
        case "no", "not approved", "false", "rejected":
            destinationFolder = notApprovedURL
        default:
            // If no clear approval status, move to pending
            return
        }
        
        let destinationFile = destinationFolder.appendingPathComponent(sourceFile.lastPathComponent)
        
        // Move the file
        do {
            // If destination exists, create a unique name
            var finalDestination = destinationFile
            var counter = 1
            while fileManager.fileExists(atPath: finalDestination.path) {
                let filename = sourceFile.deletingPathExtension().lastPathComponent
                let ext = sourceFile.pathExtension
                finalDestination = destinationFolder.appendingPathComponent("\(filename)_\(counter).\(ext)")
                counter += 1
            }
            
            try fileManager.moveItem(at: sourceFile, to: finalDestination)
            print("Moved \(sourceFile.lastPathComponent) to \(destinationFolder.lastPathComponent)")
        } catch {
            throw OrganizationError.moveOperationFailed
        }
    }
}

// MARK: - Main Application
@main
class FileOrganizerApp: NSObject, NSApplicationDelegate {
    
    private var window: NSWindow?
    private let organizationService = FileOrganizationService()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupUI()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    private func setupUI() {
        // Create main window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window?.title = "File Organizer"
        window?.center()
        
        // Create main view
        let contentView = NSView(frame: window!.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window?.contentView = contentView
        
        setupControls(in: contentView)
        
        window?.makeKeyAndOrderFront(nil)
        
        // Activate the app
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupControls(in contentView: NSView) {
        let margin: CGFloat = 20
        let buttonHeight: CGFloat = 44
        let textFieldHeight: CGFloat = 24
        let spacing: CGFloat = 20
        
        var currentY = contentView.bounds.height - margin - 30
        
        // Title
        let titleLabel = NSTextField(labelWithString: "Image Review File Organizer")
        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        titleLabel.frame = NSRect(x: margin, y: currentY, width: contentView.bounds.width - 2*margin, height: 30)
        titleLabel.autoresizingMask = [.width]
        contentView.addSubview(titleLabel)
        currentY -= 50
        
        // Instructions
        let instructionText = """
        1. Select the JSON file exported from your image review web app
        2. Choose the folder containing the images to organize
        3. Click 'Organize Files' to sort images into Approved/Not Approved folders
        """
        let instructionLabel = NSTextField(wrappingLabelWithString: instructionText)
        instructionLabel.frame = NSRect(x: margin, y: currentY - 60, width: contentView.bounds.width - 2*margin, height: 60)
        instructionLabel.autoresizingMask = [.width]
        contentView.addSubview(instructionLabel)
        currentY -= 80
        
        // JSON file selection
        let jsonLabel = NSTextField(labelWithString: "JSON File:")
        jsonLabel.frame = NSRect(x: margin, y: currentY, width: 100, height: textFieldHeight)
        contentView.addSubview(jsonLabel)
        
        let jsonPathField = NSTextField()
        jsonPathField.frame = NSRect(x: margin + 100, y: currentY, width: 350, height: textFieldHeight)
        jsonPathField.autoresizingMask = [.width]
        jsonPathField.placeholderString = "Select JSON file..."
        contentView.addSubview(jsonPathField)
        
        let jsonBrowseButton = NSButton(title: "Browse", target: self, action: #selector(selectJSONFile(_:)))
        jsonBrowseButton.frame = NSRect(x: contentView.bounds.width - margin - 80, y: currentY, width: 80, height: textFieldHeight)
        jsonBrowseButton.autoresizingMask = [.minXMargin]
        jsonBrowseButton.identifier = NSUserInterfaceItemIdentifier("jsonPathField")
        contentView.addSubview(jsonBrowseButton)
        currentY -= (textFieldHeight + spacing)
        
        // Source folder selection
        let folderLabel = NSTextField(labelWithString: "Image Folder:")
        folderLabel.frame = NSRect(x: margin, y: currentY, width: 100, height: textFieldHeight)
        contentView.addSubview(folderLabel)
        
        let folderPathField = NSTextField()
        folderPathField.frame = NSRect(x: margin + 100, y: currentY, width: 350, height: textFieldHeight)
        folderPathField.autoresizingMask = [.width]
        folderPathField.placeholderString = "Select folder containing images..."
        contentView.addSubview(folderPathField)
        
        let folderBrowseButton = NSButton(title: "Browse", target: self, action: #selector(selectImageFolder(_:)))
        folderBrowseButton.frame = NSRect(x: contentView.bounds.width - margin - 80, y: currentY, width: 80, height: textFieldHeight)
        folderBrowseButton.autoresizingMask = [.minXMargin]
        folderBrowseButton.identifier = NSUserInterfaceItemIdentifier("folderPathField")
        contentView.addSubview(folderBrowseButton)
        currentY -= (textFieldHeight + spacing * 2)
        
        // Organize button
        let organizeButton = NSButton(title: "Organize Files", target: self, action: #selector(organizeFiles(_:)))
        organizeButton.frame = NSRect(x: (contentView.bounds.width - 200) / 2, y: currentY, width: 200, height: buttonHeight)
        organizeButton.autoresizingMask = [.minXMargin, .maxXMargin]
        organizeButton.bezelStyle = .rounded
        organizeButton.keyEquivalent = "\r"
        contentView.addSubview(organizeButton)
        currentY -= (buttonHeight + spacing)
        
        // Status text view
        let scrollView = NSScrollView()
        scrollView.frame = NSRect(x: margin, y: margin, width: contentView.bounds.width - 2*margin, height: currentY - margin)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        
        let statusTextView = NSTextView()
        statusTextView.isEditable = false
        statusTextView.isSelectable = true
        statusTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        statusTextView.string = "Ready to organize files...\n"
        
        scrollView.documentView = statusTextView
        contentView.addSubview(scrollView)
        
        // Store references for later use
        jsonPathField.identifier = NSUserInterfaceItemIdentifier("jsonPath")
        folderPathField.identifier = NSUserInterfaceItemIdentifier("folderPath")
        statusTextView.identifier = NSUserInterfaceItemIdentifier("statusText")
    }
    
    @objc private func selectJSONFile(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.begin { response in
            if response == .OK {
                if let url = openPanel.url {
                    if let jsonPathField = self.window?.contentView?.findSubview(ofType: NSTextField.self, withIdentifier: "jsonPath") {
                        jsonPathField.stringValue = url.path
                    }
                }
            }
        }
    }
    
    @objc private func selectImageFolder(_ sender: NSButton) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        
        openPanel.begin { response in
            if response == .OK {
                if let url = openPanel.url {
                    if let folderPathField = self.window?.contentView?.findSubview(ofType: NSTextField.self, withIdentifier: "folderPath") {
                        folderPathField.stringValue = url.path
                    }
                }
            }
        }
    }
    
    @objc private func organizeFiles(_ sender: NSButton) {
        guard let contentView = window?.contentView,
              let jsonPathField = contentView.findSubview(ofType: NSTextField.self, withIdentifier: "jsonPath"),
              let folderPathField = contentView.findSubview(ofType: NSTextField.self, withIdentifier: "folderPath"),
              let statusTextView = contentView.findSubview(ofType: NSTextView.self, withIdentifier: "statusText") else {
            return
        }
        
        let jsonPath = jsonPathField.stringValue
        let folderPath = folderPathField.stringValue
        
        guard !jsonPath.isEmpty && !folderPath.isEmpty else {
            updateStatus("Please select both JSON file and image folder.", in: statusTextView)
            return
        }
        
        updateStatus("Starting file organization...\n", in: statusTextView)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.organizationService.organizeFiles(jsonPath: jsonPath, sourceFolderPath: folderPath)
                DispatchQueue.main.async {
                    self.updateStatus("✅ File organization completed successfully!\n", in: statusTextView)
                }
            } catch {
                DispatchQueue.main.async {
                    self.updateStatus("❌ Error: \(error.localizedDescription)\n", in: statusTextView)
                }
            }
        }
    }
    
    private func updateStatus(_ message: String, in textView: NSTextView) {
        textView.string += message
        textView.scrollToEndOfDocument(nil)
    }
}

// Helper extension to fix the view finding issue
extension NSView {
    func findSubview<T: NSView>(ofType type: T.Type, withIdentifier identifier: String) -> T? {
        for subview in subviews {
            if let matchingView = subview as? T, subview.identifier?.rawValue == identifier {
                return matchingView
            }
            if let found = subview.findSubview(ofType: type, withIdentifier: identifier) {
                return found
            }
        }
        return nil
    }
}
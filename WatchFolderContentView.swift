import SwiftUI
import Foundation
import AppKit
import Swifter

// MARK: - Data Models
struct ImageFeedback: Codable {
    let imageName: String
    let approved: String
    let status: String
    let reviewer: String?
    let comments: String?
    let timestamp: String?
    let folderName: String?
    let productCode: String?
    let productName: String?
    let imageVersion: Int?
    let attachments: String?
}

// MARK: - Folder Watcher
class FolderWatcher: ObservableObject {
    @Published var isWatching = false
    @Published var watchedFolder = ""
    @Published var pendingProcessing: [PendingJob] = []
    
    private var monitor: DispatchSourceFileSystemObject?
    private let fileManager = FileManager.default
    
    struct PendingJob: Identifiable, Equatable {
        let id = UUID()
        let jsonPath: String
        let fileName: String
        let detectedAt: Date
        let approvedCount: Int
        let rejectedCount: Int
        
        var timeAgo: String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: detectedAt, relativeTo: Date())
        }
    }
    
    func startWatching(folder: String) {
        stopWatching()
        
        guard fileManager.fileExists(atPath: folder) else { 
            print("Folder does not exist: \(folder)")
            return 
        }
        
        watchedFolder = folder
        isWatching = true
        
        let folderURL = URL(fileURLWithPath: folder)
        let descriptor = open(folderURL.path, O_EVTONLY)
        
        guard descriptor >= 0 else {
            print("Failed to open folder for monitoring")
            isWatching = false
            return
        }
        
        monitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        
        monitor?.setEventHandler { [weak self] in
            self?.checkForNewJSONFiles()
        }
        
        monitor?.setCancelHandler {
            close(descriptor)
        }
        
        monitor?.resume()
        
        // Initial check for existing files
        checkForNewJSONFiles()
    }
    
    func stopWatching() {
        monitor?.cancel()
        monitor = nil
        isWatching = false
        watchedFolder = ""
    }
    
    private func checkForNewJSONFiles() {
        guard !watchedFolder.isEmpty else { return }
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: watchedFolder)
            let jsonFiles = contents.filter { $0.hasSuffix(".json") }
            
            for jsonFile in jsonFiles {
                let fullPath = (watchedFolder as NSString).appendingPathComponent(jsonFile)
                
                // Check if we already have this file pending
                if pendingProcessing.contains(where: { $0.jsonPath == fullPath }) {
                    continue
                }
                
                // Analyze the JSON file
                if let job = analyzeJSONFile(path: fullPath, fileName: jsonFile) {
                    DispatchQueue.main.async {
                        self.pendingProcessing.append(job)
                    }
                }
            }
        } catch {
            print("Error checking folder: \(error)")
        }
    }
    
    private func analyzeJSONFile(path: String, fileName: String) -> PendingJob? {
        guard let jsonData = fileManager.contents(atPath: path) else { return nil }
        
        do {
            let feedbackData = try JSONDecoder().decode([ImageFeedback].self, from: jsonData)
            
            let approvedCount = feedbackData.filter { feedback in
                feedback.approved.lowercased() == "yes" || feedback.status.lowercased() == "approved"
            }.count
            
            let rejectedCount = feedbackData.filter { feedback in
                feedback.approved.lowercased() == "no" || 
                feedback.status.lowercased() == "rejected" ||
                feedback.status.lowercased() == "not approved"
            }.count
            
            return PendingJob(
                jsonPath: path,
                fileName: fileName,
                detectedAt: Date(),
                approvedCount: approvedCount,
                rejectedCount: rejectedCount
            )
        } catch {
            print("Error analyzing JSON: \(error)")
            return nil
        }
    }
    
    func removePendingJob(_ job: PendingJob) {
        pendingProcessing.removeAll { $0.id == job.id }
    }
}

// MARK: - File Organization Service
class FileOrganizationService: ObservableObject {
    
    enum OrganizationError: Error, LocalizedError {
        case sourcePathNotFound
        case fileNotFound
        case moveOperationFailed
        case invalidJSON
        
        var errorDescription: String? {
            switch self {
            case .sourcePathNotFound: return "JSON file not found"
            case .fileNotFound: return "Image file not found"
            case .moveOperationFailed: return "Failed to move file"
            case .invalidJSON: return "Invalid JSON format"
            }
        }
    }
    
    @Published var statusMessage = "Ready to organize files..."
    @Published var isProcessing = false
    
    private let fileManager = FileManager.default
    
    @MainActor
    func organizeFiles(jsonPath: String, sourceFolderPath: String) {
        isProcessing = true
        statusMessage = "Starting file organization...\n"
        
        Task {
            await performOrganization(jsonPath: jsonPath, sourceFolderPath: sourceFolderPath)
        }
    }
    
    private func performOrganization(jsonPath: String, sourceFolderPath: String) async {
        do {
            // Read and parse JSON data
            guard let jsonData = fileManager.contents(atPath: jsonPath) else {
                await updateStatus("❌ Error: JSON file not found\n", isProcessing: false)
                return
            }
            
            let feedbackData: [ImageFeedback]
            do {
                feedbackData = try JSONDecoder().decode([ImageFeedback].self, from: jsonData)
            } catch {
                await updateStatus("❌ Error: Invalid JSON format\n", isProcessing: false)
                return
            }
            
            // Create organization folders
            let sourceURL = URL(fileURLWithPath: sourceFolderPath)
            let approvedURL = sourceURL.appendingPathComponent("Approved")
            let notApprovedURL = sourceURL.appendingPathComponent("Not Approved")
            
            do {
                try createDirectoryIfNeeded(at: approvedURL)
                try createDirectoryIfNeeded(at: notApprovedURL)
            } catch {
                await updateStatus("❌ Error: Failed to create directories\n", isProcessing: false)
                return
            }
            
            // Process each file
            var movedCount = 0
            var errorCount = 0
            
            for feedback in feedbackData {
                do {
                    try organizeFile(feedback: feedback, sourceURL: sourceURL,
                                   approvedURL: approvedURL, notApprovedURL: notApprovedURL)
                    movedCount += 1
                    await updateStatus("Moved \(feedback.imageName)\n")
                } catch {
                    errorCount += 1
                    await updateStatus("Error with \(feedback.imageName): \(error.localizedDescription)\n")
                }
            }
            
            await updateStatus("✅ Organization complete: \(movedCount) files moved, \(errorCount) errors\n", isProcessing: false)
            
        } catch {
            await updateStatus("❌ Unexpected error: \(error.localizedDescription)\n", isProcessing: false)
        }
    }
    
    @MainActor
    private func updateStatus(_ message: String, isProcessing: Bool? = nil) {
        statusMessage += message
        if let processing = isProcessing {
            self.isProcessing = processing
        }
    }
    
    private func createDirectoryIfNeeded(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    private func organizeFile(feedback: ImageFeedback, sourceURL: URL,
                            approvedURL: URL, notApprovedURL: URL) throws {
        // Find the file in source directory
        let possibleExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic"]
        var sourceFileURL: URL?
        
        // First try exact filename
        let exactFileURL = sourceURL.appendingPathComponent(feedback.imageName)
        if fileManager.fileExists(atPath: exactFileURL.path) {
            sourceFileURL = exactFileURL
        } else {
            // Try different extensions
            let baseFilename = (feedback.imageName as NSString).deletingPathExtension
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
        
        let isApproved = feedback.approved.lowercased() == "yes" ||
                        feedback.status.lowercased() == "approved"
        let isRejected = feedback.approved.lowercased() == "no" ||
                        feedback.status.lowercased() == "rejected" ||
                        feedback.status.lowercased() == "not approved"
        
        if isApproved {
            destinationFolder = approvedURL
        } else if isRejected {
            destinationFolder = notApprovedURL
        } else {
            return // Skip unclear status
        }
        
        let destinationFile = destinationFolder.appendingPathComponent(sourceFile.lastPathComponent)
        
        // Move the file
        do {
            var finalDestination = destinationFile
            var counter = 1
            while fileManager.fileExists(atPath: finalDestination.path) {
                let filename = sourceFile.deletingPathExtension().lastPathComponent
                let ext = sourceFile.pathExtension
                finalDestination = destinationFolder.appendingPathComponent("\(filename)_\(counter).\(ext)")
                counter += 1
            }
            
            try fileManager.moveItem(at: sourceFile, to: finalDestination)
        } catch {
            throw OrganizationError.moveOperationFailed
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @StateObject private var organizationService = FileOrganizationService()
    @StateObject private var folderWatcher = FolderWatcher()
    @StateObject private var httpServer = HTTPServer()
    @State private var jsonFilePath = ""
    @State private var imageFolderPath = ""
    @State private var showingProcessConfirmation = false
    @State private var jobToProcess: FolderWatcher.PendingJob?
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Image Review File Organizer")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            // HTTP Server Section
            GroupBox("🌐 Web App Integration") {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("HTTP Server Status:")
                                .font(.headline)
                            Text(httpServer.serverStatus)
                                .font(.caption)
                                .foregroundColor(httpServer.isServerRunning ? .green : .secondary)
                        }
                        
                        Spacer()
                        
                        if httpServer.isServerRunning {
                            Button("Stop Server") {
                                httpServer.stopServer()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Start Server") {
                                httpServer.startServer()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    if httpServer.isServerRunning {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Available endpoints:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("• GET http://localhost:8080/status")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("• POST http://localhost:8080/scan-files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("• POST http://localhost:8080/sort-files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("• POST http://localhost:8080/move-files")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal)
            
            // Watch Folder Section
            GroupBox("🔍 Auto-Watch Folder") {
                VStack(spacing: 10) {
                    HStack {
                        Text("Watch Folder:")
                            .frame(width: 100, alignment: .leading)
                        
                        TextField("Select folder to monitor...", text: $folderWatcher.watchedFolder)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(true)
                        
                        Button("Browse") {
                            selectWatchFolder()
                        }
                        .buttonStyle(.bordered)
                        
                        if folderWatcher.isWatching {
                            Button("Stop Watching") {
                                folderWatcher.stopWatching()
                            }
                            .buttonStyle(.bordered)
                        } else if !folderWatcher.watchedFolder.isEmpty {
                            Button("Start Watching") {
                                folderWatcher.startWatching(folder: folderWatcher.watchedFolder)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    if folderWatcher.isWatching {
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.green)
                            Text("Watching for new JSON files...")
                                .font(.caption)
                                .foregroundColor(.green)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            // Pending Processing Section
            if !folderWatcher.pendingProcessing.isEmpty {
                GroupBox("📋 Processing Available") {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(folderWatcher.pendingProcessing) { job in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(job.fileName)
                                            .font(.headline)
                                        HStack {
                                            Label("\(job.approvedCount)", systemImage: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Label("\(job.rejectedCount)", systemImage: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                            Spacer()
                                            Text("detected \(job.timeAgo)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Process") {
                                        jobToProcess = job
                                        showingProcessConfirmation = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    
                                    Button("Dismiss") {
                                        folderWatcher.removePendingJob(job)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .padding(.horizontal)
            }
            
            // Manual Processing Section
            GroupBox("📁 Manual Processing") {
                VStack(spacing: 15) {
                    // JSON file selection
                    HStack {
                        Text("JSON File:")
                            .frame(width: 100, alignment: .leading)
                        
                        TextField("Select JSON file...", text: $jsonFilePath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(true)
                        
                        Button("Browse") {
                            selectJSONFile()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Image folder selection
                    HStack {
                        Text("Image Folder:")
                            .frame(width: 100, alignment: .leading)
                        
                        TextField("Select folder containing images...", text: $imageFolderPath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(true)
                        
                        Button("Browse") {
                            selectImageFolder()
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Organize button
                    Button("Organize Files") {
                        guard !jsonFilePath.isEmpty && !imageFolderPath.isEmpty else { return }
                        organizationService.organizeFiles(jsonPath: jsonFilePath, sourceFolderPath: imageFolderPath)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(jsonFilePath.isEmpty || imageFolderPath.isEmpty || organizationService.isProcessing)
                }
            }
            .padding(.horizontal)
            
            // Status area
            GroupBox("📊 Status") {
                ScrollView {
                    Text(organizationService.statusMessage)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(height: 120)
                
                if organizationService.isProcessing {
                    ProgressView("Processing...")
                        .padding()
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .frame(minWidth: 700, minHeight: 600)
        .alert("Process Images?", isPresented: $showingProcessConfirmation) {
            Button("Cancel", role: .cancel) {
                jobToProcess = nil
            }
            Button("Process") {
                if let job = jobToProcess {
                    processJob(job)
                    jobToProcess = nil
                }
            }
        } message: {
            if let job = jobToProcess {
                Text("Process \(job.fileName)?\n\n✅ \(job.approvedCount) approved images\n❌ \(job.rejectedCount) rejected images\n\nImages will be organized into Approved/Not Approved folders.")
            }
        }
    }
    
    // MARK: - Helper Functions
    private func selectWatchFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Select Watch Folder"
        panel.message = "Choose the folder to monitor for new JSON exports"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                folderWatcher.watchedFolder = url.path
                // Also add to HTTP server's watched directories
                httpServer.addWatchDirectory(url.path)
            }
        }
    }
    
    private func selectJSONFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Select JSON Export File"
        panel.message = "Choose the JSON file exported from your image review app"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                jsonFilePath = url.path
            }
        }
    }
    
    private func selectImageFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Select Image Folder"
        panel.message = "Choose the folder containing your images to organize"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                imageFolderPath = url.path
                // Add this folder to HTTP server's watched directories
                httpServer.addWatchDirectory(url.path)
            }
        }
    }
    
    private func processJob(_ job: FolderWatcher.PendingJob) {
        if imageFolderPath.isEmpty {
            // If no image folder is set, ask user to select one
            selectImageFolder()
            guard !imageFolderPath.isEmpty else { return }
        }
        
        organizationService.organizeFiles(jsonPath: job.jsonPath, sourceFolderPath: imageFolderPath)
        folderWatcher.removePendingJob(job)
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
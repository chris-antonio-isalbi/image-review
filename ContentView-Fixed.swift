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

// MARK: - HTTP Server for Web App Integration
class HTTPServer: ObservableObject {
    @Published var isServerRunning = false
    @Published var serverStatus = "Stopped"
    
    private var server: HttpServer?
    private let port: UInt16 = 8080
    private var watchedDirectories: [String] = []
    private let fileManager = FileManager.default
    
    // MARK: - Server Control
    func startServer() {
        guard server == nil else { return }
        
        server = HttpServer()
        setupRoutes()
        
        do {
            try server?.start(port, forceIPv4: true)
            DispatchQueue.main.async {
                self.isServerRunning = true
                self.serverStatus = "Running on localhost:\(self.port)"
            }
            print("✅ HTTP Server started on localhost:\(port)")
        } catch {
            DispatchQueue.main.async {
                self.serverStatus = "Failed to start: \(error.localizedDescription)"
            }
            print("❌ Failed to start server: \(error)")
        }
    }
    
    func stopServer() {
        server?.stop()
        server = nil
        DispatchQueue.main.async {
            self.isServerRunning = false
            self.serverStatus = "Stopped"
        }
        print("🛑 HTTP Server stopped")
    }
    
    func addWatchDirectory(_ path: String) {
        if !watchedDirectories.contains(path) {
            watchedDirectories.append(path)
        }
    }
    
    // MARK: - Route Setup
    private func setupRoutes() {
        // CORS preflight handling
        server?[.OPTIONS, "/**"] = { request in
            return HttpResponse.ok(.text("OK")).withCORSHeaders()
        }
        
        // GET /status - Server status endpoint
        server?[.GET, "/status"] = { [weak self] request in
            return self?.handleStatus() ?? HttpResponse.internalServerError
        }
        
        // POST /scan-files - File scanning endpoint
        server?[.POST, "/scan-files"] = { [weak self] request in
            return self?.handleScanFiles(request) ?? HttpResponse.internalServerError
        }
        
        // POST /sort-files - Sort files into subdirectories
        server?[.POST, "/sort-files"] = { [weak self] request in
            return self?.handleSortFiles(request) ?? HttpResponse.internalServerError
        }
        
        // POST /move-files - Move files to absolute paths
        server?[.POST, "/move-files"] = { [weak self] request in
            return self?.handleMoveFiles(request) ?? HttpResponse.internalServerError
        }
    }
    
    // MARK: - Endpoint Handlers
    private func handleStatus() -> HttpResponse {
        let statusData: [String: Any] = [
            "status": "running",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "watchedDirectories": watchedDirectories
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: statusData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return HttpResponse.internalServerError
        }
        
        return HttpResponse.ok(.text(jsonString)).withCORSHeaders()
    }
    
    private func handleScanFiles(_ request: HttpRequest) -> HttpResponse {
        // Parse incoming JSON
        guard let bodyData = Data(request.body),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let supabaseImagesArray = json["supabaseImages"] as? [[String: Any]] else {
            return HttpResponse.badRequest(.text("Invalid JSON format")).withCORSHeaders()
        }
        
        // Convert to our ImageFeedback format
        var supabaseImages: [ImageFeedback] = []
        for imageData in supabaseImagesArray {
            if let imageName = imageData["Image Name"] as? String,
               let approved = imageData["Approved"] as? String {
                let feedback = ImageFeedback(
                    imageName: imageName,
                    approved: approved,
                    status: approved == "Yes" ? "Approved" : "Not Approved",
                    reviewer: imageData["Reviewer"] as? String,
                    comments: imageData["Comments"] as? String,
                    timestamp: imageData["Timestamp"] as? String,
                    folderName: imageData["Folder"] as? String,
                    productCode: nil,
                    productName: nil,
                    imageVersion: nil,
                    attachments: nil
                )
                supabaseImages.append(feedback)
            }
        }
        
        // Scan local directories
        let localFiles = scanLocalDirectories()
        
        // Compare and create matches
        let comparisonResult = compareFilesWithDatabase(localFiles: localFiles, supabaseImages: supabaseImages)
        
        // Format response
        let responseData: [String: Any] = [
            "localFiles": localFiles,
            "supabaseImages": supabaseImages.map { $0.imageName },
            "matches": comparisonResult.matches.map { match in
                [
                    "fileName": match.fileName,
                    "localPath": match.localPath,
                    "supabaseRecord": [
                        "imageName": match.supabaseRecord.imageName,
                        "approved": match.supabaseRecord.approved,
                        "status": match.supabaseRecord.status
                    ],
                    "status": match.status
                ]
            },
            "missing": [
                "inLocal": comparisonResult.missingInLocal,
                "inSupabase": comparisonResult.missingInSupabase
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: responseData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return HttpResponse.internalServerError
        }
        
        return HttpResponse.ok(.text(jsonString)).withCORSHeaders()
    }
    
    private func handleSortFiles(_ request: HttpRequest) -> HttpResponse {
        guard let bodyData = Data(request.body),
              let instructions = try? JSONDecoder().decode([SortInstruction].self, from: bodyData) else {
            return HttpResponse.badRequest(.text("Invalid JSON format")).withCORSHeaders()
        }
        
        var processed = 0
        var successful = 0
        var errors = 0
        
        for instruction in instructions {
            processed += 1
            
            do {
                try sortFile(instruction: instruction)
                successful += 1
            } catch {
                errors += 1
                print("Error sorting file \(instruction.fileName): \(error)")
            }
        }
        
        let response: [String: Any] = [
            "success": errors == 0,
            "processed": processed,
            "successful": successful,
            "errors": errors
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return HttpResponse.internalServerError
        }
        
        return HttpResponse.ok(.text(jsonString)).withCORSHeaders()
    }
    
    private func handleMoveFiles(_ request: HttpRequest) -> HttpResponse {
        guard let bodyData = Data(request.body),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let filesArray = json["files"] as? [[String: Any]] else {
            return HttpResponse.badRequest(.text("Invalid JSON format")).withCORSHeaders()
        }
        
        var processed = 0
        var successful = 0
        var errors = 0
        
        for fileData in filesArray {
            guard let fileName = fileData["fileName"] as? String,
                  let fromPath = fileData["fromPath"] as? String,
                  let toPath = fileData["toPath"] as? String else {
                continue
            }
            
            processed += 1
            
            do {
                try moveFile(fileName: fileName, fromPath: fromPath, toPath: toPath)
                successful += 1
            } catch {
                errors += 1
                print("Error moving file \(fileName): \(error)")
            }
        }
        
        let response: [String: Any] = [
            "success": errors == 0,
            "processed": processed,
            "successful": successful,
            "errors": errors
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return HttpResponse.internalServerError
        }
        
        return HttpResponse.ok(.text(jsonString)).withCORSHeaders()
    }
    
    // MARK: - File Operations
    private func scanLocalDirectories() -> [String] {
        var allFiles: [String] = []
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        
        for directory in watchedDirectories {
            let files = scanDirectory(path: directory, extensions: imageExtensions)
            allFiles.append(contentsOf: files)
        }
        
        return allFiles
    }
    
    private func scanDirectory(path: String, extensions: [String]) -> [String] {
        var files: [String] = []
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return files
        }
        
        while let fileName = enumerator.nextObject() as? String {
            let fileExtension = (fileName as NSString).pathExtension.lowercased()
            if extensions.contains(fileExtension) {
                files.append(fileName)
            }
        }
        
        return files
    }
    
    private func compareFilesWithDatabase(localFiles: [String], supabaseImages: [ImageFeedback]) -> ComparisonResult {
        var matches: [FileMatch] = []
        var missingInLocal: [String] = []
        var missingInSupabase: [String] = []
        
        // Find matches
        for supabaseImage in supabaseImages {
            if let localFile = localFiles.first(where: { file in
                let localFileName = (file as NSString).lastPathComponent
                let baseName = (localFileName as NSString).deletingPathExtension
                let supabaseBaseName = (supabaseImage.imageName as NSString).deletingPathExtension
                return baseName == supabaseBaseName || localFileName == supabaseImage.imageName
            }) {
                let status: String
                switch supabaseImage.approved.lowercased() {
                case "yes": status = "approved"
                case "no": status = "not_approved"
                default: status = "pending"
                }
                
                matches.append(FileMatch(
                    fileName: supabaseImage.imageName,
                    localPath: localFile,
                    supabaseRecord: supabaseImage,
                    status: status
                ))
            } else {
                missingInLocal.append(supabaseImage.imageName)
            }
        }
        
        // Find files that exist locally but not in database
        let matchedLocalFiles = Set(matches.map { $0.localPath })
        missingInSupabase = localFiles.filter { !matchedLocalFiles.contains($0) }
        
        return ComparisonResult(
            matches: matches,
            missingInLocal: missingInLocal,
            missingInSupabase: missingInSupabase
        )
    }
    
    private func sortFile(instruction: SortInstruction) throws {
        let sourceURL = URL(fileURLWithPath: instruction.currentPath)
        let parentDirectory = sourceURL.deletingLastPathComponent()
        let targetDirectory = parentDirectory.appendingPathComponent(instruction.targetFolder)
        
        // Create target directory if it doesn't exist
        if !fileManager.fileExists(atPath: targetDirectory.path) {
            try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        }
        
        let destinationURL = targetDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        
        // Handle duplicate names
        var finalDestination = destinationURL
        var counter = 1
        while fileManager.fileExists(atPath: finalDestination.path) {
            let filename = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            finalDestination = targetDirectory.appendingPathComponent("\(filename)_\(counter).\(ext)")
            counter += 1
        }
        
        try fileManager.moveItem(at: sourceURL, to: finalDestination)
    }
    
    private func moveFile(fileName: String, fromPath: String, toPath: String) throws {
        let sourceURL = URL(fileURLWithPath: fromPath)
        let destinationURL = URL(fileURLWithPath: toPath)
        
        // Create destination directory if it doesn't exist
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }
        
        // Handle duplicate names
        var finalDestination = destinationURL
        var counter = 1
        while fileManager.fileExists(atPath: finalDestination.path) {
            let filename = destinationURL.deletingPathExtension().lastPathComponent
            let ext = destinationURL.pathExtension
            finalDestination = destinationDirectory.appendingPathComponent("\(filename)_\(counter).\(ext)")
            counter += 1
        }
        
        try fileManager.moveItem(at: sourceURL, to: finalDestination)
    }
}

// MARK: - Data Models for HTTP API
struct SortInstruction: Codable {
    let fileName: String
    let currentPath: String
    let targetFolder: String
}

struct FileMatch {
    let fileName: String
    let localPath: String
    let supabaseRecord: ImageFeedback
    let status: String
}

struct ComparisonResult {
    let matches: [FileMatch]
    let missingInLocal: [String]
    let missingInSupabase: [String]
}

// MARK: - HTTP Response Extensions
extension HttpResponse {
    func withCORSHeaders() -> HttpResponse {
        var response = self
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        response.headers["Content-Type"] = "application/json"
        return response
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
                httpServer.addWatchDirectory(url.path)
            }
        }
    }
    
    private func processJob(_ job: FolderWatcher.PendingJob) {
        if imageFolderPath.isEmpty {
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
import Foundation
import Swifter

// HTTP Server for connecting your web app to the native app
class WebAppHTTPServer: ObservableObject {
    @Published var isServerRunning = false
    @Published var serverStatus = "Stopped"
    
    private var server: HttpServer?
    private let port: UInt16 = 8080
    private var watchedDirectories: [String] = []
    private let fileManager = FileManager.default
    
    // Start the HTTP server
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
    
    // Stop the HTTP server
    func stopServer() {
        server?.stop()
        server = nil
        DispatchQueue.main.async {
            self.isServerRunning = false
            self.serverStatus = "Stopped"
        }
        print("🛑 HTTP Server stopped")
    }
    
    // Add a folder for the server to watch
    func addWatchDirectory(_ path: String) {
        if !watchedDirectories.contains(path) {
            watchedDirectories.append(path)
        }
    }
    
    // Set up the server routes (the endpoints your web app can call)
    private func setupRoutes() {
        // Handle CORS (allows web browser to connect)
        server?[.OPTIONS, "/**"] = { request in
            return HttpResponse.ok(.text("OK")).withCORSHeaders()
        }
        
        // GET /status - Check if server is running
        server?[.GET, "/status"] = { [weak self] request in
            return self?.handleStatus() ?? HttpResponse.internalServerError
        }
        
        // POST /scan-files - Compare web app data with local files
        server?[.POST, "/scan-files"] = { [weak self] request in
            return self?.handleScanFiles(request) ?? HttpResponse.internalServerError
        }
        
        // POST /sort-files - Organize files into folders
        server?[.POST, "/sort-files"] = { [weak self] request in
            return self?.handleSortFiles(request) ?? HttpResponse.internalServerError
        }
    }
    
    // Handle status requests
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
    
    // Handle file scanning requests from web app
    private func handleScanFiles(_ request: HttpRequest) -> HttpResponse {
        guard let bodyData = Data(request.body),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let supabaseImagesArray = json["supabaseImages"] as? [[String: Any]] else {
            return HttpResponse.badRequest(.text("Invalid JSON format")).withCORSHeaders()
        }
        
        // Convert web app data to our format
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
        
        // Scan local directories for files
        let localFiles = scanLocalDirectories()
        
        // Compare web app data with local files
        let comparisonResult = compareFilesWithDatabase(localFiles: localFiles, supabaseImages: supabaseImages)
        
        // Create response
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
    
    // Handle file sorting requests
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
    
    // Scan local directories for image files
    private func scanLocalDirectories() -> [String] {
        var allFiles: [String] = []
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        
        for directory in watchedDirectories {
            let files = scanDirectory(path: directory, extensions: imageExtensions)
            allFiles.append(contentsOf: files)
        }
        
        return allFiles
    }
    
    // Scan a single directory
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
    
    // Compare local files with web app data
    private func compareFilesWithDatabase(localFiles: [String], supabaseImages: [ImageFeedback]) -> ComparisonResult {
        var matches: [FileMatch] = []
        var missingInLocal: [String] = []
        var missingInSupabase: [String] = []
        
        // Find matches between web app data and local files
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
        
        // Find local files not in web app data
        let matchedLocalFiles = Set(matches.map { $0.localPath })
        missingInSupabase = localFiles.filter { !matchedLocalFiles.contains($0) }
        
        return ComparisonResult(
            matches: matches,
            missingInLocal: missingInLocal,
            missingInSupabase: missingInSupabase
        )
    }
    
    // Sort a single file into the appropriate folder
    private func sortFile(instruction: SortInstruction) throws {
        let sourceURL = URL(fileURLWithPath: instruction.currentPath)
        let parentDirectory = sourceURL.deletingLastPathComponent()
        let targetDirectory = parentDirectory.appendingPathComponent(instruction.targetFolder)
        
        // Create target directory if it doesn't exist
        if !fileManager.fileExists(atPath: targetDirectory.path) {
            try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        }
        
        let destinationURL = targetDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        
        // Handle duplicate file names
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
}

// Data structures for the HTTP API
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

// Add CORS headers to HTTP responses
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
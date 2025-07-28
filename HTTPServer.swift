import Foundation
import Network

class WebAppHTTPServer: ObservableObject {
    @Published var isServerRunning = false
    @Published var serverStatus = "Stopped"
    
    private var listener: NWListener?
    @Published var watchedDirectories: [String] = []
    private let port: UInt16 = 8080
    private let fileManager = FileManager.default
    
    func startServer() {
        print("🚀 Starting HTTP server...")
        
        guard listener == nil else {
            print("❌ Server already running")
            return
        }
        
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: DispatchQueue.global())
            
            DispatchQueue.main.async {
                self.isServerRunning = true
                self.serverStatus = "Running on localhost:\(self.port)"
            }
            
            print("✅ Server started on port \(port)")
            
        } catch {
            print("❌ Failed to start server: \(error)")
            DispatchQueue.main.async {
                self.serverStatus = "Failed to start: \(error.localizedDescription)"
            }
        }
    }
    
    func stopServer() {
        print("🛑 Stopping HTTP server...")
        listener?.cancel()
        listener = nil
        
        DispatchQueue.main.async {
            self.isServerRunning = false
            self.serverStatus = "Stopped"
        }
        
        print("✅ Server stopped")
    }
    
    func addWatchDirectory(_ path: String) {
        if !watchedDirectories.contains(path) {
            watchedDirectories.append(path)
            print("📁 Added watch directory: \(path)")
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                let request = String(data: data, encoding: .utf8) ?? ""
                print("📨 Received request: \(request.prefix(200))...")
                
                let response: String
                
                // Check if this is an image request (binary response needed)
                if request.contains("GET /images/") || request.contains("GET /thumbnails/") {
                    response = self?.processRequest(request) ?? self?.createErrorResponse("Server error") ?? "HTTP/1.1 500 Internal Server Error\r\n\r\n"
                } else {
                    response = self?.processRequest(request) ?? self?.createErrorResponse("Server error") ?? "HTTP/1.1 500 Internal Server Error\r\n\r\n"
                }
                
                let responseData = response.data(using: .utf8) ?? Data()
                
                connection.send(content: responseData, completion: .contentProcessed { error in
                    if let error = error {
                        print("❌ Send error: \(error)")
                    }
                    connection.cancel()
                })
            }
            
            if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func processRequest(_ request: String) -> String {
        print("🔍 Processing request...")
        
        // Handle CORS preflight
        if request.hasPrefix("OPTIONS") {
            return createCORSResponse()
        }
        
        // Parse the request line
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return createErrorResponse("Invalid request")
        }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            return createErrorResponse("Invalid request format")
        }
        
        let method = components[0]
        let path = components[1]
        
        print("📍 Method: \(method), Path: \(path)")
        
        // Route the request
        switch (method, path) {
        case ("GET", "/status"):
            return handleStatus()
        case ("POST", "/scan-files"):
            let body = extractBody(from: request)
            return handleScanFiles(body: body)
        case ("POST", "/sort-files"):
            let body = extractBody(from: request)
            return handleSortFiles(body: body)
        case ("GET", let imagePath) where imagePath.hasPrefix("/images/"):
            let filename = String(imagePath.dropFirst("/images/".count))
            return handleImageRequest(filename: filename)
        case ("GET", let thumbnailPath) where thumbnailPath.hasPrefix("/thumbnails/"):
            let filename = String(thumbnailPath.dropFirst("/thumbnails/".count))
            return handleThumbnailRequest(filename: filename)
        default:
            return createErrorResponse("Endpoint not found")
        }
    }
    
    private func extractBody(from request: String) -> String {
        let components = request.components(separatedBy: "\r\n\r\n")
        return components.count > 1 ? components[1] : ""
    }
    
    private func handleStatus() -> String {
        let status = [
            "status": "running",
            "watchedDirectories": watchedDirectories,
            "swiftAppRunning": true,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ] as [String : Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: status, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return createJSONResponse(jsonString)
        } catch {
            return createErrorResponse("Failed to create status response")
        }
    }
    
    private func handleScanFiles(body: String) -> String {
        print("📊 Handling scan files request with body: \(body.prefix(200))...")
        
        guard let jsonData = body.data(using: .utf8) else {
            return createErrorResponse("Invalid JSON data")
        }
        
        do {
            let requestData = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let supabaseImages = requestData?["supabaseImages"] as? [[String: Any]] else {
                return createErrorResponse("Missing or invalid supabaseImages")
            }
            
            print("🔍 Processing \(supabaseImages.count) supabase images...")
            
            // Scan local files
            var localFiles: [String] = []
            for directory in watchedDirectories {
                localFiles.append(contentsOf: scanDirectory(path: directory))
            }
            
            print("📁 Found \(localFiles.count) local files")
            
            // Compare and match
            var matches: [[String: Any]] = []
            var missingInLocal: [String] = []
            
            for supabaseImage in supabaseImages {
                guard let imageName = supabaseImage["Image Name"] as? String else { continue }
                
                if let localPath = findLocalFile(named: imageName) {
                    let approved = supabaseImage["Approved"] as? String ?? ""
                    let status = approved.lowercased() == "yes" ? "approved" : 
                               approved.lowercased() == "no" ? "not_approved" : "pending"
                    
                    matches.append([
                        "fileName": imageName,
                        "localPath": localPath,
                        "supabaseRecord": supabaseImage,
                        "status": status
                    ])
                } else {
                    missingInLocal.append(imageName)
                }
            }
            
            let localFileNames = localFiles.map { URL(fileURLWithPath: $0).lastPathComponent }
            let supabaseFileNames = supabaseImages.compactMap { $0["Image Name"] as? String }
            let missingInSupabase = localFileNames.filter { !supabaseFileNames.contains($0) }
            
            let response = [
                "localFiles": localFiles,
                "supabaseImages": supabaseImages,
                "matches": matches,
                "missing": [
                    "inLocal": missingInLocal,
                    "inSupabase": missingInSupabase
                ]
            ] as [String : Any]
            
            let jsonData = try JSONSerialization.data(withJSONObject: response, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            print("✅ Scan complete: \(matches.count) matches, \(missingInLocal.count) missing locally")
            
            return createJSONResponse(jsonString)
            
        } catch {
            print("❌ Scan files error: \(error)")
            return createErrorResponse("Failed to process scan request: \(error.localizedDescription)")
        }
    }
    
    private func handleSortFiles(body: String) -> String {
        print("📁 Handling sort files request...")
        
        guard let jsonData = body.data(using: .utf8) else {
            return createErrorResponse("Invalid JSON data")
        }
        
        do {
            let decoder = JSONDecoder()
            let instructions = try decoder.decode([SortInstruction].self, from: jsonData)
            
            var successful = 0
            var errors = 0
            var errorMessages: [String] = []
            
            for instruction in instructions {
                do {
                    try sortFile(instruction: instruction)
                    successful += 1
                    print("✅ Sorted: \(instruction.fileName)")
                } catch {
                    errors += 1
                    let errorMsg = "Failed to sort \(instruction.fileName): \(error.localizedDescription)"
                    errorMessages.append(errorMsg)
                    print("❌ \(errorMsg)")
                }
            }
            
            let response = [
                "success": true,
                "processed": instructions.count,
                "successful": successful,
                "errors": errors,
                "errorMessages": errorMessages
            ] as [String : Any]
            
            let responseData = try JSONSerialization.data(withJSONObject: response, options: [])
            let responseString = String(data: responseData, encoding: .utf8) ?? "{}"
            
            return createJSONResponse(responseString)
            
        } catch {
            print("❌ Sort files error: \(error)")
            return createErrorResponse("Failed to process sort request: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Image Serving
    private func handleImageRequest(filename: String) -> String {
        print("🖼️ Handling image request for: \(filename)")
        
        guard let filePath = findLocalFile(named: filename) else {
            return createNotFoundResponse("Image not found: \(filename)")
        }
        
        guard let imageData = fileManager.contents(atPath: filePath) else {
            return createNotFoundResponse("Could not read image: \(filename)")
        }
        
        let contentType = getContentType(for: filePath)
        return createImageResponse(imageData, contentType: contentType)
    }
    
    private func handleThumbnailRequest(filename: String) -> String {
        print("🖼️ Handling thumbnail request for: \(filename)")
        
        // For now, serve the full image (thumbnail generation can be added later)
        return handleImageRequest(filename: filename)
    }
    
    private func findLocalFile(named filename: String) -> String? {
        for directory in watchedDirectories {
            let filePath = findFileRecursively(in: directory, named: filename)
            if filePath != nil {
                return filePath
            }
        }
        return nil
    }
    
    private func findFileRecursively(in directory: String, named filename: String) -> String? {
        guard let enumerator = fileManager.enumerator(atPath: directory) else { return nil }
        
        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(filename) || file == filename {
                return directory + "/" + file
            }
        }
        return nil
    }
    
    private func getContentType(for filePath: String) -> String {
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "application/octet-stream"
        }
    }
    
    private func createImageResponse(_ imageData: Data, contentType: String) -> String {
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Content-Length: \(imageData.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "",
            ""
        ].joined(separator: "\r\n")
        
        // Convert image data to base64 and embed in response
        let base64Image = imageData.base64EncodedString()
        return headers + base64Image
    }
    
    private func createNotFoundResponse(_ message: String) -> String {
        let response = ["error": message, "success": false] as [String: Any]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: response, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            return [
                "HTTP/1.1 404 Not Found",
                "Content-Type: application/json",
                "Access-Control-Allow-Origin: *",
                "Access-Control-Allow-Methods: GET, POST, OPTIONS",
                "Access-Control-Allow-Headers: Content-Type",
                "",
                jsonString
            ].joined(separator: "\r\n")
        } catch {
            return "HTTP/1.1 404 Not Found\r\n\r\n"
        }
    }
    
    // MARK: - Helper Methods
    private func scanDirectory(path: String) -> [String] {
        var files: [String] = []
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            print("❌ Could not enumerate directory: \(path)")
            return files
        }
        
        while let file = enumerator.nextObject() as? String {
            let fullPath = path + "/" + file
            var isDirectory: ObjCBool = false
            
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory) && !isDirectory.boolValue {
                // Check if it's an image file
                let ext = URL(fileURLWithPath: file).pathExtension.lowercased()
                if ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) {
                    files.append(fullPath)
                }
            }
        }
        
        return files
    }
    
    private func sortFile(instruction: SortInstruction) throws {
        let sourceURL = URL(fileURLWithPath: instruction.currentPath)
        
        // Create target directory if it doesn't exist
        let targetDir = URL(fileURLWithPath: instruction.targetFolder)
        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
        
        // Move the file
        let targetURL = targetDir.appendingPathComponent(sourceURL.lastPathComponent)
        
        // Remove existing file if it exists
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        
        try fileManager.moveItem(at: sourceURL, to: targetURL)
    }
    
    // MARK: - HTTP Response Helpers
    private func createJSONResponse(_ json: String) -> String {
        return [
            "HTTP/1.1 200 OK",
            "Content-Type: application/json",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "",
            json
        ].joined(separator: "\r\n")
    }
    
    private func createCORSResponse() -> String {
        return [
            "HTTP/1.1 200 OK",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "",
            ""
        ].joined(separator: "\r\n")
    }
    
    private func createErrorResponse(_ message: String = "Internal Server Error") -> String {
        let errorResponse: [String: Any] = ["error": message, "success": false]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: errorResponse, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"error\":\"JSON encoding failed\",\"success\":false}"
            
            return [
                "HTTP/1.1 500 Internal Server Error",
                "Content-Type: application/json",
                "Access-Control-Allow-Origin: *",
                "Access-Control-Allow-Methods: GET, POST, OPTIONS",
                "Access-Control-Allow-Headers: Content-Type",
                "",
                jsonString
            ].joined(separator: "\r\n")
        } catch {
            return "HTTP/1.1 500 Internal Server Error\r\n\r\n{\"error\":\"Server error\",\"success\":false}"
        }
    }
}

// MARK: - Data Models
struct SortInstruction: Codable {
    let fileName: String
    let currentPath: String
    let targetFolder: String
}

struct ComparisonResult {
    let matches: [FileMatch]
    let missingInLocal: [String]
    let missingInSupabase: [String]
}

struct FileMatch {
    let fileName: String
    let localPath: String
    let supabaseRecord: [String: Any]
    let status: String
}
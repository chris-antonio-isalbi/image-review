# Web App Integration Guide

Your native macOS app now includes an HTTP server that can communicate directly with your web app! This enables real-time synchronization and automatic file organization.

## 🚀 **What's New**

### **Native App Features:**
- ✅ HTTP Server running on `localhost:8080`
- ✅ 4 REST API endpoints for web app communication
- ✅ Automatic file scanning and organization
- ✅ Real-time status updates
- ✅ CORS enabled for web app integration

### **Web App Integration:**
- ✅ Connection status indicator
- ✅ Automatic file scanning when exporting
- ✅ One-click file organization
- ✅ Real-time results and feedback

## 📡 **API Endpoints**

Your native app now provides these endpoints:

### **GET /status**
Returns server status and watched directories
```json
{
  "status": "running",
  "timestamp": "2024-12-15T10:30:00Z",
  "watchedDirectories": ["/Users/you/Pictures"]
}
```

### **POST /scan-files**
Compares web app data with local files
```javascript
// Send this:
{
  "supabaseImages": [
    {
      "Image Name": "IMG_001.jpg",
      "Approved": "Yes",
      "Reviewer": "John",
      "Comments": "Looks great!"
    }
  ]
}

// Get back:
{
  "localFiles": ["IMG_001.jpg", "IMG_002.jpg"],
  "supabaseImages": ["IMG_001.jpg"],
  "matches": [
    {
      "fileName": "IMG_001.jpg",
      "localPath": "/Users/you/Pictures/IMG_001.jpg",
      "supabaseRecord": {...},
      "status": "approved"
    }
  ],
  "missing": {
    "inLocal": [],
    "inSupabase": ["IMG_002.jpg"]
  }
}
```

### **POST /sort-files**
Organizes files into Approved/Not Approved folders
```javascript
// Send this:
[
  {
    "fileName": "IMG_001.jpg",
    "currentPath": "/Users/you/Pictures/IMG_001.jpg",
    "targetFolder": "Approved"
  }
]

// Get back:
{
  "success": true,
  "processed": 1,
  "successful": 1,
  "errors": 0
}
```

### **POST /move-files**
Moves files to specific absolute paths
```javascript
// Send this:
{
  "files": [
    {
      "fileName": "IMG_001.jpg",
      "fromPath": "/Users/you/Pictures/IMG_001.jpg",
      "toPath": "/Users/you/Approved/IMG_001.jpg"
    }
  ]
}
```

## 🔧 **Setup Instructions**

### **Step 1: Update Your Native App**

1. **Replace your `ContentView.swift`** with the updated version from `WatchFolderContentView.swift`
2. **Add the new `HTTPServer.swift`** file to your Xcode project
3. **Build and run** the app (Cmd+R)

### **Step 2: Add Web Integration to Your HTML**

Add the content from `web-integration.js` to your `Image Review.html` file, just before the closing `</script>` tag.

### **Step 3: Test the Connection**

1. **Start your native app**
2. **Click "Start Server"** in the Web App Integration section
3. **Open your web app** in browser
4. **Look for the "Native App" section** in the sidebar
5. **Should show "✅ Connected"**

## 🎯 **How It Works**

### **Automatic Workflow:**
1. **Review images** in your web app as usual
2. **Click "Export as JSON"** 
3. **Web app automatically detects** native app is running
4. **Sends data to native app** for scanning
5. **Shows results**: "Found 15 matching files, 12 approved, 3 rejected"
6. **Offers to organize**: "Would you like to automatically organize the files?"
7. **Click "OK"** → files are instantly sorted into folders!

### **Manual Workflow:**
- Use the native app's watch folder feature
- Or use the manual JSON import as before

## 🎨 **User Experience**

### **In Your Web App:**
```
┌─ Image Review ─────────────────────┐
│ [Existing content]                 │
│                                    │
│ ──────────────────                 │
│ Native App                         │
│ ✅ Connected                       │
│ [Check Connection]                 │
│                                    │
│ Export Data                        │
│ [Export as JSON] ← Enhanced!       │
└────────────────────────────────────┘
```

### **When You Export:**
```
📊 Native App Sync Results:

✅ Found 15 matching files
⚠️ 2 images not found locally
ℹ️ 3 local files not in review data

📈 Breakdown:
• 12 approved images
• 3 rejected images

[OK] [Cancel]
```

### **Then:**
```
Would you like to automatically organize the files?

This will move:
• 12 images → Approved folder
• 3 images → Not Approved folder

[Yes, organize now] [No, just export]
```

### **Result:**
```
✅ Successfully organized 15 out of 15 files!

Your images are now sorted in:
📁 /Users/you/Pictures/Approved/ (12 images)
📁 /Users/you/Pictures/Not Approved/ (3 images)
```

## 🔍 **Native App Interface**

Your native app now shows:

```
┌─ Image Review File Organizer ─────────────────────┐
│                                                   │
│ 🌐 Web App Integration                            │
│ HTTP Server Status: Running on localhost:8080    │
│ [Stop Server]                                     │
│                                                   │
│ Available endpoints:                              │
│ • GET http://localhost:8080/status               │
│ • POST http://localhost:8080/scan-files          │
│ • POST http://localhost:8080/sort-files          │
│ • POST http://localhost:8080/move-files          │
│                                                   │
│ 🔍 Auto-Watch Folder                              │
│ [Your existing watch folder functionality]        │
│                                                   │
│ 📁 Manual Processing                              │
│ [Your existing manual functionality]              │
└───────────────────────────────────────────────────┘
```

## 🚨 **Security Notes**

- **Server runs on localhost only** (not accessible from internet)
- **Automatically handles CORS** for web app communication
- **Safe file operations** (moves files, never deletes)
- **Server stops** when app is closed

## 🎉 **Benefits**

1. **No more manual steps**: Export → Organize happens in one click
2. **Real-time feedback**: See exactly what files are found/missing
3. **Error handling**: Know immediately if something goes wrong
4. **Flexible**: Works with both web app integration AND manual workflow
5. **Fast**: Local communication, instant file operations

## 🔧 **Troubleshooting**

### **"Not Connected" in web app:**
- Make sure native app is running
- Click "Start Server" in native app
- Check "Web App Integration" section shows "Running"

### **Server won't start:**
- Port 8080 might be in use
- Restart the native app
- Check Console.app for error messages

### **Files not found:**
- Make sure image folder is selected in native app
- Verify image files exist in the specified location
- Check file extensions match (jpg, png, etc.)

This integration creates a seamless bridge between your web-based review process and local file organization! 🎊
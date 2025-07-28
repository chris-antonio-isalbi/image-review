// Web App Integration with Native macOS App
// Add this to your Image Review.html file

class NativeAppConnector {
    constructor() {
        this.baseURL = 'http://localhost:8080';
        this.isConnected = false;
    }

    // Check if the native app is running
    async checkConnection() {
        try {
            const response = await fetch(`${this.baseURL}/status`);
            if (response.ok) {
                const data = await response.json();
                this.isConnected = true;
                console.log('✅ Connected to native app:', data);
                return true;
            }
        } catch (error) {
            this.isConnected = false;
            console.log('❌ Native app not running');
        }
        return false;
    }

    // Send feedback data to native app for scanning
    async scanFiles(feedbackData) {
        try {
            const response = await fetch(`${this.baseURL}/scan-files`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    supabaseImages: feedbackData
                })
            });

            if (response.ok) {
                const result = await response.json();
                console.log('📊 Scan results:', result);
                return result;
            } else {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
        } catch (error) {
            console.error('❌ Failed to scan files:', error);
            throw error;
        }
    }

    // Sort files into Approved/Not Approved folders
    async sortFiles(instructions) {
        try {
            const response = await fetch(`${this.baseURL}/sort-files`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(instructions)
            });

            if (response.ok) {
                const result = await response.json();
                console.log('📁 Sort results:', result);
                return result;
            } else {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
        } catch (error) {
            console.error('❌ Failed to sort files:', error);
            throw error;
        }
    }

    // Move files to specific paths
    async moveFiles(moveInstructions) {
        try {
            const response = await fetch(`${this.baseURL}/move-files`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(moveInstructions)
            });

            if (response.ok) {
                const result = await response.json();
                console.log('🚚 Move results:', result);
                return result;
            } else {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
        } catch (error) {
            console.error('❌ Failed to move files:', error);
            throw error;
        }
    }
}

// Initialize the connector
const nativeApp = new NativeAppConnector();

// Enhanced export functionality that also communicates with native app
function exportFeedbackDataWithNativeSync() {
    // Collect all feedback data in the format that matches your current system
    const exportData = [];
    
    // Go through all images and their feedback
    for (const img of images) {
        const feedback = feedbackData.filter(f => f['Image Name'] === img.name);
        
        if (feedback.length > 0) {
            // Get the latest feedback for each image
            const latest = feedback[0];
            const isApproved = latest.Approved === 'Yes';
            
            exportData.push({
                "Image Name": img.name,
                "Approved": latest.Approved || "No",
                "Reviewer": latest.Reviewer || "",
                "Comments": latest.Comments || "",
                "Timestamp": latest.Timestamp || new Date().toISOString(),
                "Folder": currentFolderName || ""
            });
        } else {
            // Include images without feedback as pending
            exportData.push({
                "Image Name": img.name,
                "Approved": "Pending",
                "Reviewer": "",
                "Comments": "",
                "Timestamp": new Date().toISOString(),
                "Folder": currentFolderName || ""
            });
        }
    }
    
    // Traditional JSON export
    const jsonData = JSON.stringify(exportData, null, 2);
    const blob = new Blob([jsonData], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    const a = document.createElement('a');
    a.href = url;
    a.download = `image-review-export-${currentFolderName || 'data'}-${new Date().toISOString().split('T')[0]}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    
    URL.revokeObjectURL(url);
    
    // Try to sync with native app
    syncWithNativeApp(exportData);
    
    console.log('Exported', exportData.length, 'image records');
    alert(`Exported ${exportData.length} image records to JSON file`);
}

// Function to sync data with native app
async function syncWithNativeApp(feedbackData) {
    // Check if native app is running
    const isConnected = await nativeApp.checkConnection();
    
    if (!isConnected) {
        console.log('ℹ️ Native app not running. Skipping sync.');
        return;
    }

    try {
        // Send data to native app for scanning
        const scanResults = await nativeApp.scanFiles(feedbackData);
        
        // Show results to user
        showNativeAppResults(scanResults);
        
        // Optionally, auto-sort files
        if (confirm('Would you like to automatically organize the files?')) {
            await autoSortFiles(scanResults);
        }
        
    } catch (error) {
        console.error('Failed to sync with native app:', error);
    }
}

// Show scan results to user
function showNativeAppResults(results) {
    const { matches, missing } = results;
    
    let message = `📊 Native App Sync Results:\n\n`;
    message += `✅ Found ${matches.length} matching files\n`;
    
    if (missing.inLocal.length > 0) {
        message += `⚠️ ${missing.inLocal.length} images not found locally\n`;
    }
    
    if (missing.inSupabase.length > 0) {
        message += `ℹ️ ${missing.inSupabase.length} local files not in review data\n`;
    }
    
    // Count approved vs rejected
    const approved = matches.filter(m => m.status === 'approved').length;
    const rejected = matches.filter(m => m.status === 'not_approved').length;
    
    message += `\n📈 Breakdown:\n`;
    message += `• ${approved} approved images\n`;
    message += `• ${rejected} rejected images\n`;
    
    alert(message);
}

// Auto-sort files based on approval status
async function autoSortFiles(scanResults) {
    const instructions = [];
    
    for (const match of scanResults.matches) {
        const targetFolder = match.status === 'approved' ? 'Approved' : 'Not Approved';
        
        instructions.push({
            fileName: match.fileName,
            currentPath: match.localPath,
            targetFolder: targetFolder
        });
    }
    
    if (instructions.length > 0) {
        try {
            const result = await nativeApp.sortFiles(instructions);
            alert(`✅ Successfully organized ${result.successful} out of ${result.processed} files!`);
        } catch (error) {
            alert(`❌ Failed to organize files: ${error.message}`);
        }
    }
}

// Add connection status indicator to the UI
function addNativeAppStatus() {
    const sidebar = document.getElementById('sidebar');
    if (!sidebar) return;
    
    // Create status section
    const statusSection = document.createElement('div');
    statusSection.style.marginTop = '20px';
    statusSection.style.borderTop = '1px solid #ccc';
    statusSection.style.paddingTop = '20px';
    
    const statusTitle = document.createElement('h4');
    statusTitle.textContent = 'Native App';
    statusTitle.style.fontSize = '14px';
    statusTitle.style.marginBottom = '10px';
    statusSection.appendChild(statusTitle);
    
    const statusIndicator = document.createElement('div');
    statusIndicator.id = 'native-app-status';
    statusIndicator.style.padding = '8px';
    statusIndicator.style.borderRadius = '4px';
    statusIndicator.style.fontSize = '12px';
    statusIndicator.style.textAlign = 'center';
    statusIndicator.textContent = 'Checking connection...';
    statusIndicator.style.backgroundColor = '#f0f0f0';
    statusIndicator.style.color = '#666';
    
    statusSection.appendChild(statusIndicator);
    
    const connectButton = document.createElement('button');
    connectButton.textContent = 'Check Connection';
    connectButton.style.width = '100%';
    connectButton.style.padding = '8px';
    connectButton.style.marginTop = '8px';
    connectButton.style.backgroundColor = '#007bff';
    connectButton.style.color = 'white';
    connectButton.style.border = 'none';
    connectButton.style.borderRadius = '4px';
    connectButton.style.cursor = 'pointer';
    connectButton.style.fontSize = '12px';
    
    connectButton.onclick = async function() {
        const isConnected = await nativeApp.checkConnection();
        updateConnectionStatus(isConnected);
    };
    
    statusSection.appendChild(connectButton);
    sidebar.appendChild(statusSection);
    
    // Check connection on page load
    setTimeout(async () => {
        const isConnected = await nativeApp.checkConnection();
        updateConnectionStatus(isConnected);
    }, 1000);
}

function updateConnectionStatus(isConnected) {
    const statusIndicator = document.getElementById('native-app-status');
    if (!statusIndicator) return;
    
    if (isConnected) {
        statusIndicator.textContent = '✅ Connected';
        statusIndicator.style.backgroundColor = '#d4edda';
        statusIndicator.style.color = '#155724';
    } else {
        statusIndicator.textContent = '❌ Not Connected';
        statusIndicator.style.backgroundColor = '#f8d7da';
        statusIndicator.style.color = '#721c24';
    }
}

// Replace the original export function
const originalExportFunction = exportFeedbackData;
exportFeedbackData = exportFeedbackDataWithNativeSync;

// Add status indicator when page loads
document.addEventListener('DOMContentLoaded', function() {
    setTimeout(addNativeAppStatus, 1500);
});

// Also add it after folders load
const originalLoadFoldersForNative = loadFolders;
loadFolders = function() {
    const result = originalLoadFoldersForNative.apply(this, arguments);
    setTimeout(addNativeAppStatus, 1000);
    return result;
};
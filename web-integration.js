// Web App Integration with Native macOS App
// Add this to your Image Review.html file

// Enhanced Native App Connector with Dynamic URL Detection
class NativeAppConnector {
    constructor() {
        // List of possible server URLs (ngrok URL will be added dynamically)
        this.possibleURLs = [
            'http://localhost:8080'    // Local development fallback
        ];
        this.baseURL = null;
        this.isConnected = false;
        this.ngrokURL = null; // Will be set when ngrok is detected
    }

    // Add ngrok URL to the list of possible URLs
    setNgrokURL(ngrokURL) {
        this.ngrokURL = ngrokURL;
        // Add ngrok URL at the beginning (higher priority)
        this.possibleURLs = [ngrokURL, ...this.possibleURLs.filter(url => url !== ngrokURL)];
        console.log(`🔗 Added ngrok URL: ${ngrokURL}`);
    }

    // Try to find a working server URL
    async findWorkingURL() {
        console.log('🔍 Searching for working server URL...');
        
        for (const url of this.possibleURLs) {
            try {
                console.log(`🔍 Trying: ${url}`);
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), 5000); // 5 second timeout
                
                const response = await fetch(`${url}/status`, {
                    method: 'GET',
                    headers: { 'Content-Type': 'application/json' },
                    mode: 'cors',
                    signal: controller.signal
                });
                
                clearTimeout(timeoutId);
                
                if (response.ok) {
                    const data = await response.json();
                    if (data.swiftAppRunning === true) {
                        this.baseURL = url;
                        this.isConnected = true;
                        console.log(`✅ Connected to: ${url}`);
                        this.updateConnectionUI(url);
                        return true;
                    }
                }
            } catch (error) {
                console.log(`❌ Failed to connect to: ${url} - ${error.message}`);
            }
        }
        
        this.isConnected = false;
        this.baseURL = null;
        console.log('❌ No working server found');
        this.updateConnectionUI(null);
        return false;
    }

    async checkConnection() {
        // If we don't have a baseURL, try to find one
        if (!this.baseURL) {
            return await this.findWorkingURL();
        }
        
        // Test current URL
        try {
            const response = await fetch(`${this.baseURL}/status`, {
                method: 'GET',
                headers: { 'Content-Type': 'application/json' },
                mode: 'cors'
            });
            
            if (response.ok) {
                const data = await response.json();
                this.isConnected = data.swiftAppRunning === true;
                this.updateConnectionUI(this.isConnected ? this.baseURL : null);
                return this.isConnected;
            }
        } catch (error) {
            console.log(`❌ Current URL failed: ${this.baseURL}`);
            // Current URL failed, try to find a working one
            return await this.findWorkingURL();
        }
        
        return false;
    }

    // Update the UI to show connection status
    updateConnectionUI(connectedURL) {
        const statusElement = document.getElementById('nativeAppStatus') || this.createStatusElement();
        
        if (connectedURL) {
            const urlType = connectedURL.includes('ngrok') ? '🌐 Remote' : '💻 Local';
            statusElement.innerHTML = `
                <div style="color: green; font-weight: bold;">
                    ✅ Connected ${urlType}
                </div>
                <div style="font-size: 12px; color: #666;">
                    ${connectedURL}
                </div>
            `;
            statusElement.className = 'connected';
        } else {
            statusElement.innerHTML = `
                <div style="color: red; font-weight: bold;">
                    ❌ Disconnected
                </div>
                <div style="font-size: 12px; color: #666;">
                    Make sure your Swift app is running
                </div>
            `;
            statusElement.className = 'disconnected';
        }
    }

    // Create status element if it doesn't exist
    createStatusElement() {
        let statusElement = document.getElementById('nativeAppStatus');
        if (!statusElement) {
            statusElement = document.createElement('div');
            statusElement.id = 'nativeAppStatus';
            statusElement.style.cssText = `
                position: fixed;
                top: 10px;
                right: 10px;
                background: white;
                border: 2px solid #ddd;
                border-radius: 8px;
                padding: 10px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                z-index: 1000;
                min-width: 200px;
            `;
            document.body.appendChild(statusElement);
        }
        return statusElement;
    }

    async scanFiles(supabaseImages) {
        if (!this.isConnected || !this.baseURL) {
            throw new Error('Not connected to native app');
        }

        const response = await fetch(`${this.baseURL}/scan-files`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            mode: 'cors',
            body: JSON.stringify({ supabaseImages })
        });

        if (!response.ok) {
            throw new Error(`Scan failed: ${response.statusText}`);
        }

        return await response.json();
    }

    async sortFiles(instructions) {
        if (!this.isConnected || !this.baseURL) {
            throw new Error('Not connected to native app');
        }

        const response = await fetch(`${this.baseURL}/sort-files`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            mode: 'cors',
            body: JSON.stringify(instructions)
        });

        if (!response.ok) {
            throw new Error(`Sort failed: ${response.statusText}`);
        }

        return await response.json();
    }
}

// Global connector instance
const nativeAppConnector = new NativeAppConnector();

// Auto-check connection every 10 seconds
setInterval(async () => {
    if (!nativeAppConnector.isConnected) {
        await nativeAppConnector.checkConnection();
    }
}, 10000);

// Initial connection check
nativeAppConnector.checkConnection();

// Function to manually set ngrok URL (you'll call this when you get the ngrok URL)
function setNgrokURL(ngrokURL) {
    nativeAppConnector.setNgrokURL(ngrokURL);
    nativeAppConnector.checkConnection(); // Immediately try to connect
}

// Enhanced export function with native app sync
async function exportFeedbackDataWithNativeSync() {
    console.log('📤 Starting export with native sync...');
    
    try {
        // Check connection first
        const isConnected = await nativeAppConnector.checkConnection();
        if (!isConnected) {
            alert('❌ Cannot connect to native app. Make sure your Swift server is running.');
            return;
        }

        // Get all feedback data
        const feedbackData = getAllFeedbackData();
        if (feedbackData.length === 0) {
            alert('No feedback data to export.');
            return;
        }

        console.log(`📊 Exporting ${feedbackData.length} feedback entries...`);

        // Sync with native app
        await syncWithNativeApp(feedbackData);
        
    } catch (error) {
        console.error('❌ Export failed:', error);
        alert(`Export failed: ${error.message}`);
    }
}

async function syncWithNativeApp(feedbackData) {
    try {
        // Transform data for native app
        const supabaseImages = feedbackData.map(item => ({
            'Image Name': item.imageName,
            'Approved': item.status === 'Approved' ? 'Yes' : 'No',
            'Reviewer': item.reviewer || 'Unknown',
            'Comments': item.comments || '',
            'Timestamp': item.timestamp || new Date().toISOString(),
            'Folder': item.folderName || 'Unknown'
        }));

        console.log('🔍 Scanning files in native app...');
        const scanResult = await nativeAppConnector.scanFiles(supabaseImages);
        
        console.log('✅ Scan complete:', scanResult);
        showNativeAppResults(scanResult);
        
    } catch (error) {
        console.error('❌ Native app sync failed:', error);
        throw error;
    }
}

function showNativeAppResults(scanResult) {
    const matches = scanResult.matches || [];
    const missing = scanResult.missing || {};
    
    const summary = `
📊 Scan Results:
• ${matches.length} files matched
• ${missing.inLocal?.length || 0} files missing locally
• ${missing.inSupabase?.length || 0} files not in review data

Would you like to organize the matched files into Approved/Not Approved folders?
    `;
    
    if (confirm(summary.trim())) {
        autoSortFiles(matches);
    }
}

async function autoSortFiles(matches) {
    try {
        const instructions = matches.map(match => ({
            fileName: match.fileName,
            currentPath: match.localPath,
            targetFolder: match.status === 'approved' ? 'Approved' : 
                         match.status === 'not_approved' ? 'Not Approved' : 'Pending Review'
        }));
        
        console.log('📁 Sorting files...');
        const sortResult = await nativeAppConnector.sortFiles(instructions);
        
        alert(`✅ File organization complete!\n• ${sortResult.successful} files moved successfully\n• ${sortResult.errors} errors`);
        
    } catch (error) {
        console.error('❌ Auto-sort failed:', error);
        alert(`File organization failed: ${error.message}`);
    }
}

// Helper function to get all feedback data (you'll need to implement this based on your app)
function getAllFeedbackData() {
    // This should return an array of your feedback data
    // You'll need to adapt this to your specific data structure
    const feedbackData = [];
    
    // Example implementation - adapt to your actual data structure
    const feedbackElements = document.querySelectorAll('[data-feedback]');
    feedbackElements.forEach(element => {
        const data = JSON.parse(element.dataset.feedback || '{}');
        if (data.imageName) {
            feedbackData.push(data);
        }
    });
    
    return feedbackData;
}
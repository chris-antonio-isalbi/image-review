// Add this JavaScript code to your Image Review.html file to enable JSON export
// Insert this code just before the closing </script> tag

// Function to export feedback data as JSON
function exportFeedbackData() {
    // Collect all feedback data
    const exportData = [];
    
    // Go through all images and their feedback
    for (const img of images) {
        const feedback = feedbackData.filter(f => f['Image Name'] === img.name);
        
        if (feedback.length > 0) {
            // Get the latest feedback for each image
            const latest = feedback[0];
            
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
    
    // Create and download the JSON file
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
    
    console.log('Exported', exportData.length, 'image records');
    alert(`Exported ${exportData.length} image records to JSON file`);
}

// Add export button to the sidebar
function addExportButton() {
    const sidebar = document.getElementById('sidebar');
    if (!sidebar) return;
    
    // Create export section
    const exportSection = document.createElement('div');
    exportSection.style.marginTop = '20px';
    exportSection.style.borderTop = '1px solid #ccc';
    exportSection.style.paddingTop = '20px';
    
    const exportTitle = document.createElement('h4');
    exportTitle.textContent = 'Export Data';
    exportTitle.style.fontSize = '14px';
    exportTitle.style.marginBottom = '10px';
    exportSection.appendChild(exportTitle);
    
    const exportButton = document.createElement('button');
    exportButton.textContent = 'Export as JSON';
    exportButton.style.width = '100%';
    exportButton.style.padding = '10px';
    exportButton.style.backgroundColor = '#28a745';
    exportButton.style.color = 'white';
    exportButton.style.border = 'none';
    exportButton.style.borderRadius = '4px';
    exportButton.style.cursor = 'pointer';
    exportButton.style.fontSize = '14px';
    
    exportButton.onmouseover = function() {
        this.style.backgroundColor = '#218838';
    };
    
    exportButton.onmouseout = function() {
        this.style.backgroundColor = '#28a745';
    };
    
    exportButton.onclick = exportFeedbackData;
    
    exportSection.appendChild(exportButton);
    sidebar.appendChild(exportSection);
}

// Add the export button when the page loads
document.addEventListener('DOMContentLoaded', function() {
    // Wait a bit for the page to fully load
    setTimeout(addExportButton, 1000);
});

// Also add it after folders load
const originalLoadFolders = loadFolders;
loadFolders = function() {
    const result = originalLoadFolders.apply(this, arguments);
    setTimeout(addExportButton, 500);
    return result;
};
# Network Optimizer & Speed Test

A PowerShell script to optimize Windows network settings, perform internet speed tests, and generate a visual HTML report with graphs.

## Features
- Optimizes key Windows network settings for performance
- Tests internet speed (latency, download, upload)
- Downloads large files to measure real-world speed
- Displays current network configuration and optimization status
- Generates a modern HTML report with interactive charts
- Logs all actions and results to a log file

## Prerequisites
- Windows 10/11
- PowerShell 5.0+
- Run as Administrator for full optimization

## Usage
1. **Open PowerShell as Administrator**
2. Navigate to the script directory:
   ```powershell
   cd "YOUR SCRIPT LOCATION HERE"
   ```
3. Run the script:
   ```powershell
   .\network-optimizer.ps1
   ```
4. Follow the prompts to choose which tests and optimizations to run.
5. After completion, the HTML report will open automatically. You can share it or export as PDF.

## Sharing Reports
- Send the HTML file directly
- Export as PDF from your browser (Ctrl+P → Save as PDF)
- Upload to OneDrive, Google Drive, Dropbox, etc.

## Troubleshooting
- **Run as Administrator** for registry/network changes
- If network throttling does not persist, check for group policies or security software that may revert registry changes
- All actions and errors are logged to `network-optimizer.log` in the script directory

## License
MIT

## Author
Brian Kinney

---

Feel free to fork, modify, and share! Pull requests and feedback are welcome.

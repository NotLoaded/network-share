# 🚀 Plug-and-Play Local Network Share

A lightweight, zero-dependency local network file-sharing server built entirely with standard Windows tools.

## 🌟 What it does
This system allows you to instantly spin up a local web server from a USB stick or a folder on any modern Windows computer. It creates a simple, beautiful, and mobile-friendly web interface that anyone on your local network (Wi-Fi or LAN) can access to:
- **Download** files you have placed in the shared folder.
- **Upload** files from their devices directly onto your computer.

No Node.js, Python, or third-party software is required. It works completely out-of-the-box using the built-in capabilities of Windows.

## ⚙️ How it currently works

1. **Launch**: You double-click `Start-Server.bat`.
2. **Execution**: It launches `ServerLogic.ps1`, bypassing default PowerShell execution policies for this specific run.
3. **Networking Setup**: The script automatically detects your active local IPv4 address.
4. **Server Initialization**: It starts a custom raw TCP HTTP server (using `.NET TcpListener`) bound specifically to your active IP address, operating entirely at the user level without requiring Administrator privileges.
5. **Interaction**: 
   - The server prints an exact, clickable URL to the console.
   - Any files dropped into the auto-generated `SharedFiles/` folder appear instantly on the web page.
   - Visitors using the web page can download those files, delete them, or upload new ones.
6. **Clean Teardown**: Pressing `Ctrl + C` in the console gracefully interrupts the server loop and immediately shuts down the server.

## 🛠️ Implementation Details & Architecture

When designing this, the primary goal was **maximum compatibility with zero dependencies**, requiring pure PowerShell and native .NET integration. 

Here is how the specific technical challenges were solved during development:

### 1. The Web Server Core (Bypassing HTTP.sys)
Instead of using Windows' built-in `HttpListener` (which relies on the `http.sys` kernel driver and strictly requires Administrator privileges or URL ACLs to bind to network IPs), this script builds a fully custom, lightweight HTTP server from scratch using raw `[System.Net.Sockets.TcpListener]`. It manually parses HTTP headers, request lines, and binary payloads, allowing it to operate entirely at the user level without ever throwing "Access Denied".

### 2. Graceful Thread Handling (The `Ctrl+C` Fix)
Natively, `HttpListener.GetContext()` is a deeply blocking call. If used, it freezes the PowerShell thread entirely until a network request arrives, causing it to ignore `Ctrl+C` keyboard interrupts. 
**Solution**: The server loop uses the asynchronous `$listener.GetContextAsync()` method combined with a rapid 50-millisecond `Start-Sleep` polling loop. This allows PowerShell to "breathe" and immediately catch the `PipelineStoppedException` triggered by `Ctrl+C`, resulting in instant, clean shutdowns.

### 3. File Uploading (Bypassing `multipart/form-data`)
Handling standard HTML form file uploads (`multipart/form-data`) in pure PowerShell requires complex, error-prone manual byte-boundary parsing.
**Solution**: Instead of a traditional HTML form submission, the custom frontend uses JavaScript's modern `fetch()` API. It reads the file locally in the browser and sends it as a raw byte stream in the POST request body, passing the filename via a custom `X-File-Name` HTTP header. The PowerShell backend simply reads the raw stream directly to a file, completely eliminating the need for complex multipart parsing.

### 4. User-Level Architecture (No Admin)
By bypassing `http.sys` entirely and using a raw TCP socket, the server operates purely at the user level. It completely avoids modifying system-wide firewall rules or requiring complex UAC elevation prompts, allowing you to run it plug-and-play on heavily restricted computers.

### 5. Encoding Stability
To prevent Windows' default ANSI code pages (like Windows-1252) from corrupting emojis into unreadable "Mojibake" (e.g., `â˜ï¸`), all emojis in the embedded HTML string were replaced with their strict HTML entity equivalents (e.g., `&#9729;&#65039;`). This ensures the UI renders perfectly regardless of how the host OS parses the script file's encoding.

## 🎨 UI/UX Design
The frontend is embedded as a "here-string" directly within the PowerShell script. It features a modern, dark-themed, glassmorphic UI built purely with vanilla CSS and JavaScript, avoiding any reliance on external CDNs or frameworks like Tailwind or React to maintain offline plug-and-play capability.

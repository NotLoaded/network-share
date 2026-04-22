param (
    [int]$Port = 8080
)

# Setup paths (Compatible with standard scripts and PS2EXE)
$scriptPath = $PSScriptRoot
if ([string]::IsNullOrEmpty($scriptPath)) {
    $scriptPath = [System.IO.Path]::GetDirectoryName([Environment]::GetCommandLineArgs()[0])
}
if ([string]::IsNullOrEmpty($scriptPath)) {
    $scriptPath = (Get-Location).Path
}
$sharedFolder = Join-Path $scriptPath "SharedFiles"

if (!(Test-Path $sharedFolder)) {
    Write-Host "Creating SharedFiles directory..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $sharedFolder | Out-Null
}

# Find the correct local IPv4 address by checking the default gateway
$ipAddress = "127.0.0.1"
$defaultGateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
if ($defaultGateway) {
    $ipInfo = Get-NetIPAddress -InterfaceIndex $defaultGateway.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch "^169\.254" -and $_.IPAddress -notmatch "^127\." }
    if ($ipInfo) {
        $ipAddress = $ipInfo[0].IPAddress
    }
}

# Fallback if the above fails
if ($ipAddress -eq "127.0.0.1") {
    $fallbackInfos = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch "^169\.254" -and $_.IPAddress -notmatch "^127\." -and $_.InterfaceAlias -notmatch "vEthernet|VMware|Virtual" }
    if ($fallbackInfos) {
        $ipAddress = $fallbackInfos[0].IPAddress
    } else {
        try { $ipAddress = (Test-Connection -ComputerName (hostname) -Count 1 -ErrorAction Stop).IPv4Address.IPAddressToString } catch {}
    }
}

try {
# Setup raw TCP Listener (User-Level, No Admin Required, bypasses HTTP.sys restrictions completely)
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)

try {
    $listener.Start()
} catch {
    Write-Host "`n[ERROR] Failed to start server: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Ensure no other application is using port $Port." -ForegroundColor Yellow
    exit
}

Clear-Host
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " SERVER IS RUNNING " -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "`nShare this exact link with others on your network:" -ForegroundColor White
Write-Host "    http://${ipAddress}:${Port}" -ForegroundColor Cyan
Write-Host "`nAll files dropped into this folder will be shared:" -ForegroundColor White
Write-Host "--> $sharedFolder" -ForegroundColor Cyan
Write-Host "`nPress Ctrl+C to stop the server.`n" -ForegroundColor Gray

# Define HTML Template
$htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Network Share</title>
    <style>
        :root {
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --glass-bg: rgba(255, 255, 255, 0.05);
            --glass-border: rgba(255, 255, 255, 0.1);
            --accent: #8b5cf6;
            --accent-hover: #7c3aed;
            --success: #10b981;
        }
        body {
            margin: 0;
            min-height: 100vh;
            background: linear-gradient(135deg, #0f172a 0%, #1e1b4b 100%);
            font-family: system-ui, -apple-system, sans-serif;
            color: var(--text-main);
            display: flex;
            justify-content: center;
            padding: 2rem;
            box-sizing: border-box;
        }
        .container {
            width: 100%;
            max-width: 800px;
            background: var(--glass-bg);
            backdrop-filter: blur(12px);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid var(--glass-border);
            border-radius: 24px;
            padding: 3rem;
            box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
            animation: fadeIn 0.5s ease-out;
        }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
        h1 {
            text-align: center;
            font-size: 2.5rem;
            margin-top: 0;
            background: linear-gradient(to right, #3b82f6, #8b5cf6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .ip-banner {
            background: rgba(59, 130, 246, 0.1);
            border: 1px solid rgba(59, 130, 246, 0.3);
            padding: 1rem;
            border-radius: 12px;
            text-align: center;
            font-size: 1.2rem;
            font-weight: 600;
            margin-bottom: 2.5rem;
            color: #60a5fa;
            letter-spacing: 0.5px;
        }
        .upload-section {
            border: 2px dashed rgba(139, 92, 246, 0.5);
            border-radius: 16px;
            padding: 3rem 2rem;
            text-align: center;
            transition: all 0.3s ease;
            background: rgba(0,0,0,0.2);
            margin-bottom: 3rem;
        }
        .upload-section.dragover {
            border-color: #8b5cf6;
            background: rgba(139, 92, 246, 0.1);
            transform: scale(1.02);
        }
        .upload-icon {
            font-size: 3rem;
            margin-bottom: 1rem;
            display: block;
        }
        .upload-btn {
            background: linear-gradient(135deg, #3b82f6, #8b5cf6);
            color: white;
            border: none;
            padding: 0.8rem 2rem;
            border-radius: 999px;
            font-size: 1.1rem;
            font-weight: 600;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
            margin-top: 1rem;
        }
        .upload-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px -10px #8b5cf6;
        }
        .file-list {
            list-style: none;
            padding: 0;
            margin: 0;
            display: grid;
            gap: 1rem;
        }
        .file-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 1.2rem;
            background: rgba(255,255,255,0.03);
            border: 1px solid var(--glass-border);
            border-radius: 12px;
            transition: transform 0.2s, background 0.2s;
        }
        .file-item:hover {
            background: rgba(255,255,255,0.06);
            transform: translateX(5px);
        }
        .file-info {
            display: flex;
            flex-direction: column;
            gap: 0.4rem;
            overflow: hidden;
        }
        .file-name {
            font-weight: 600;
            font-size: 1.1rem;
            color: #fff;
            text-decoration: none;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .file-meta {
            font-size: 0.9rem;
            color: var(--text-muted);
        }
        .download-btn {
            background: rgba(255,255,255,0.1);
            color: #fff;
            text-decoration: none;
            padding: 0.6rem 1.2rem;
            border-radius: 8px;
            font-weight: 500;
            transition: background 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
        }
        .download-btn:hover {
            background: var(--accent);
        }
        #progress-container {
            display: none;
            margin-top: 1.5rem;
        }
        .progress-bar {
            height: 10px;
            background: rgba(255,255,255,0.1);
            border-radius: 999px;
            overflow: hidden;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #3b82f6, #8b5cf6);
            width: 0%;
            transition: width 0.3s ease;
        }
        .status-text { margin-top: 0.8rem; font-size: 0.95rem; color: var(--text-muted); font-weight: 500; }
        .action-group { position: relative; display: flex; align-items: center; gap: 0.5rem; }
        .menu-btn { background: transparent; border: none; color: var(--text-muted); padding: 0.4rem 0.6rem; border-radius: 8px; cursor: pointer; font-size: 1.2rem; transition: background 0.2s; }
        .menu-btn:hover { background: rgba(255,255,255,0.1); color: #fff; }
        .dropdown { position: absolute; right: 0; top: 100%; margin-top: 0.5rem; background: #1e293b; border: 1px solid var(--glass-border); border-radius: 8px; padding: 0.4rem; min-width: 120px; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.5); display: none; z-index: 10; }
        .dropdown.show { display: block; }
        .dropdown-item { width: 100%; text-align: left; background: transparent; border: none; color: #ef4444; padding: 0.6rem; border-radius: 6px; cursor: pointer; font-size: 0.9rem; transition: background 0.2s; }
        .dropdown-item:hover { background: rgba(239, 68, 68, 0.1); }
        @media (max-width: 600px) {
            .container { padding: 1.5rem; }
            .file-item { flex-direction: column; align-items: flex-start; gap: 1rem; }
            .download-btn { width: 100%; justify-content: center; box-sizing: border-box; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Network Share</h1>
        <div class="ip-banner">
            Access Link: http://<!-- IP_PLACEHOLDER -->:<!-- PORT_PLACEHOLDER -->
        </div>

        <div class="upload-section" id="drop-zone">
            <span class="upload-icon">&#9729;&#65039;</span>
            <h3 style="margin-top:0; font-size: 1.5rem; color: #fff;">Upload Files</h3>
            <p style="color: var(--text-muted); margin-bottom: 1rem; font-size: 1.1rem;">Drag & drop files here or click to browse</p>
            <input type="file" id="file-input" style="display: none;" multiple>
            <button class="upload-btn" onclick="document.getElementById('file-input').click()">Select Files</button>
            
            <div id="progress-container">
                <div class="progress-bar"><div class="progress-fill" id="progress-fill"></div></div>
                <div class="status-text" id="status-text">Uploading... 0%</div>
            </div>
        </div>

        <h3 style="color: #fff; font-size: 1.5rem; margin-bottom: 1rem;">Available Files</h3>
        <ul class="file-list" id="file-list">
            <!-- FILES_PLACEHOLDER -->
        </ul>
    </div>

    <script>
        const dropZone = document.getElementById('drop-zone');
        const fileInput = document.getElementById('file-input');
        const progressContainer = document.getElementById('progress-container');
        const progressFill = document.getElementById('progress-fill');
        const statusText = document.getElementById('status-text');

        ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
            dropZone.addEventListener(eventName, preventDefaults, false);
        });

        function preventDefaults(e) {
            e.preventDefault();
            e.stopPropagation();
        }

        ['dragenter', 'dragover'].forEach(eventName => {
            dropZone.addEventListener(eventName, () => dropZone.classList.add('dragover'), false);
        });

        ['dragleave', 'drop'].forEach(eventName => {
            dropZone.addEventListener(eventName, () => dropZone.classList.remove('dragover'), false);
        });

        dropZone.addEventListener('drop', (e) => {
            const files = e.dataTransfer.files;
            handleFiles(files);
        }, false);

        fileInput.addEventListener('change', function() {
            handleFiles(this.files);
        });

        async function handleFiles(files) {
            if (files.length === 0) return;
            
            progressContainer.style.display = 'block';
            
            for (let i = 0; i < files.length; i++) {
                const file = files[i];
                statusText.innerText = `Uploading ${file.name}...`;
                progressFill.style.width = '0%';
                
                try {
                    await uploadFile(file);
                } catch (err) {
                    alert('Error uploading ' + file.name + ': ' + err.message);
                }
            }
            
            statusText.innerText = 'Upload complete! Refreshing...';
            statusText.style.color = 'var(--success)';
            progressFill.style.background = 'var(--success)';
            
            setTimeout(() => {
                window.location.reload();
            }, 800);
        }

        function uploadFile(file) {
            return new Promise((resolve, reject) => {
                const xhr = new XMLHttpRequest();
                xhr.open('POST', '/upload', true);
                
                xhr.setRequestHeader('X-File-Name', encodeURIComponent(file.name));
                
                xhr.upload.onprogress = function(e) {
                    if (e.lengthComputable) {
                        const percentComplete = (e.loaded / e.total) * 100;
                        progressFill.style.width = percentComplete + '%';
                        statusText.innerText = `Uploading ${file.name}... ${Math.round(percentComplete)}%`;
                    }
                };
                
                xhr.onload = function() {
                    if (xhr.status === 200) {
                        resolve(xhr.responseText);
                    } else {
                        reject(new Error(xhr.statusText));
                    }
                };
                
                xhr.onerror = function() {
                    reject(new Error("Network Error"));
                };
                
                xhr.send(file);
            });
        }

        function toggleDropdown(id) {
            document.querySelectorAll('.dropdown').forEach(d => {
                if(d.id !== 'drop-' + id) d.classList.remove('show');
            });
            document.getElementById('drop-' + id).classList.toggle('show');
        }

        document.addEventListener('click', (e) => {
            if (!e.target.closest('.action-group')) {
                document.querySelectorAll('.dropdown').forEach(d => d.classList.remove('show'));
            }
        });

        async function deleteFile(encodedName) {
            const fileName = decodeURIComponent(encodedName);
            if (!confirm('Are you sure you want to delete "' + fileName + '"?')) return;
            try {
                const res = await fetch('/delete', {
                    method: 'POST',
                    headers: { 'X-File-Name': encodedName }
                });
                if (res.ok) {
                    window.location.reload();
                } else {
                    alert('Failed to delete file.');
                }
            } catch(e) {
                alert('Error: ' + e);
            }
        }
    </script>
</body>
</html>
'@

function Get-MimeType($extension) {
    switch ($extension.ToLower()) {
        ".html" { return "text/html" }
        ".css" { return "text/css" }
        ".js" { return "application/javascript" }
        ".png" { return "image/png" }
        ".jpg" { return "image/jpeg" }
        ".jpeg" { return "image/jpeg" }
        ".gif" { return "image/gif" }
        ".svg" { return "image/svg+xml" }
        ".pdf" { return "application/pdf" }
        ".txt" { return "text/plain" }
        ".zip" { return "application/zip" }
        ".json" { return "application/json" }
        ".mp3" { return "audio/mpeg" }
        ".mp4" { return "video/mp4" }
        default { return "application/octet-stream" }
    }
}

function Send-Response($stream, $statusCode, $statusText, $contentType, $bodyBytes) {
    $headerString = "HTTP/1.1 $statusCode $statusText`r`n"
    $headerString += "Access-Control-Allow-Origin: *`r`n"
    if ($null -ne $contentType) { $headerString += "Content-Type: $contentType`r`n" }
    if ($null -ne $bodyBytes) { $headerString += "Content-Length: $($bodyBytes.Length)`r`n" }
    $headerString += "Connection: close`r`n`r`n"
    $headerBytesOut = [System.Text.Encoding]::UTF8.GetBytes($headerString)
    $stream.Write($headerBytesOut, 0, $headerBytesOut.Length)
    if ($null -ne $bodyBytes -and $bodyBytes.Length -gt 0) {
        $stream.Write($bodyBytes, 0, $bodyBytes.Length)
    }
}

# The Main Server Loop using raw TCP to bypass HTTP.sys limitations
while ($true) {
    if ($listener.Pending()) {
        $client = $null
        try {
            $client = $listener.AcceptTcpClient()
            $stream = $client.GetStream()
            
            $buffer = New-Object byte[] 65536
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -eq 0) { $client.Close(); continue }
            
            $headerString = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
            $headerEndIndex = $headerString.IndexOf("`r`n`r`n")
            if ($headerEndIndex -eq -1) { $client.Close(); continue }
            
            $headerTextOnly = $headerString.Substring(0, $headerEndIndex)
            $headerBytesLength = [System.Text.Encoding]::UTF8.GetBytes($headerTextOnly + "`r`n`r`n").Length
            
            $lines = $headerTextOnly -split "`r`n"
            $requestLine = $lines[0]
            if ($requestLine -notmatch "^([A-Z]+)\s+([^\s]+)\s+HTTP/") { $client.Close(); continue }
            
            $method = $matches[1]
            $urlPath = $matches[2]
            
            $headers = @{}
            for ($i = 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -match "^(.*?):\s*(.*)$") {
                    $headers[$matches[1]] = $matches[2]
                }
            }
            
            if ($method -eq "GET") {
                if ($urlPath -eq "/") {
                    $filesHtml = ""
                    $files = Get-ChildItem -Path $sharedFolder | Where-Object { -not $_.PSIsContainer } | Sort-Object LastWriteTime -Descending
                    
                    if ($files.Count -eq 0) {
                        $filesHtml = "<li class='file-item' style='justify-content:center;color:var(--text-muted);border:none;background:transparent;'>No files available yet. Drop some files here!</li>"
                    } else {
                        foreach ($file in $files) {
                            $encodedName = [uri]::EscapeDataString($file.Name)
                            $sizeVal = $file.Length
                            $sizeStr = ""
                            if ($sizeVal -gt 1MB) { $sizeStr = "$([math]::Round($sizeVal / 1MB, 2)) MB" }
                            elseif ($sizeVal -gt 1KB) { $sizeStr = "$([math]::Round($sizeVal / 1KB, 2)) KB" }
                            else { $sizeStr = "$sizeVal Bytes" }
                            
                            $date = $file.LastWriteTime.ToString("MMM dd, yyyy HH:mm")
                            $id = [guid]::NewGuid().ToString()
                            $filesHtml += @"
                            <li class='file-item'>
                                <div class='file-info'>
                                    <span class='file-name' title='$($file.Name)'>$($file.Name)</span>
                                    <span class='file-meta'>$sizeStr • $date</span>
                                </div>
                                <div class='action-group'>
                                    <a href='/download/$encodedName' class='download-btn' download>
                                        <span>&#128229;</span> Download
                                    </a>
                                    <button class='menu-btn' onclick='toggleDropdown("$id")'>&#8942;</button>
                                    <div class='dropdown' id='drop-$id'>
                                        <button class='dropdown-item' onclick='deleteFile("$encodedName")'>&#128465; Delete</button>
                                    </div>
                                </div>
                            </li>
"@
                        }
                    }
                    $finalHtml = $htmlTemplate -replace "<!-- FILES_PLACEHOLDER -->", $filesHtml
                    $finalHtml = $finalHtml -replace "<!-- IP_PLACEHOLDER -->", $ipAddress
                    $finalHtml = $finalHtml -replace "<!-- PORT_PLACEHOLDER -->", $Port
                    
                    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($finalHtml)
                    Send-Response -stream $stream -statusCode "200" -statusText "OK" -contentType "text/html" -bodyBytes $bodyBytes
                }
                elseif ($urlPath -match "^/download/(.+)$") {
                    $fileName = [uri]::UnescapeDataString($matches[1])
                    $filePath = Join-Path $sharedFolder $fileName
                    
                    if (Test-Path $filePath) {
                        $fileInfo = New-Object System.IO.FileInfo($filePath)
                        $fileSize = $fileInfo.Length
                        $contentType = Get-MimeType ([System.IO.Path]::GetExtension($fileName))
                        
                        $headerOut = "HTTP/1.1 200 OK`r`n"
                        $headerOut += "Access-Control-Allow-Origin: *`r`n"
                        $headerOut += "Content-Type: $contentType`r`n"
                        $headerOut += "Content-Length: $fileSize`r`n"
                        $headerOut += "Content-Disposition: attachment; filename=`"$fileName`"`r`n"
                        $headerOut += "Connection: close`r`n`r`n"
                        $headerBytesOut = [System.Text.Encoding]::UTF8.GetBytes($headerOut)
                        $stream.Write($headerBytesOut, 0, $headerBytesOut.Length)
                        
                        $fileStream = [System.IO.File]::OpenRead($filePath)
                        $outBuffer = New-Object byte[] 65536
                        while (($readOut = $fileStream.Read($outBuffer, 0, $outBuffer.Length)) -gt 0) {
                            $stream.Write($outBuffer, 0, $readOut)
                        }
                        $fileStream.Close()
                        Write-Host "[DOWNLOAD] Sent: $fileName" -ForegroundColor Cyan
                    } else {
                        Send-Response -stream $stream -statusCode "404" -statusText "Not Found" -contentType "text/plain" -bodyBytes ([System.Text.Encoding]::UTF8.GetBytes("File Not Found"))
                    }
                } else {
                    Send-Response -stream $stream -statusCode "404" -statusText "Not Found" -contentType "text/plain" -bodyBytes ([System.Text.Encoding]::UTF8.GetBytes("Not Found"))
                }
            }
            elseif ($method -eq "POST" -and $urlPath -eq "/delete") {
                $fileNameEncoded = $headers["X-File-Name"]
                if ([string]::IsNullOrEmpty($fileNameEncoded)) {
                    Send-Response -stream $stream -statusCode "400" -statusText "Bad Request" -contentType "text/plain" -bodyBytes ([System.Text.Encoding]::UTF8.GetBytes("Bad Request"))
                } else {
                    $fileName = [uri]::UnescapeDataString($fileNameEncoded)
                    $fileName = [System.IO.Path]::GetFileName($fileName)
                    $filePath = Join-Path $sharedFolder $fileName
                    if (Test-Path $filePath) {
                        Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
                        Send-Response -stream $stream -statusCode "200" -statusText "OK" -contentType "text/plain" -bodyBytes ([System.Text.Encoding]::UTF8.GetBytes("OK"))
                        Write-Host "[DELETE] Removed: $fileName" -ForegroundColor DarkRed
                    } else {
                        Send-Response -stream $stream -statusCode "404" -statusText "Not Found" -contentType "text/plain" -bodyBytes ([System.Text.Encoding]::UTF8.GetBytes("Not Found"))
                    }
                }
            }
            elseif ($method -eq "POST" -and $urlPath -eq "/upload") {
                $fileNameEncoded = $headers["X-File-Name"]
                $contentLengthStr = $headers["Content-Length"]
                
                if ([string]::IsNullOrEmpty($fileNameEncoded) -or [string]::IsNullOrEmpty($contentLengthStr)) {
                    Send-Response -stream $stream -statusCode "400" -statusText "Bad Request" -contentType "text/plain" -bodyBytes ([System.Text.Encoding]::UTF8.GetBytes("Bad Request"))
                } else {
                    $contentLength = [int]$contentLengthStr
                    $fileName = [uri]::UnescapeDataString($fileNameEncoded)
                    $fileName = [System.IO.Path]::GetFileName($fileName)
                    $filePath = Join-Path $sharedFolder $fileName
                    
                    $fileStream = [System.IO.File]::Create($filePath)
                    $bodyBytesReadSoFar = $read - $headerBytesLength
                    if ($bodyBytesReadSoFar -gt 0) {
                        $fileStream.Write($buffer, $headerBytesLength, $bodyBytesReadSoFar)
                    }
                    
                    $totalRead = $bodyBytesReadSoFar
                    while ($totalRead -lt $contentLength) {
                        $bytesToRead = [math]::Min($buffer.Length, $contentLength - $totalRead)
                        if ($bytesToRead -le 0) { break }
                        $readBytes = $stream.Read($buffer, 0, $bytesToRead)
                        if ($readBytes -eq 0) { break }
                        $fileStream.Write($buffer, 0, $readBytes)
                        $totalRead += $readBytes
                    }
                    $fileStream.Close()
                    
                    Send-Response -stream $stream -statusCode "200" -statusText "OK" -contentType "text/plain" -bodyBytes ([System.Text.Encoding]::UTF8.GetBytes("OK"))
                    Write-Host "[UPLOAD] Received: $fileName" -ForegroundColor Green
                }
            } else {
                Send-Response -stream $stream -statusCode "405" -statusText "Method Not Allowed" -contentType "text/plain" -bodyBytes ([System.Text.Encoding]::UTF8.GetBytes("Method Not Allowed"))
            }
            
            $client.Close()
        } catch {
            if ($null -ne $client) { $client.Close() }
        }
    } else {
        Start-Sleep -Milliseconds 50
    }
}
} finally {
    if ($null -ne $listener) {
        $listener.Stop()
    }
}

#Requires -Version 5.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$CachePath = Join-Path -Path $env:APPDATA -ChildPath "Get-Download\PRIVATE"
$YtDlpExe = Join-Path -Path $CachePath -ChildPath "yt-dlp.exe"
$YtDlpDownloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
$ModulePath = $PSScriptRoot
$GitHubRawUrl = "https://raw.githubusercontent.com/Goodwintek/Get-Download/main"
$script:InstanceId = [guid]::NewGuid().ToString("N")

function Write-Log {
    param([string]$Text)
    if ($script:logBox) {
        $script:logBox.AppendText($Text + [Environment]::NewLine)
    } else {
        Write-Host $Text
    }
}

function Initialize-YtDlp {
    if (Test-Path -Path $YtDlpExe -PathType Leaf) {
        return $true
    }

    if (-not (Test-Path -Path $CachePath -PathType Container)) {
        New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
    }

    try {
        Write-Log "Downloading yt-dlp.exe..."
        Invoke-WebRequest -Uri $YtDlpDownloadUrl -OutFile $YtDlpExe -ErrorAction Stop
        Write-Log "yt-dlp.exe downloaded successfully."
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to download yt-dlp.exe: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
}

function Update-GetDownload {
    [CmdletBinding()]
    param()

    $result = [System.Windows.Forms.MessageBox]::Show("This will update Get-Download module and yt-dlp. Continue?", "Update", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    try {
        Write-Log "Updating Get-Download module..."

        $psd1Url = "$GitHubRawUrl/Get-Download.psd1"
        $psm1Url = "$GitHubRawUrl/Get-Download.psm1"
        $psd1Path = Join-Path -Path $ModulePath -ChildPath "Get-Download.psd1"
        $psm1Path = Join-Path -Path $ModulePath -ChildPath "Get-Download.psm1"

        Invoke-WebRequest -Uri $psd1Url -OutFile $psd1Path -ErrorAction Stop
        Invoke-WebRequest -Uri $psm1Url -OutFile $psm1Path -ErrorAction Stop

        Write-Log "Module updated successfully."

        if (Test-Path -Path $YtDlpExe -PathType Leaf) {
            Write-Log "Updating yt-dlp.exe..."
            & $YtDlpExe -U | Out-Null
            Write-Log "yt-dlp.exe updated successfully."
        }

        [System.Windows.Forms.MessageBox]::Show("Update complete. Application will restart.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

        $global:RestartApp = $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Update failed: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Write-Log "Update error: $_"
    }
}

function Get-YtDlpArgs {
    param(
        [string]$OutputDir,
        [string]$Url,
        [string]$FileName,
        [bool]$AudioOnly,
        [bool]$SslFix,
        [bool]$FfmpegHls
    )

    if ($FileName) {
        $template = "$OutputDir\$FileName.%(ext)s"
    } else {
        $template = "$OutputDir\%(title)s.%(ext)s"
    }

    $argString = "--output `"$template`" --embed-metadata"

    if ($FileName) {
        $argString += ' --replace-in-metadata title "^.*$" "' + $FileName + '"'
    }
    if ($Url -notmatch '\.m3u8') {
        $argString += " --download-archive `"$OutputDir\.yt-dlp-archive.txt`""
    }
    if ($FfmpegHls) {
        $argString += " --merge-output-format mp4 --downloader m3u8:ffmpeg --downloader-args `"ffmpeg:-protocol_whitelist file,http,https,tcp,tls,crypto`""
    }
    if ($AudioOnly) { $argString += " -x" }
    if ($SslFix) { $argString += " --legacy-server-connect --no-check-certificate" }
    $argString += " `"$Url`""

    return $argString
}

function Read-NewText {
    param(
        [string]$Path,
        [ref]$Position
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return ""
    }

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $stream.Position = $Position.Value
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        $Position.Value = $stream.Position
        return $text
    } finally {
        $stream.Dispose()
    }
}

function Start-YtDlpAttempt {
    $attempt = $script:attempts[$script:attemptIndex]
    $argString = Get-YtDlpArgs -OutputDir $script:runOutputDir -Url $script:runUrl -FileName $script:runFileName -AudioOnly $script:runAudio -SslFix $attempt.Ssl -FfmpegHls $attempt.Ffmpeg

    Write-Log "Attempt [$($attempt.Label)]: $YtDlpExe $argString"
    $script:statusLabel.Text = "Running: $($attempt.Label)"

    $env:PYTHONIOENCODING = "utf-8"
    $script:outFile = Join-Path -Path $CachePath -ChildPath "$($script:InstanceId)-stdout.log"
    $script:errFile = Join-Path -Path $CachePath -ChildPath "$($script:InstanceId)-stderr.log"
    $script:outPos = 0
    $script:errPos = 0

    $script:proc = Start-Process -FilePath $YtDlpExe -ArgumentList $argString -NoNewWindow -PassThru -RedirectStandardOutput $script:outFile -RedirectStandardError $script:errFile
    $script:timer.Start()
}

function Flush-YtDlpOutput {
    $text = Read-NewText -Path $script:outFile -Position ([ref]$script:outPos)
    $text += Read-NewText -Path $script:errFile -Position ([ref]$script:errPos)
    if ($text) {
        $script:logBox.AppendText($text)
    }
}

function Finish-Run {
    param([string]$Status)
    $script:downloadButton.Enabled = $true
    $script:statusLabel.Text = $Status
    Remove-Item -Path $script:outFile, $script:errFile -ErrorAction SilentlyContinue
}

function Get-Download {
    [CmdletBinding()]
    param(
        [string]$DefaultOutputPath = "",
        [switch]$U
    )

    if ($U) {
        Update-GetDownload
        return
    }

    if (-not (Initialize-YtDlp)) {
        return
    }

    if (-not (Test-Path -Path $YtDlpExe -PathType Leaf)) {
        throw "yt-dlp.exe not found at: $YtDlpExe"
    }

    do {
        $global:RestartApp = $false

        $form = New-Object System.Windows.Forms.Form
        $form.Text = "Get-Download"
        $form.Width = 400
        $form.Height = 500
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

        $menuStrip = New-Object System.Windows.Forms.MenuStrip
        $helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem
        $helpMenu.Text = "Help"
        $updateItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $updateItem.Text = "Check for Updates"
        $updateItem.Add_Click({ Update-GetDownload })
        $helpMenu.DropDownItems.Add($updateItem) | Out-Null
        $menuStrip.Items.Add($helpMenu) | Out-Null
        $form.Controls.Add($menuStrip)
        $form.MainMenuStrip = $menuStrip

        $urlLabel = New-Object System.Windows.Forms.Label
        $urlLabel.Location = New-Object System.Drawing.Point(10, 35)
        $urlLabel.AutoSize = $true
        $urlLabel.Text = "Playlist URL:"
        $form.Controls.Add($urlLabel)

        $script:urlTextBox = New-Object System.Windows.Forms.TextBox
        $script:urlTextBox.Location = New-Object System.Drawing.Point(100, 32)
        $script:urlTextBox.Width = 245
        $script:urlTextBox.Add_KeyDown({
            if ($_.Control -and $_.KeyCode -eq [System.Windows.Forms.Keys]::A) {
                $script:urlTextBox.SelectAll()
                $_.SuppressKeyPress = $true
            }
        })
        $script:urlTextBox.Add_DoubleClick({
            $script:urlTextBox.SelectAll()
        })
        $form.Controls.Add($script:urlTextBox)

        $clearUrlButton = New-Object System.Windows.Forms.Button
        $clearUrlButton.Location = New-Object System.Drawing.Point(350, 30)
        $clearUrlButton.Width = 30
        $clearUrlButton.Height = 22
        $clearUrlButton.Text = "X"
        $clearUrlButton.Add_Click({
            $script:urlTextBox.Clear()
            $script:urlTextBox.Focus()
        })
        $form.Controls.Add($clearUrlButton)

        $script:audioOnlyCheckBox = New-Object System.Windows.Forms.CheckBox
        $script:audioOnlyCheckBox.Location = New-Object System.Drawing.Point(10, 70)
        $script:audioOnlyCheckBox.AutoSize = $true
        $script:audioOnlyCheckBox.Text = "Extract Audio Only (-x)"
        $form.Controls.Add($script:audioOnlyCheckBox)

        $outputLabel = New-Object System.Windows.Forms.Label
        $outputLabel.Location = New-Object System.Drawing.Point(10, 100)
        $outputLabel.AutoSize = $true
        $outputLabel.Text = "Output Folder:"
        $form.Controls.Add($outputLabel)

        $script:outputTextBox = New-Object System.Windows.Forms.TextBox
        $script:outputTextBox.Location = New-Object System.Drawing.Point(100, 97)
        $script:outputTextBox.Width = 200
        if ($DefaultOutputPath) {
            $script:outputTextBox.Text = $DefaultOutputPath
        }
        $form.Controls.Add($script:outputTextBox)

        $browseButton = New-Object System.Windows.Forms.Button
        $browseButton.Location = New-Object System.Drawing.Point(305, 95)
        $browseButton.Text = "Browse"
        $browseButton.Add_Click({
            $folderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $folderBrowserDialog.Description = "Select the output folder"
            if (-not [string]::IsNullOrEmpty($script:outputTextBox.Text) -and (Test-Path $script:outputTextBox.Text)) {
                $folderBrowserDialog.SelectedPath = $script:outputTextBox.Text
            }
            if ($folderBrowserDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $script:outputTextBox.Text = $folderBrowserDialog.SelectedPath
            }
        })
        $form.Controls.Add($browseButton)

        $fileLabel = New-Object System.Windows.Forms.Label
        $fileLabel.Location = New-Object System.Drawing.Point(10, 130)
        $fileLabel.AutoSize = $true
        $fileLabel.Text = "File Name:"
        $form.Controls.Add($fileLabel)

        $script:fileTextBox = New-Object System.Windows.Forms.TextBox
        $script:fileTextBox.Location = New-Object System.Drawing.Point(100, 127)
        $script:fileTextBox.Width = 245
        $form.Controls.Add($script:fileTextBox)

        $script:downloadButton = New-Object System.Windows.Forms.Button
        $script:downloadButton.Location = New-Object System.Drawing.Point(150, 165)
        $script:downloadButton.Text = "Download"
        $script:downloadButton.Add_Click({
            $script:runUrl = $script:urlTextBox.Text
            $script:runOutputDir = $script:outputTextBox.Text
            $script:runFileName = $script:fileTextBox.Text.Trim() -replace '[\\/:*?"<>|]', ''
            $script:runAudio = $script:audioOnlyCheckBox.Checked

            if ([string]::IsNullOrEmpty($script:runUrl) -or [string]::IsNullOrEmpty($script:runOutputDir)) {
                [System.Windows.Forms.MessageBox]::Show("Please enter a URL and select an output folder.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            if (-not (Test-Path $script:runOutputDir)) {
                try {
                    New-Item -ItemType Directory -Path $script:runOutputDir -Force | Out-Null
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Could not create folder: $($script:runOutputDir)`n$($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
            }

            if ($script:proc -and -not $script:proc.HasExited) {
                Write-Log "A download is already running."
                return
            }

            $script:attempts = @(
                @{ Label = "Standard";       Ssl = $false; Ffmpeg = $false }
                @{ Label = "SSL fix";        Ssl = $true;  Ffmpeg = $false }
                @{ Label = "HLS via ffmpeg"; Ssl = $false; Ffmpeg = $true }
                #@{ Label = "SSL + HLS";     Ssl = $true;  Ffmpeg = $true }
            )
            $script:attemptIndex = 0
            $script:logBox.Clear()
            $script:downloadButton.Enabled = $false
            Start-YtDlpAttempt
        })
        $form.Controls.Add($script:downloadButton)

        $script:logBox = New-Object System.Windows.Forms.TextBox
        $script:logBox.Multiline = $true
        $script:logBox.ReadOnly = $true
        $script:logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        $script:logBox.Font = New-Object System.Drawing.Font("Consolas", 8)
        $script:logBox.Location = New-Object System.Drawing.Point(10, 200)
        $script:logBox.Size = New-Object System.Drawing.Size(365, 220)
        $form.Controls.Add($script:logBox)

        $script:statusLabel = New-Object System.Windows.Forms.Label
        $script:statusLabel.Location = New-Object System.Drawing.Point(10, 425)
        $script:statusLabel.Size = New-Object System.Drawing.Size(365, 24)
        $script:statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $script:statusLabel.Text = "Ready"
        $form.Controls.Add($script:statusLabel)

        $script:timer = New-Object System.Windows.Forms.Timer
        $script:timer.Interval = 300
        $script:timer.Add_Tick({
            Flush-YtDlpOutput
            if ($script:proc -and $script:proc.HasExited) {
                $script:timer.Stop()
                Flush-YtDlpOutput
                $attempt = $script:attempts[$script:attemptIndex]
                $exitCode = $script:proc.ExitCode

                if ($exitCode -eq 0) {
                    Write-Log "Download completed successfully."
                    Finish-Run "Completed"
                    [System.Windows.Forms.MessageBox]::Show("Download completed successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    return
                }

                Write-Log "[$($attempt.Label)] exited with code $exitCode."
                $script:attemptIndex++

                if ($script:attemptIndex -lt $script:attempts.Count) {
                    Start-YtDlpAttempt
                } else {
                    Write-Log "All attempts failed."
                    Finish-Run "Failed - see log"
                    [System.Windows.Forms.MessageBox]::Show("All attempts failed. Check the log for details.", "yt-dlp error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                }
            }
        })

        $form.Add_FormClosed({ $script:timer.Stop() })

        $form.ShowDialog() | Out-Null
        $form.Dispose()

        if ($global:RestartApp) {
            Remove-Module Get-Download -Force
            Import-Module (Join-Path -Path $ModulePath -ChildPath "Get-Download.psd1") -Force
            Get-Download
            return
        }
    } while ($global:RestartApp)
}

Export-ModuleMember -Function Get-Download, Update-GetDownload
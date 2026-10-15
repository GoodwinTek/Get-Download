#Requires -Version 5.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$CachePath = Join-Path -Path $env:APPDATA -ChildPath "Get-Download\PRIVATE"
$YtDlpExe = Join-Path -Path $CachePath -ChildPath "yt-dlp.exe"
$YtDlpDownloadUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
$ModulePath = $PSScriptRoot
$GitHubRawUrl = "https://raw.githubusercontent.com/Goodwintek/Get-Download/main"

function Initialize-YtDlp {
    if (Test-Path -Path $YtDlpExe -PathType Leaf) {
        return $true
    }

    if (-not (Test-Path -Path $CachePath -PathType Container)) {
        New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
    }

    try {
        Write-Host "Downloading yt-dlp.exe..."
        Invoke-WebRequest -Uri $YtDlpDownloadUrl -OutFile $YtDlpExe -ErrorAction Stop
        Write-Host "yt-dlp.exe downloaded successfully."
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
        Write-Host "Updating Get-Download module..."

        $psd1Url = "$GitHubRawUrl/Get-Download.psd1"
        $psm1Url = "$GitHubRawUrl/Get-Download.psm1"
        $psd1Path = Join-Path -Path $ModulePath -ChildPath "Get-Download.psd1"
        $psm1Path = Join-Path -Path $ModulePath -ChildPath "Get-Download.psm1"

        Invoke-WebRequest -Uri $psd1Url -OutFile $psd1Path -ErrorAction Stop
        Invoke-WebRequest -Uri $psm1Url -OutFile $psm1Path -ErrorAction Stop

        Write-Host "Module updated successfully."

        if (Test-Path -Path $YtDlpExe -PathType Leaf) {
            Write-Host "Updating yt-dlp.exe..."
            & $YtDlpExe -U | Out-Null
            Write-Host "yt-dlp.exe updated successfully."
        }

        [System.Windows.Forms.MessageBox]::Show("Update complete. Application will restart.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

        $global:RestartApp = $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Update failed: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Write-Host "Update error: $_"
    }
}

function Get-YtDlpArgs {
    param(
        [string]$OutputDir,
        [string]$Url,
        [bool]$AudioOnly,
        [bool]$SslFix,
        [bool]$FfmpegHls,
        [bool]$BotFix
    )

    $template = "$OutputDir\%(title)s.%(ext)s"
    $argString = "--output `"$template`" --embed-metadata"

    if ($FfmpegHls) {
        $argString += " --merge-output-format mp4 --downloader m3u8:ffmpeg --downloader-args `"ffmpeg:-protocol_whitelist file,http,https,tcp,tls,crypto`""
    }
    if ($AudioOnly) { $argString += " -x" }
    if ($SslFix) { $argString += " --legacy-server-connect --no-check-certificate" }
    if ($BotFix) { $argString += " --extractor-args `"generic:impersonate`"" }
    $argString += " `"$Url`""

    return $argString
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
        $form.Height = 210
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

        $audioOnlyCheckBox = New-Object System.Windows.Forms.CheckBox
        $audioOnlyCheckBox.Location = New-Object System.Drawing.Point(10, 70)
        $audioOnlyCheckBox.AutoSize = $true
        $audioOnlyCheckBox.Text = "Extract Audio Only (-x)"
        $form.Controls.Add($audioOnlyCheckBox)

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

        $downloadButton = New-Object System.Windows.Forms.Button
        $downloadButton.Location = New-Object System.Drawing.Point(150, 140)
        $downloadButton.Text = "Download"
        $downloadButton.Add_Click({
            $url = $script:urlTextBox.Text
            $outputDir = $script:outputTextBox.Text
            $audioOnly = $audioOnlyCheckBox.Checked

            if ([string]::IsNullOrEmpty($url) -or [string]::IsNullOrEmpty($outputDir)) {
                [System.Windows.Forms.MessageBox]::Show("Please enter a URL and select an output folder.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            if (-not (Test-Path $outputDir)) {
                try {
                    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Could not create folder: $outputDir`n$($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    return
                }
            }

            # Each attempt is independent: base arguments plus one option set, tried in order
            $attempts = @(
                @{ Label = "Standard";      Ssl = $false; Ffmpeg = $false; BotFix = $false }
                @{ Label = "SSL fix";       Ssl = $true;  Ffmpeg = $false; BotFix = $false }
                @{ Label = "HLS via ffmpeg"; Ssl = $false; Ffmpeg = $true; BotFix = $false }
                @{ Label = "Bot fix";        Ssl = $false; Ffmpeg = $false; BotFix = $true }
                #@{ Label = "SSL + HLS";     Ssl = $true;  Ffmpeg = $true; BotFix = $false }
            )

                        foreach ($attempt in $attempts) {
                $argString = Get-YtDlpArgs -OutputDir $outputDir -Url $url -AudioOnly $audioOnly -SslFix $attempt.Ssl -FfmpegHls $attempt.Ffmpeg -BotFix $attempt.BotFix

                Write-Host "Attempt [$($attempt.Label)]: $YtDlpExe $argString"

                $proc = Start-Process -FilePath $YtDlpExe -ArgumentList $argString -NoNewWindow -Wait -PassThru
                $exitCode = $proc.ExitCode

                if ($exitCode -eq 0) {
                    Write-Host "Download completed successfully."
                    [System.Windows.Forms.MessageBox]::Show("Download completed successfully!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    return
                }
                Write-Host "[$($attempt.Label)] exited with code $exitCode. Trying next option..."
                    }
                
                    [System.Windows.Forms.MessageBox]::Show("All attempts failed. Check the console for details.", "yt-dlp error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                })
                $form.Controls.Add($downloadButton)
            
                $form.ShowDialog() | Out-Null
                $form.Dispose()
            
                if ($global:RestartApp) {
                    Remove-Module Get-Download -Force
                    Import-Module (Join-Path -Path $ModulePath -ChildPath "Get-Download.psd1") -Force
                    Get-Download
                    return
                }
            } while ($global:RestartApp)
        
            Write-Host ""
        }

Export-ModuleMember -Function Get-Download, Update-GetDownload
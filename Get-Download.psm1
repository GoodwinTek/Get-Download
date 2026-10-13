Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ModuleRoot = $PSScriptRoot
$YtDlpExe = Join-Path -Path $ModuleRoot -ChildPath "PRIVATE\yt-dlp.exe"

function Get-Content {
    [CmdletBinding()]
    param(
        [string]$DefaultOutputPath = ""
    )

    if (-not (Test-Path -Path $YtDlpExe -PathType Leaf)) {
        throw "yt-dlp.exe not found at: $YtDlpExe"
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "yt-dlp Downloader"
    $form.Width = 400
    $form.Height = 255
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

    $urlLabel = New-Object System.Windows.Forms.Label
    $urlLabel.Location = New-Object System.Drawing.Point(10, 15)
    $urlLabel.AutoSize = $true
    $urlLabel.Text = "Playlist URL:"
    $form.Controls.Add($urlLabel)

    $script:urlTextBox = New-Object System.Windows.Forms.TextBox
    $script:urlTextBox.Location = New-Object System.Drawing.Point(100, 12)
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
    $clearUrlButton.Location = New-Object System.Drawing.Point(350, 10)
    $clearUrlButton.Width = 30
    $clearUrlButton.Height = 22
    $clearUrlButton.Text = "X"
    $clearUrlButton.Add_Click({
        $script:urlTextBox.Clear()
        $script:urlTextBox.Focus()
    })
    $form.Controls.Add($clearUrlButton)

    $audioOnlyCheckBox = New-Object System.Windows.Forms.CheckBox
    $audioOnlyCheckBox.Location = New-Object System.Drawing.Point(10, 50)
    $audioOnlyCheckBox.AutoSize = $true
    $audioOnlyCheckBox.Text = "Extract Audio Only (-x)"
    $form.Controls.Add($audioOnlyCheckBox)

    $sslFixCheckBox = New-Object System.Windows.Forms.CheckBox
    $sslFixCheckBox.Location = New-Object System.Drawing.Point(10, 75)
    $sslFixCheckBox.AutoSize = $true
    $sslFixCheckBox.Text = "SSL Error Fix (legacy TLS + skip cert check)"
    $form.Controls.Add($sslFixCheckBox)

    $ffmpegHlsCheckBox = New-Object System.Windows.Forms.CheckBox
    $ffmpegHlsCheckBox.Location = New-Object System.Drawing.Point(10, 100)
    $ffmpegHlsCheckBox.AutoSize = $true
    $ffmpegHlsCheckBox.Text = "HLS via ffmpeg (fixes CDN m3u8 SSL/stream errors)"
    $form.Controls.Add($ffmpegHlsCheckBox)

    $outputLabel = New-Object System.Windows.Forms.Label
    $outputLabel.Location = New-Object System.Drawing.Point(10, 135)
    $outputLabel.AutoSize = $true
    $outputLabel.Text = "Output Folder:"
    $form.Controls.Add($outputLabel)

    $script:outputTextBox = New-Object System.Windows.Forms.TextBox
    $script:outputTextBox.Location = New-Object System.Drawing.Point(100, 132)
    $script:outputTextBox.Width = 200
    if ($DefaultOutputPath) {
        $script:outputTextBox.Text = $DefaultOutputPath
    }
    $form.Controls.Add($script:outputTextBox)

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Location = New-Object System.Drawing.Point(305, 130)
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
    $downloadButton.Location = New-Object System.Drawing.Point(150, 170)
    $downloadButton.Text = "Download"
    $downloadButton.Add_Click({
        $url = $script:urlTextBox.Text
        $outputDir = $script:outputTextBox.Text
        $audioOnly = $audioOnlyCheckBox.Checked
        $sslFix = $sslFixCheckBox.Checked
        $ffmpegHls = $ffmpegHlsCheckBox.Checked

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

        if ($ffmpegHls) {
            $argString = "--output `"$outputDir\%(title)s.%(ext)s`" --merge-output-format mp4"
        } else {
            $argString = "--output `"$outputDir\%(title)s.%(ext)s`" --embed-metadata"
        }
        if ($audioOnly) { $argString += " -x" }
        if ($sslFix) { $argString += " --legacy-server-connect --no-check-certificate" }
        if ($ffmpegHls) { $argString += " --downloader m3u8:ffmpeg --downloader-args `"ffmpeg:-protocol_whitelist file,http,https,tcp,tls,crypto`"" }
        $argString += " `"$url`""

        Write-Host "Running: $YtDlpExe $argString"

        try {
            $proc = & (Get-Command Start-Process) -FilePath $YtDlpExe -ArgumentList $argString -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Host "Download completed."
                [System.Windows.Forms.MessageBox]::Show("Download completed!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                Write-Host "yt-dlp exited with code $($proc.ExitCode)."
                [System.Windows.Forms.MessageBox]::Show("yt-dlp exited with code $($proc.ExitCode). Check the console for details.", "yt-dlp error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to run yt-dlp: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $form.Controls.Add($downloadButton)

    $form.ShowDialog() | Out-Null
    Write-Host ""
}

Export-ModuleMember -Function Get-Content
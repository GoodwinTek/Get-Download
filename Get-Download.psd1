@{
    RootModule        = 'Get-Download.psm1'
    ModuleVersion     = '1.0.5'
    GUID              = '3a7f9c2e-1b4d-4f8a-9e6c-2d5a8b1c4f7e'
    Author            = 'Dave'
    Description       = 'yt-dlp GUI downloader with embedded executable'
    PowerShellVersion = '5.0'
    FunctionsToExport = @(
        'Get-Download'
    )
    PrivateData = @{
    PSData = @{
        ProjectUri = 'https://github.com/Goodwintek/Get-Download'
        Tags       = @('yt-dlp', 'youtube', 'download', 'GUI')
        }
    }
}

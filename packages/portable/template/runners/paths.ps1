# Shared setup validation. No changes are made by these functions.
function Get-AgentOSLocalPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[a-zA-Z]:[\\/]') {
        throw 'Use an absolute local drive path, for example C:\AgentOS. Network and relative paths are not supported for automated setup.'
    }
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if($full.IndexOfAny([char[]]'[]*?') -ge 0) { throw 'Use a folder path without brackets, asterisks or question marks. Spaces are supported.' }
    if ($full.Length -le 2) { throw 'Choose a dedicated folder, not a drive root.' }
    # Check every existing ancestor: lexical containment alone misses junctions.
    $item=$full
    while ($item) {
        if (Test-Path -LiteralPath $item) {
            if ((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Setup paths must not contain junctions or symbolic links. Choose an ordinary local folder.'
            }
        }
        $item=Split-Path $item -Parent
    }
    return $full
}
function Assert-AgentOSSeparatePaths([string]$Workspace,[string]$Ledger) {
    if ($Workspace.Equals($Ledger,[StringComparison]::OrdinalIgnoreCase) -or
        $Ledger.StartsWith($Workspace+'\',[StringComparison]::OrdinalIgnoreCase) -or
        $Workspace.StartsWith($Ledger+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Workspace and ledger must be separate folders; neither may contain the other.'
    }
}
function Assert-AgentOSBinary([string]$Path) {
    if (![IO.Path]::IsPathRooted($Path) -or !(Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.Path]::GetExtension($Path) -ine '.exe') {
        throw 'Supply absolute paths to actual CLI .exe binaries, not npm .cmd or .ps1 shims.'
    }
}

#
# Modulmanifest für das Modul "MediaWiki"
#
# Generiert von: Serpen
#
# Generiert am: 13.03.2015
#

@{

# Die diesem Manifest zugeordnete Skript- oder Binärmoduldatei.
RootModule = 'MediaWiki.psm1'

# Die Versionsnummer dieses Moduls
ModuleVersion = '1.2'

# ID zur eindeutigen Kennzeichnung dieses Moduls
GUID = 'edb173dd-a344-42fd-bdc4-d0a345dac2e8'

# Autor dieses Moduls
Author = 'Serpen'

# Beschreibung der von diesem Modul bereitgestellten Funktionen
Description = 'Mediawiki API for Powershell'

# Die für dieses Modul mindestens erforderliche Version des Windows PowerShell-Moduls
PowerShellVersion = '3.0'

# Die Module, die vor dem Importieren dieses Moduls in die globale Umgebung geladen werden müssen
RequiredModules = @('microsoft.powershell.security')

# Aus diesem Modul zu exportierende Funktionen
FunctionsToExport = 'Add-PageText', 'Connect-Site', 'Disconnect-Site', 'Find-Pages', 'Format-PageContentHTML', 'Get-AllPages', 'Get-CategoryPages', 'Get-FileInfo', 'Get-LinksHere', 'Get-PageCategories', 'Get-PageContent', 'Get-PageLinks', 'Get-PageList', 'Get-PageRevisions', 'Get-PageTemplates', 'Get-RecentChanges', 'Get-TranscludedIn', 'Import-File', 'Invoke-Query', 'Move-Page', 'New-Page', 'Protect-Page', 'Remove-Page', 'Set-Page', 'Test-Page'

# Aus diesem Modul zu exportierende Cmdlets
CmdletsToExport = 'Add-PageText', 'Connect-Site', 'Disconnect-Site', 'Find-Pages', 'Format-PageContentHTML', 'Get-AllPages', 'Get-CategoryPages', 'Get-FileInfo', 'Get-LinksHere', 'Get-PageCategories', 'Get-PageContent', 'Get-PageLinks', 'Get-PageList', 'Get-PageRevisions', 'Get-PageTemplates', 'Get-RecentChanges', 'Get-TranscludedIn', 'Import-File', 'Invoke-Query', 'Move-Page', 'New-Page', 'Protect-Page', 'Remove-Page', 'Set-Page', 'Test-Page'

# Die aus diesem Modul zu exportierenden Variablen
#VariablesToExport = '*'

# Aus diesem Modul zu exportierende Aliase
# AliasesToExport = '*'

# Standardpräfix für Befehle, die aus diesem Modul exportiert werden. Das Standardpräfix kann mit "Import-Module -Prefix" überschrieben werden.
DefaultCommandPrefix = 'MW'

}


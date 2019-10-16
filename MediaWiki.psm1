Add-Type -AssemblyName System.Web

Set-StrictMode -Version Latest

Set-Variable -Name MW_Format -Value 'format=json' -Option ReadOnly -Visibility Private -ea SilentlyContinue
Set-Variable -Name MW_Limit -Value 10 -ea SilentlyContinue


Set-Variable -Name MW_UploadBoundary -Value ([guid]::NewGuid().ToString()) -Option ReadOnly -Visibility Private -ea SilentlyContinue
Set-Variable -Name MW_MimeMap -Value @{png='image/png';jpg='image/jpeg';pdf='application/pdf';gif='image/gif'} -ea SilentlyContinue

Set-Variable -Name MW_TimeStampFormat -Value 'yyyymmddhhMMss' -Option ReadOnly -Visibility Private -ea SilentlyContinue

#region "internals"

function Convert-MWUrl([Parameter(Mandatory=$true)][AllowEmptyString()][string]$url)
{
    return [System.Web.HttpUtility]::UrlEncode($url)
}

function ConvertFrom-MWJsonRequest {
	param ($Inputobject)
	write-Verbose $Inputobject[0].Content
	if ($Inputobject[0].Content.Chars(0) -ne '{') {
		ConvertFrom-Json $Inputobject[0].Content.subString(1)
	} else {
		ConvertFrom-Json $Inputobject[0].Content
	} #endif
} #end function ConvertFrom-MWJsonRequest

function Test-MWError {
	param ($json)
	
	($json | Get-Member -Name error) -ne $null

}

function Invoke-MWQuery {
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true )][Alias("Properties")] [hashtable]$GetProperties,
    [Parameter(Mandatory=$false )][hashtable]$PostProperties
)

    $uri = "$($global:mw_site)?$MW_Format$(($GetProperties.GetEnumerator() | ForEach-Object {"&$($PSItem.key)=$(Convert-MWUrl $psitem.value)"}) -join '')"


    $body = @{}
    if ($PSBoundParameters.ContainsKey('PostProperties')) {
        #$body = New-Object hashtable -Property $PostProperties
        $PostProperties.GetEnumerator() | ForEach-Object {$body.("$($PSItem.key)")=$psitem.value}

        $object = Invoke-WebRequest -WebSession $global:mw_session -Uri $uri -Method Post -Body $body -Verbose:$false

    } else {
        $object = Invoke-WebRequest -WebSession $global:mw_session -Uri $uri -Verbose:$false
    }

	write-Verbose "Uri: '$uri'"#
	
    $json =  ConvertFrom-MWJsonRequest $object

    if (($json | Get-Member -Name Warnings) -ne $null) {
        write-warning ($json.warnings | Select-Object -expand * | Select-Object -exp *)
    }

    Write-Debug "Json Object $json"

    $json

} #end function Invoke-MWQuery


#endregion "internals"

#region "Connect"
<#
.Synopsis
   Anmelden an MediaWiki API
.EXAMPLE
   Connect-MWSite -site http://de.wikipedia.org/w/api.php -user bot -pass bot 
#>
function Connect-MWSite {
[CmdletBinding()]
param (
    [Parameter(Position=0,Mandatory=$true)][uri]$site,
    [Parameter(Mandatory=$true)][pscredential]$credential
)
    
    $username = $credential.UserName
    $BSTR = [System.Runtime.InteropServices.marshal]::SecureStringToBSTR($Credential.password)
    $password = [System.Runtime.InteropServices.marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.marshal]::ZeroFreeBSTR($BSTR)
    
    $uri = $site.AbsoluteUri + "?$MW_Format&action=query&meta=tokens&type=login"
    $object = Invoke-WebRequest $uri -Method Post -SessionVariable mw_session
    $json = ConvertFrom-MWJsonRequest $object

    #$uri = $site.AbsoluteUri + "?$MW_Format&action=login&lgname=" + (Convert-MWUrl($username))

    #if ($json.login.result -eq 'NeedToken') {
        $body = @{}
        $body.lgpassword = $password
        $body.lgtoken = $json.query.tokens.logintoken
        $uri = $site.AbsoluteUri + "?$MW_Format&action=login&lgname=" + (Convert-MWUrl($username)) #+ '&lgtoken=' + 
        $object = Invoke-WebRequest $uri -Method Post -WebSession $mw_session -Body $body
        $json = ConvertFrom-MWJsonRequest $object

    #}

    if($json.login.result -ne 'Success') {
        throw ('Login.result = ' + $json.login.result)
    } else {
        #$global:mw_user = $username
        $global:mw_site = $site.AbsoluteUri
        $global:mw_session = $mw_session
        $json = Invoke-MWQuery -Get @{action='query'; meta='tokens'}
        $global:mw_token = $json.query.tokens.csrftoken
    }
} #end function Connect-Site

<#
.Synopsis
   Abmelden an MediaWiki API
.EXAMPLE
   Disconnect-MWSite
#>
function Disconnect-Site {
    $json = Invoke-MWQuery -GetProperties @{action='logout'}
    $global:mw_session = $null
    $global:mw_site = $null
    #$mw_user = $null
    $global:mw_token = $null
} #end function

#endregion "connect"

#region "edit"
<#
.Synopsis
   Text zu Seite hinzufügen
.EXAMPLE
   Add-MWPageText -title Testseite -text 'Dies ist eine Testseite'
#>
function Add-MWPageText {
[CmdletBinding(SupportsShouldProcess=$true)]

param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$true )][string]$Text,
    [Parameter(Mandatory=$false )][int]$Section,
    [Parameter(Mandatory=$false)][string]$Summary,
	[Parameter(Mandatory=$false)][string[]]$Tags,
    [Parameter(Mandatory=$false )][switch]$Minor,
    [Parameter(Mandatory=$false )][switch]$Bot
)
    $get = @{action='edit'; title=$Title; nocreate=1}
    if ($PSBoundParameters.ContainsKey('Summary')) {
        $get.Add('summary', $Summary)
    }
	if ($PSBoundParameters.ContainsKey('Tags')) {
        $get.Add('tags', $tags -join '|')
    }
    if ($Minor) {
        $get.Add('minor',1)
    }
    if ($Bot) {
        $get.Add('bot',1)
    }
	if ($Section -ne -1) {
        $get.Add('section',$Section)
    }

    if ($PSCmdlet.ShouldProcess($Title, 'Add Text')) {
        $json = Invoke-MWQuery -GetProperties $get -PostProperties @{token=$global:mw_token;appendtext=$Text}

        if (Test-MWError $json) {
            Write-Error $json.error
        }
    }

    
} #end function Add-PageText

<#
.Synopsis
   Legt eine neue Seite an
.EXAMPLE
   New-MWPage -title Testseite -text 'Dies ist eine Testseite'
#>
function New-MWPage {
[CmdletBinding(SupportsShouldProcess=$true)]

param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$true )][string]$Text,
    [Parameter(Mandatory=$false)][string]$Summary,
    [Parameter(Mandatory=$false)][string[]]$Tags,
    [Parameter(Mandatory=$false )][switch]$Minor,
    [Parameter(Mandatory=$false )][switch]$Bot
)
    
    $get = @{action='edit'; title=$Title; createonly=1}
    if ($PSBoundParameters.ContainsKey('Summary')) {
        $get.Add('summary', $Summary)
    }
    if ($PSBoundParameters.ContainsKey('Tags')) {
        $get.Add('tags', $tags -join '|')
    }
    if ($Minor) {
        $get.Add('minor',1)
    }
    if ($Bot) {
        $get.Add('bot',1)
    }

    if ($PSCmdlet.ShouldProcess($Title, 'New Text')) {
        $json = Invoke-MWQuery -GetProperties $get -PostProperties @{token=$global:mw_token;text=$Text}

        if (Test-MWError $json) {
            Write-Error $json.error
        }
    }

    
} # end function New-MWPage


function Set-MWPage {
[CmdletBinding(SupportsShouldProcess=$true)]

param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$true )][string]$Text,
    [Parameter(Mandatory=$false)][string]$Summary,
    [Parameter(Mandatory=$false)][string[]]$Tags,
    [Parameter(Mandatory=$false )][switch]$Minor,
    [Parameter(Mandatory=$false )][switch]$Bot,
    [Parameter(Mandatory=$false )][int]$Section = -1
)
    $get = @{action='edit'; title=$Title; nocreate=1}
    if ($PSBoundParameters.ContainsKey('Summary')) {
        $get.Add('summary', $Summary)
    }
    if ($PSBoundParameters.ContainsKey('Tags')) {
        $get.Add('tags', $tags -join '|')
    }
    if ($Minor) {
        $get.Add('minor',1)
    }
    if ($Bot) {
        $get.Add('bot',1)
    }
	if ($Section -ne -1) {
        $get.Add('section',$section)
    }

    if ($PSCmdlet.ShouldProcess($Title, 'Set Page')) {
        $json = Invoke-MWQuery -GetProperties $get -PostProperties @{token=$global:mw_token;text=$Text}

        if (Test-MWError $json) {
            Write-Error $json.error
        }
    }

    
} #end function Set-MWPage

#endregion "edit"


<#
.Synopsis
   Fragt eine Seitenliste ab
.EXAMPLE
   Get-MWPageList -List BrokenRedirects -limit 15
#>
function Get-MWPageList {
param (
    [Parameter(Mandatory=$true)]
        [ValidateSet("Ancientpages", "BrokenRedirects", "Deadendpages", "DoubleRedirects", "ListDuplicatedFiles", "Listredirects", "Lonelypages", "Longpages", "MediaStatistics", "Mostcategories", "Mostimages", "Mostinterwikis", "Mostlinkedcategories", "Mostlinkedtemplates", "Mostlinked", "Mostrevisions", "Fewestrevisions", "Shortpages", "Uncategorizedcategories", "Uncategorizedpages", "Uncategorizedimages", "Uncategorizedtemplates", "Unusedcategories", "Unusedimages", "Wantedcategories", "Wantedfiles", "Wantedpages", "Wantedtemplates", "Unwatchedpages", "Unusedtemplates", "Withoutinterwiki", "Popularpages")]
        [string]$List,
    [int]$Offset = 0,
    [int]$Limit = $MW_Limit
)

	$get = @{action='query'; list='querypage'; qppage=$List; qplimit=$Limit; qpoffset=$Offset; continue=''}
	
    $json = Invoke-MWQuery -GetProperties $get

	if (Test-MWError $json) {
        Write-Error $json.error
    } else {
		$json.query.querypage.results
	}
}

<#
.Synopsis
   Gibt die Kategorien einer Seite aus
.EXAMPLE
   Get-MWPageCategories -Title Testseite
#>
function Get-MWPageCategories {
param (
	[Parameter(Mandatory=$true)][string]$Title,
	[int]$Limit = $MW_Limit
)
    $json = Invoke-MWQuery -GetProperties @{action='query'; prop='categories'; titles=$Title; cllimit=$Limit; continue=''}

    try {
        ($json.query.pages) | Get-Member -MemberType NoteProperty | ForEach-Object {$json.query.pages.$($_.name).categories.title} | ForEach-Object {New-Object PSOBject -Property ([ordered]@{Title=$Title; category=$_})}
    } catch {}
}

<#
.Synopsis
   Gibt alle Seiten aus einem Namensraus aus
.EXAMPLE
   #Alle Vorlagen
   Get-MWAllPages -ns 10 -limit 15
#>
function Get-MWAllPages {
param (
    [Parameter(Mandatory=$false)][string]$From,
    [Parameter(Mandatory=$false)][string]$To,
    [Parameter(Mandatory=$false)][Alias("ns")] [int]$Namespace = 0,
    [Parameter(Mandatory=$false)][int]$Limit = $MW_Limit,
    [Parameter(Mandatory=$false )][string][ValidateSet('all','redirects','nonredirects')]$FilterRedirects = 'all'
)
    
    $get = @{action='query'; list='allpages'; apnamespace=$Namespace; aplimit=$Limit; apfilterredir=$FilterRedirects;continue='' }

    if ($PSBoundParameters.ContainsKey('From')) {
        $get.Add('apfrom', $From)
    }
    if ($PSBoundParameters.ContainsKey('To')) {
        $get.Add('apto', $To)
    }

    $json = Invoke-MWQuery -GetProperties $get

    if (Test-MWError $json) {
        Write-Error $json.error
    } else {
        $json.query.allpages 
    }
}

<#
.Synopsis
   Gibt alle Seiten aus einer Kategorie aus
.EXAMPLE
   #Alle Vorlagen
   Get-MWCategoryPages -title Kategorie:Test
#>
function Get-MWCategoryPages {
param (
    [Parameter(Mandatory=$true )][string]$Category,
    [Parameter(Mandatory=$false )][string][ValidateSet('page','subcat','file')]$Type,
    [Parameter(Mandatory=$false )][int]$Limit = $MW_Limit,
    [Parameter(Mandatory=$false )][int]$Namespace = 0
)
	if (-not $Category.contains(':')) {
		$Category = "Category:$Category"
	}
	
	$get = @{action='query'; list='categorymembers'; cmtitle=$Category; cmlimit=$limit; cmnamespace=$Namespace; continue=''}
	
	if ($PSBoundParameters.ContainsKey('Type')) {
        $get.Add('cmtype', $Type -join '|')
    }
	
	
    $json = Invoke-MWQuery -GetProperties $get
	
	if (Test-MWError $json) {
        Write-Error $json.error
    } else {
		$json.query.categorymembers
	}
    
}

function Get-MWLinksHere {
param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$false )][int]$Limit = $MW_Limit
)
	
	$json = Invoke-MWQuery -GetProperties @{action='query'; prop='linkshere'; titles=$Title; lhlimit=$limit; continue=''}

    
	if (Test-MWError $json) {
        Write-Error $json.error
    } else {
        if (($json.query.pages | Get-Member -Name '-1') -eq $null) {
            ($json.query.pages | Select-Object -expand *).linkshere
        } else {
            Write-Warning "Page '$Title' does not exist"
        }
    }

}

function Get-MWTranscludedIn {
param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$false )][int]$Limit = $MW_Limit
)
	
	$json = Invoke-MWQuery -GetProperties @{action='query'; prop='transcludedin'; titles=$Title; tilimit=$Limit; continue=''}

    if (Test-MWError $json) {
        Write-Error $json.error
    } else {
        if ((($json.query.pages) | Get-Member '-1') -eq $null) {
            if ((($json.query.pages | Select-Object -ExpandProperty *) | Get-Member transcludedin) -ne $null) {
                ($json.query.pages | Select-Object -ExpandProperty *).transcludedin
            } else {
                Write-Warning "Page '$Title' ist not transcluded"
            }
        } else {
            Write-Warning "Page '$Title' doesn't exist"
        }
    }
}

<#
.Synopsis
   Gibt den Seiteninhalt aus
.EXAMPLE
   #Alle Vorlagen
   Get-MWPageContent -title Test
#>
function Get-MWPageContent {
param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$false )][int]$Section = -1

) 
	$get = @{action='parse'; page=$Title; contentmodel='wikitext'; prop='wikitext'}
	
    if ($section -ne -1) {
        $get.add("section",$Section)
    }
	
	$json = Invoke-MWQuery -GetProperties $get
	
	if (Test-MWError $json) {
        Write-Error $json.error
    } else {
		$json.parse.wikitext | Select-Object -ExpandProperty *
	}
}

function Format-MWPageContentHTML {
param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$false )][int]$Section = -1

) 
	$get = @{action='parse'; page=$Title;  prop='text'; disablepp=1; disableeditsection=0}
	
    if ($section -ne -1) {
        $get.add("section",$Section)
    }
	
	$json = Invoke-MWQuery -GetProperties $get
	
	if (Test-MWError $json) {
        Write-Error $json.error
    } else {
		$json.parse.text | Select-Object -ExpandProperty *
	}
}

function Find-MWPages {
param (
    [Parameter(Mandatory=$true )][string]$Text,
    [Parameter(Mandatory=$false )][switch]$Fulltext,
    [Parameter(Mandatory=$false )][int]$Limit = $MW_Limit
)
	$get = @{action='query'; list='search'; srsearch=$Text; srlimit=$Limit}
	
    if ($Fulltext) {
        $get.add("srwhat","text")
    }
	
	$json = Invoke-MWQuery -GetProperties $get
    
    #$json.query.searchinfo.totalhits

    $json.query.search
}

function Remove-MWPage {
[CmdletBinding(SupportsShouldProcess=$true)]

param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$false)][string]$Reason
)
    
    $get = @{action='delete'; title=$Title}
    if ($PSBoundParameters.ContainsKey('Reason')) {
        $get.Add('reason', $Reason)
    }

    if ($PSCmdlet.ShouldProcess($Title, 'Remove Page')) {
        $json = Invoke-MWQuery -GetProperties $get -PostProperties @{token=$global:mw_token}


        if (Test-MWError $json) {
            Write-Error $json.error
        }
    }

    
}


function Move-MWPage {
[CmdletBinding(SupportsShouldProcess=$true)]

param (
    [Parameter(Mandatory=$true )][string]$From,
    [Parameter(Mandatory=$true )][string]$To,
    [Parameter(Mandatory=$false)][string]$Reason,
    [Parameter(Mandatory=$false)][switch]$NoRedirect,
    [Parameter(Mandatory=$false)][switch]$MoveTalk,
    [Parameter(Mandatory=$false)][switch]$IgnoreWarnings
)
    
    $get = @{action='move'; from=$From; to=$To}
    if ($PSBoundParameters.ContainsKey('Reason')) {
        $get.Add('reason', $Reason)
    }
    if ($NoRedirect) {
        $get.Add('noredirect', 1)
    }
    if ($MoveTalk) {
        $get.Add('movetalk', 1)
    }
    if ($IgnoreWarnings) {
        $get.Add('ignorewarnings', 1)
    }

    if ($PSCmdlet.ShouldProcess($From, 'Move Page')) {
        $json = Invoke-MWQuery -GetProperties $get -PostProperties @{token=$global:mw_token}
    }

    if (Test-MWError $json) {
        Write-Error $json.error
    }
	
}

function Test-MWPage {
param ([Parameter(Mandatory=$true )][string]$Title)
    $json = Invoke-MWQuery -GetProperties @{action='query'; titles=$Title}
    
    ($json.query.pages | Get-Member -Name '-1') -eq $null
}

function Get-MWRecentChanges {
param (
    [Parameter(Mandatory=$false )][int]$Limit = $MW_Limit,
    [Parameter(Mandatory=$false )][string]$User,
    [Parameter(Mandatory=$false )][ValidateSet('edit','external','new','log')][string]$Type
)

    $get =  @{action='query'; list='recentchanges'; rclimit=$Limit; continue=''}

    if ($PSBoundParameters.ContainsKey('User')) {
        $get.Add('rcuser', $User)
    }
    if ($PSBoundParameters.ContainsKey('Type')) {
        $get.Add('rctype', $Type)
    }

    $json = Invoke-MWQuery -GetProperties $get
    
    $json.query.recentchanges
}

function Get-MWPageTemplates {
param (
    [Parameter(Mandatory=$false )][string]$Title,
    [Parameter(Mandatory=$false )][int]$Limit = $MW_Limit
)

	$json = Invoke-MWQuery -GetProperties @{action='query'; prop='templates'; titles=$Title; tllimit=$Limit}

    ($json.query.pages | Select-Object -ExpandProperty *).templates
}

function Get-MWPageLinks {
param (
    [Parameter(Mandatory=$false )][string]$Title,
    [Parameter(Mandatory=$false )][int]$Limit = $MW_Limit
)

	$json = Invoke-MWQuery -GetProperties @{action='query'; prop='links'; titles=$Title; pllimit=$Limit}

    ($json.query.pages | Select-Object -ExpandProperty *).links
}

function Get-MWFileInfo {
param (
    [Parameter(Mandatory=$false )][string]$Title
)

	if (-not $title.contains(':')) {
		$Title = "File:$Title"
	}
	$json = Invoke-MWQuery -GetProperties @{action='query'; prop='imageinfo'; titles=$Title; iiprop=('url','size','mime','mediatype','timestamp','user','comment','sha1','metadata') -join '|'}
	
    if (Test-MWError $json) {
        Write-Error $json.error
    } else {
        #Fehlerbild: $json.query.pages.'-1'
        if (($json.query.pages | Get-Member -Name -1) -eq $null) {
            ($json.query.pages | Select-Object -ExpandProperty *).imageinfo
        } else {
            Write-Warning  "Image '$Title' does not exist"
        }
    }
}

function Get-MWFileUsage {
param (
    [Parameter(Mandatory=$false )][string]$Title
)

	if (-not $title.contains(':')) {
		$Title = "File:$Title"
	}
	$json = Invoke-MWQuery -GetProperties @{action='query'; prop='fileusage'; titles=$Title; continue=''}
	
    if (Test-MWError $json) {
        Write-Error $json.error
    } else {
        #Fehlerbild: $json.query.pages.'-1'
        if (($json.query.pages | Get-Member -Name -1) -eq $null) {
            try {
                ($json.query.pages | Select-Object -ExpandProperty *).fileusage
            } catch {}
        } else {
            Write-Warning  "Image '$Title' does not exist"
        }
    }
}

function Import-MWFile {
[CmdletBinding(SupportsShouldProcess=$true)]

param (
    [Parameter(Mandatory=$true, ParameterSetName='Local')] [System.IO.FileInfo]$LocalFileName,
    [Parameter(Mandatory=$true ,ParameterSetName='Url')][uri]$url,
    [Parameter(Mandatory=$true )][String]$Name,
    [Parameter(Mandatory=$false)][String]$Comment,
    [Parameter(Mandatory=$false)][Switch]$IgnoreWarnings
)
    if ($PSCmdlet.ParameterSetName -eq 'Url') {
        $Get = [ordered]@{action='upload'; filename=$Name; url=$url}

        if ($IgnoreWarnings) {
            $get.add("ignorewarnings",1)
        }
        if (-not [String]::IsNullOrEmpty($Comment)) {
            $get.add("comment",$Comment)
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Import File')) {
            $json = Invoke-MWQuery -GetProperties $Get -PostProperties @{token=$global:mw_token}
        }

        if (Test-MWError $json) {
            Write-Error $json.error
        }

    } else { 
        #throw New-Object  System.NotImplementedException
        
        [System.Text.StringBuilder]$contents = New-Object System.Text.StringBuilder
        [String]$mime = ''
        [String]$tmpFile = [System.IO.Path]::GetTempFileName()

        [void]$contents.AppendLine("--$MW_UploadBoundary")

        [void]$contents.AppendLine("Content-Disposition: form-data; name=`"file`"; filename=`"$($LocalFileName.Name)`"")

        $mime = $MW_mimeMap[$LocalFileName.Extension.Substring(1)]
        if ($mime -eq '') {$mime = 'application/octet-stream'}
        [void]$contents.AppendLine("Content-Type: $mime" )

        [void]$contents.AppendLine()

        [void]$contents.AppendLine((Get-Content -raw $LocalFileName.FullName))

        [void]$contents.AppendLine("--$MW_UploadBoundary")
        [void]$contents.AppendLine("Content-Disposition: form-data; name=`"token`"")
        [void]$contents.AppendLine()
        [void]$contents.AppendLine($global:mw_token)
        
        [void]$contents.AppendLine("--$MW_UploadBoundary--")
        [void]$contents.AppendLine()

        Set-Content -Value $contents.ToString() -Path $tmpFile

        $uri = "$($global:mw_site)?action=upload&$mw_format&comment=$Comment&filename=$name"

        if ($IgnoreWarnings) {
            $uri += '&ignorewarnings=1'
        }
        
        if ($PSCmdlet.ShouldProcess($Name, 'Import File')) {

            $object = Invoke-WebRequest -Uri $uri -WebSession $global:mw_session -Method Post -ContentType "multipart/form-data; boundary=$MW_UploadBoundary"  -InFile $tmpFile # -Body $contents.ToString() 

            $json =  ConvertFrom-MWJsonRequest $object

            #Set-Content -Value $contents.ToString() -Path $tmpFile

            if (Test-MWError $json) {
                Write-Debug "Content: $($contents.ToString())"
                Write-Error $json.error
            }


            if (($json.upload | Get-Member -Name warnings) -ne $null) {
                if ($IgnoreWarnings) {
                    Write-Warning $json.upload.warnings
                } else {

                    Write-Error $json.upload.warnings
                }
            }
        }

        


        [void](Remove-Item $tmpFile -ErrorAction SilentlyContinue)
    } #end else
    $json
	
} #end function Import-File

function Get-MWPageRevisions {
param (
    [Parameter(Mandatory=$false )][string]$Title,
    [Parameter(Mandatory=$false )][int]$Limit = $MW_Limit

)
    $json = Invoke-MWQuery -GetProperties @{action='query'; prop='revisions'; titles=$Title; rvlimit=$Limit; continue='' }

    if (Test-MWError $json) {
            Write-Error $json.error
    } else {
        if (($json.query.pages | Get-Member -Name -1) -eq $null) {
            ($json.query.pages | Select-Object -ExpandProperty *).revisions
        } else {
            Write-Warning  "Page '$Title' does not exist"
        }
    }

}

function Protect-MWPage {
[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory=$true )][string]$Title,
    [Parameter(Mandatory=$false )][Switch]$Cascade,

    [Parameter(Mandatory=$false )][Switch]$Reason,

    [Parameter(Mandatory=$true )][String][ValidateSet("all", "autoconfirmed", "sysop")]$EditGroup,
    [Parameter(Mandatory=$true )][String]$EditExpiry,

    [Parameter(Mandatory=$false, ParameterSetName='SeperateMove' )][Switch]$SeparateMoveRights,

    [Parameter(Mandatory=$false, ParameterSetName='SeperateMove' )][String][ValidateSet("all", "autoconfirmed", "sysop")]$MoveGroup,
    [Parameter(Mandatory=$false, ParameterSetName='SeperateMove' )][String]$MoveExpiry

)
    $get = @{action='protect'; title=$Title}

    [datetime]$EditExpiryDate = [datetime]::MinValue
    if ($EditExpiry -notin 'infinite', 'indefinite', 'infinity' , 'never') {
        if ([datetime]::TryParse($EditExpiry, [ref]$EditExpiryDate)) {
            $EditExpiry = $EditExpiryDate.ToString($MW_TimeStampFormat)
        } else {
            Write-Error "Invalid Edit-Date $EditExpiry"
            return
        }
    }

    if ($Cascade) {
        $get.Add('cascade', 1)
    }
    if ($Reason -ne '') {
        $get.Add('reason', $Reason)
    }


    if (-not $SeparateMoveRights) {
        $get.Add('protections', "edit=$EditGroup|move=$EditGroup")
        $get.Add('expiry', "$EditExpiry|$EditExpiry")
    } else {
        
        [datetime]$MoveExpiryDate = [datetime]::MinValue
        if ($MoveExpiry -notin 'infinite', 'indefinite', 'infinity' , 'never') {
            if ([datetime]::TryParse($MoveExpiry, [ref]$MoveExpiryDate)) {
                $MoveExpiry = $MoveExpiryDate.ToString($MW_TimeStampFormat)
            } else {
                Write-Error "Invalid Move-Date $MoveExpiry"
                return
            }
        }

        $get.Add('protections', "edit=$EditGroup|move=$MoveGroup")
        $get.Add('expiry', "$EditExpiry|$MoveExpiry")
    }

    if ($PSCmdlet.ShouldProcess($Title, 'Protect Page')) {

        $json = Invoke-MWQuery -GetProperties $get -PostProperties @{token=$global:mw_token}
    }

    $json
	
} #function Protect-Page

function Get-MWSemanticQuery {
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, ParameterSetName='DirectQuery',Position=0)]  [string]$Query,
    [Parameter(Mandatory=$true, ParameterSetName='InDirectQuery')][hashtable]$Where,
    [Parameter(Mandatory=$false,ParameterSetName='InDirectQuery')][string[]]$Properties = "#",
    [Parameter(Mandatory=$false,ParameterSetName='InDirectQuery')][int]$Limit = -1
)
    
    $get = @{action='ask'}

    if ($PSCmdlet.ParameterSetName -eq 'DirectQuery') {
        $get.add('query', $Query)
    } else  {
        [string]$querystring = ""
        foreach ($criteria in $Where.GetEnumerator()) {
            $querystring += "[[$($criteria.name)::$($criteria.value)]]"
        }
        foreach ($prop in $Properties) {
            $querystring += "|?$prop"
        }

        if ($Limit -ne -1) {
            $querystring += "|limit=$limit"
        }
        $get.add('query', $querystring)
    }
    
    $json = Invoke-MWQuery -GetProperties $get

    if (Test-MWError $json) {
        Write-Error $json.error.query
    } else {
        if ($json.query.results -ne $null) {
            foreach ($entryname in ($json.query.results | Get-Member -Type NoteProperty | Select-Object -ExpandProperty Name)) {
                $props = [ordered]@{Name=$entryname}
                foreach ($propname in ($json.query.results."$entryname".printouts | Get-Member -Type NoteProperty -ea SilentlyContinue | Select-Object -ExpandProperty Name)) {
                    $props.add($propname, $json.query.results."$entryname".printouts.$propname -join ', ')        
                }
                $obj = New-Object PSObject -Property $props
                $obj.PSObject.TypeNames.Insert(0, 'FEK.Wiki.SemanticEntry') | Out-Null
                $obj
            }
        } else {
            Write-Warning $json.error
        }
    }
} #Query-MWSematics

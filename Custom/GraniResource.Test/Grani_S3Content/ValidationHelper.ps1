﻿#region Initialize

function Initialize
{
    # Enum for Item Type
    Add-Type -TypeDefinition @"
        public enum GraniDonwloadItemTypeEx
        {
            FileInfo,
            DirectoryInfo,
            Other,
            NotExists
        }
"@

    # Enum for Ensure
    Add-Type -TypeDefinition @"
        public enum GraniDonwloadEnsuretype
        {
            Present,
            Absent
        }
"@
}

Initialize

#endregion

#region Message Definition

$debugMessage = DATA {
    ConvertFrom-StringData -StringData "
        IsDestinationPathExist = Checking Destination Path is existing and Valid as a FileInfo
        IsDestinationPathAlreadyUpToDate = Matching FileHash to verify file is already exist/Up-To-Date or not.
        IsFileAlreadyUpToDate = CurrentFileHash : S3 FileHash -> {0} : {1}
        IsFileExists = File found from DestinationPath. Checking already up-to-date.
        IsS3ObjectExist = Testing S3 Object is exist or not.
        ItemTypeWasFile = Destination Path found as File : '{0}'
        ItemTypeWasDirectory = Destination Path found but was Directory : '{0}'
        ItemTypeWasOther = Destination Path found but was neither File nor Directory: '{0}'
        ItemTypeWasNotExists = Destination Path not found : '{0}'
        ValidateS3Bucket = Checking S3 Bucket '{0}' is exist.
        ValidateS3Object = Checking S3 Object Key '{0}' is exist.
        ValidateFilePath = Check DestinationPath '{0}' is FileInfo and Parent Directory already exist.
    "
}

$verboseMessage = DATA {
    ConvertFrom-StringData -StringData "
        alreadyUpToDate = Current DestinationPath FileHash and S3 FileHash matched. File already Up-To-Date.
        notUpToDate = Current DestinationPath FileHash and S3 FileHash not matched. Need to download latest file.
    "
}
$exceptionMessage = DATA {
    ConvertFrom-StringData -StringData "
        DestinationPathAlreadyExistAsNotFile = Destination Path '{0}' already exist but not a file. Found itemType is {1}. Windows not allowed exist same name item.
        S3BucketNotExistEXception = Desired S3 Bucket not found exception. : '{0}'
        S3ObjectNotExistEXception = Desired S3 Object not found in S3Bucket exception. : '{0}'
    "
}

#endregion

#region *-TargetResource

function Get-TargetResource
{
    [OutputType([System.Collections.Hashtable])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$S3BucketName,

        [parameter(Mandatory = $false)]
        [System.String]$Key,

        [parameter(Mandatory = $true)]
        [System.String]$DestinationPath
    )


    # validate S3 Bucket is exist
    ValidateS3Bucket -BucketName $S3BucketName
    ValidateS3Object -BucketName $S3BucketName -Key $Key

    # Initialize return values
    # Header and OAuth2Token will never return as TypeConversion problem
    $returnHash = 
    @{
        S3BucketName = $S3BucketName
        Key = $Key
        DestinationPath = $DestinationPath
        Ensure = [GraniDonwloadEnsuretype]::Absent.ToString()
    }

    # Destination Path check
    Write-Debug -Message $debugMessage.IsDestinationPathExist
    $itemType = GetPathItemType -Path $DestinationPath

    $fileExists = $false
    switch ($itemType.ToString())
    {
        ([GraniDonwloadItemTypeEx]::FileInfo.ToString())
        {
            Write-Debug -Message ($debugMessage.ItemTypeWasFile -f $DestinationPath)
            $fileExists = $true
        }
        ([GraniDonwloadItemTypeEx]::DirectoryInfo.ToString())
        {
            Write-Debug -Message ($debugMessage.ItemTypeWasDirectory -f $DestinationPath)
        }
        ([GraniDonwloadItemTypeEx]::Other.ToString())
        {
            Write-Debug -Message ($debugMessage.ItemTypeWasOther -f $DestinationPath)
        }
        ([GraniDonwloadItemTypeEx]::NotExists.ToString())
        {
            Write-Debug -Message ($debugMessage.ItemTypeWasNotExists -f $DestinationPath)
        }
    }

    # Already Up-to-date Check
    Write-Debug -Message $debugMessage.IsDestinationPathAlreadyUpToDate
    if ($fileExists -eq $true)
    {
        Write-Debug -Message $debugMessage.IsFileExists
        $currentFileHash = GetFileHash -Path $DestinationPath
        $s3ObjectCache = GetS3ObjectHash -BucketName $S3BucketName -Key $Key

        Write-Debug -Message ($debugMessage.IsFileAlreadyUpToDate -f $currentFileHash, $s3ObjectCache)
        if ($currentFileHash -eq $s3ObjectCache)
        {
            Write-Verbose -Message $verboseMessage.alreadyUpToDate
            $returnHash.Ensure = [GraniDonwloadEnsuretype]::Present.ToString()
        }
        else
        {
            Write-Verbose -Message $verboseMessage.notUpToDate
        }
    }

    return $returnHash
}


function Set-TargetResource
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$S3BucketName,

        [parameter(Mandatory = $false)]
        [System.String]$Key,

        [parameter(Mandatory = $true)]
        [System.String]$DestinationPath
    )

    # validate S3 Bucket is exist
    ValidateS3Bucket -BucketName $S3BucketName
    ValidateS3Object -BucketName $S3BucketName -Key $Key

    # validate DestinationPath is valid
    ValidateFilePath -Path $DestinationPath

    # Start Download
    Read-S3Object -BucketName $S3BucketName -Key $Key -File $DestinationPath
}


function Test-TargetResource
{
    [OutputType([System.Boolean])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$S3BucketName,

        [parameter(Mandatory = $false)]
        [System.String]$Key,

        [parameter(Mandatory = $true)]
        [System.String]$DestinationPath
    )

    $param = @{
        S3BucketName = $S3BucketName
        Key = $Key
        DestinationPath = $DestinationPath
    }
    return (Get-TargetResource @param).Ensure -eq [GraniDonwloadEnsuretype]::Present.ToString()
}


#endregion

#region S3 Helper

function TestS3Object
{
    [OutputType([Boolean])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [string]$BucketName,

        [parameter(Mandatory = $true)]
        [string]$Key
    )
    
    Write-Debug -Message ($debugMessage.IsS3ObjectExist)
    $objects = Get-S3Object -BucketName $BucketName

    $result = $null
    $dic = New-Object "System.Collections.Generic.Dictionary[[string], [string]]"
    $objects | %{ $dic.Add($_.Key, $_.Etag) }
    return $dic.TryGetValue($Key, [ref]$result)
}

#endregion

#region Validation Helper

function ValidateS3Bucket
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [string]$BucketName
    )

    Write-Debug -Message ($debugMessage.ValidateS3Bucket -f $BucketName)
    if (-not (Test-S3Bucket -BucketName $BucketName))
    {
        throw New-Object System.NullReferenceException ($exceptionMessage.S3BucketNotExistEXception -f $BucketName)
    }
}

function ValidateS3Object
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [string]$BucketName,

        [parameter(Mandatory = $true)]
        [string]$Key
    )

    Write-Debug -Message ($debugMessage.ValidateS3Object -f $Key)
    if (-not (TestS3Object -BucketName $BucketName -Key $Key))
    {
        throw New-Object System.NullReferenceException ($exceptionMessage.S3ObjectNotExistEXception -f $S3Object)
    }
}

function ValidateFilePath
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [string]$Path
    )
    
    Write-Debug -Message ($debugMessage.ValidateFilePath -f $Path)
    $itemType = GetPathItemType -Path $Path
    switch ($itemType.ToString())
    {
        ([GraniDonwloadItemTypeEx]::FileInfo.ToString())
        {
            return;
        }
        ([GraniDonwloadItemTypeEx]::NotExists.ToString())
        {
            # Create Parent Directory check
            $parentPath = Split-Path $Path -Parent
            if (-not (Test-Path -Path $parentPath))
            {
                [System.IO.Directory]::CreateDirectory($parentPath) > $null
            }
        }
        Default
        {
            $errorId = "FileValudationFailure"
            $errorMessage = $exceptionMessage.DestinationPathAlreadyExistAsNotFile -f $Path, $itemType.ToString()
            ThrowInvalidDataException -ErrorId $errorId -ErrorMessage $errorMessage
        }
    }

}

#endregion

#region Hash Helper

function GetFileHash
{
    [OutputType([string])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -Path $Path -Algorithm MD5).Hash
}

function GetS3ObjectHash
{
    [OutputType([string])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [string]$BucketName,

        [parameter(Mandatory = $true)]
        [string]$Key
    )

    return (Get-S3Object -BucketName $BucketName -Key $Key).ETag.Replace('"', "")
}

#endregion

#region ItemType Helper

function GetPathItemType
{
    [OutputType([GraniDonwloadItemTypeEx])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("FullName", "LiteralPath", "PSPath")]
        [System.String]$Path = [string]::Empty
    )

    $type = [string]::Empty

    # Check type of the Path Item
    if (-not (Test-Path -Path $Path))
    {
        return [GraniDonwloadItemTypeEx]::NotExists
    }
    
    $pathItem = Get-Item -Path $path
    $pathItemType = $pathItem.GetType().FullName
    $type = switch ($pathItemType)
    {
        "System.IO.FileInfo"
        {
            [GraniDonwloadItemTypeEx]::FileInfo
        }
        "System.IO.DirectoryInfo"
        {
            [GraniDonwloadItemTypeEx]::DirectoryInfo
        }
        Default
        {
            [GraniDonwloadItemTypeEx]::Other
        }
    }

    return $type
}

#endregion

#region Exception Helper

function ThrowInvalidDataException
{
    [OutputType([Void])]
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]$ErrorId,

        [parameter(Mandatory = $true)]
        [System.String]$ErrorMessage
    )
    
    $errorCategory = [System.Management.Automation.ErrorCategory]::InvalidData
    $exception = New-Object System.InvalidOperationException $ErrorMessage 
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $ErrorId, $errorCategory, $null
    throw $errorRecord
}

#endregion
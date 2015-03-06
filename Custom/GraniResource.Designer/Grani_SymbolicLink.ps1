Import-Module xDSCResourceDesigner
$property = @()
$property += New-xDscResourceProperty `
    -Name DestinationPath `
    -Type String `
    -Attribute Key `
    -Description "Symbolic Link path."
$property += New-xDscResourceProperty `
    -Name SourcePath `
    -Type String `
    -Attribute Required `
    -Description "Symbolic Link source path"
$property += New-xDscResourceProperty `
    -Name Ensure `
    -Type String `
    -Attribute Required `
    -Description "Ensure Symbolic Link is Present or Absent." `
    -ValidateSet Present, Absent
$property += New-xDscResourceProperty `
    -Name ForceFile `
    -Type Boolean `
    -Attribute Write `
    -Description "Force create File Symbolic Link even if source path is not exist."
$property += New-xDscResourceProperty `
    -Name ForceFolder `
    -Type Boolean `
    -Attribute Write `
    -Description "Force create Folder Symbolic Link even if source path is not exist."

New-xDscResource -Name Grani_SimbolicLink -Property $property -Path .\ -ModuleName GraniResource -FriendlyName cSymbolicLink -Force
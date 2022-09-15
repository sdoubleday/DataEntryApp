
<#
Dotnet webapp razorpages development setup
#>
<#
PARAM(
     [String]$WebAppName
    ,[String]$DatabaseName
    ,[String]$DirectoryOfCsvFiles = '.\Documents\csv'
)
#>
[String]$WebAppName = 'MyWebApp';
[String]$DatabaseName = 'DataEntryDB'
[String]$DirectoryOfCsvFiles = '.\Documents\csv'
$CrudSchema = $WebAppName + "Schema";

New-Item -ItemType Directory $DirectoryOfCsvFiles -Force | Out-Null; #Paste csv file here
New-Item -ItemType File $DirectoryOfCsvFiles\sampleTable.csv | Add-Content -Encoding UTF8 -Value "col1,col2,col3`r`n1234,qwer,asdf`r`nfdsa,rewq,4321";
New-Item -ItemType File $DirectoryOfCsvFiles\exampleTable.csv | Add-Content -Encoding UTF8 -Value "colA,colB,colC`r`nZ1234,Zqwer,Zasdf`r`nYfdsa,Yrewq,Y4321";

#region PowerShell and Package Managers
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force;

Write-Verbose -Verbose 'Add empty powershell profile...';
#Create an empty powershell profile if none already exists
if(-not $(test-path $profile)) {new-item -ItemType File -Path $profile -Force};

Write-Verbose -Verbose 'Start with package managers...';
#Install Chocolatey Package Manager for Windows
Set-ExecutionPolicy Bypass -Scope Process -Force;
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'));
. $profile;

#Microsoft dev VMs need VS's package manager fixed. Name and source:
Register-PackageSource -Name "nuget.org" -Location "https://api.nuget.org/v3/index.json" -ProviderName NuGet -Force;
#endregion PowerShell and Package Managers

Write-Verbose -Verbose 'Install commandline git...';
choco install git -y;

Write-Verbose -Verbose 'Install vscode...';
choco install vscode -y;

Write-Verbose -Verbose 'Install dotnet core...';
choco install dotnetcore -y;

Write-Verbose -Verbose 'Install dotnet sdk...';
choco install dotnet-sdk --version=5.0.406 -y;

Write-Verbose -Verbose 'Install dbatools...';
choco install dbatools -y;

#refresh the environment after package installation
refreshenv;

Write-Verbose -Verbose 'Add nuget source...';
dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org

Write-Verbose -Verbose 'Install aspnet codegenerator...';
dotnet tool install --global dotnet-aspnet-codegenerator --version 5.0.0-*

Write-Verbose -Verbose 'Install dotnet-ef...';
dotnet tool install --global dotnet-ef --version 5.0.0-*

Write-Verbose -Verbose 'Install SQL Server 2019 Express Edition...';
choco install sql-server-express -y;

#refresh the environment after package installation
refreshenv;

#Create Database and Ingest CSV Files
Import-Module dbatools;
$SqlInstance = Find-DbaInstance -computerName .;
$db = New-DbaDatabase -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Name $DatabaseName -Owner 'sa';
Invoke-DbaQuery -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Database $db.Name -Query "CREATE SCHEMA [$CrudSchema] AUTHORIZATION [dbo];";
function Add-LocalDbaIdentityPrimaryKeyToTable {
<#
.SYNOPSIS
Pipe Import-DbaCsv to this to add an arbitrary IDENTITY PRIMARY KEY.
#>
#Cmdlet Binding Attributes
[CmdletBinding()]
PARAM
(
    
     [Parameter(Mandatory= $true,ValueFromPipelineByPropertyName= $true)][ValidateNotNullOrEmpty()][String]$SqlInstance
    ,[Parameter(Mandatory= $true,ValueFromPipelineByPropertyName= $true)][ValidateNotNullOrEmpty()][String]$Database
    ,[Parameter(Mandatory= $true,ValueFromPipelineByPropertyName= $true)][ValidateNotNullOrEmpty()][String]$Table
    ,[Parameter(Mandatory= $true,ValueFromPipelineByPropertyName= $true)][ValidateNotNullOrEmpty()][String]$Schema
)
BEGIN   {
    Import-Module dbatools;
}<# END BEGIN    #>
PROCESS {
    $query = @"
ALTER TABLE [$($Schema)].[$($Table)] ADD [$($Table)_Id] [INT] IDENTITY (1,1) NOT NULL PRIMARY KEY;
"@;
    Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database -Query $query;

}<# END PROCESS  #>
END     {}<# END END      #>
} <# END function Add-LocalDbaIdentityPrimaryKeyToTable #>

Get-ChildItem $DirectoryOfCsvFiles\*csv | Import-DbaCsv -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Database $db.Name -Schema $CrudSchema -AutoCreateTable | Add-LocalDbaIdentityPrimaryKeyToTable;

#Begin creating webapp

dotnet new webapp -o $WebAppName;
Set-Location .\$WebAppName;
dotnet add package Microsoft.EntityFrameworkCore.Design -v 5.0.0-*;
New-Item -ItemType Directory -Name Modules;
New-Item -ItemType Directory -Name Data;

dotnet add package Microsoft.EntityFrameworkCore.SqlServer -v 5.0.0-*;
dotnet add package Microsoft.EntityFrameworkCore.Tools -v 5.0.0-*;
dotnet add package Microsoft.VisualStudio.Web.CodeGeneration.Design -v 5.0.0-*;
dotnet add package Microsoft.AspNetCore.Diagnostics.EntityFrameworkCore -v 5.0.0-*;


<#
Possible validation: Confirm that all tables in scope have primary keys of one column and no rowversion (b/c I cannot yet get EF Core 5 to handle concurrency tokens like rowversion correctly without manual configuration).
#>

$relpath = ".\Modules\$CrudSchema";
$relpath_Pages = ".\Pages\$CrudSchema";
$connectionString = New-DbaConnectionString -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Database $db.Name -ConnectTimeout:$null -PacketSize:$null -ClientName:$null ;

New-Item -ItemType Directory -Path $relpath -Force | Out-Null;
New-Item -ItemType Directory -Path $relpath_Pages -Force | Out-Null;

dotnet ef dbcontext scaffold $connectionString Microsoft.EntityFrameworkCore.SqlServer -o $relpath --context-dir .\Data\ --data-annotations --schema $CrudSchema;

#Scaffold first, THEN get the context file
$projname = Split-Path -Leaf $PWD.Path;
$dbcontextname = $(Get-ChildItem ".\Data\*Context.cs")[0].BaseName; #SO FRAGILE. V2 TODO make this an optional parameter. Maybe use a script param validation list to offer up whatever dbcontexts are available? Though, frankly, limiting to just one does lean into the whole "script this and move on" approach.
$qualifiedDbContextName = $projname + '.Data.' + $dbcontextname;
$namespaceTrunk = $projname + '.Pages.' + $CrudSchema;
#Explanation: You need to change the namespace from the unpluralized version because otherwise the .cshtml.cs code tries to refernce the un-qualified class name, which collides with its unqualified namespace. Changing the namespace at generator time is easier than getting the generator to fully qualify its use of the class.

$htmlListOfPages = "";
Get-ChildItem $relpath | ForEach-Object {
    dotnet aspnet-codegenerator razorpage -m $($_.BaseName) -dc $qualifiedDbContextName -udl -outDir "$($relpath_Pages)\$($_.BaseName)" –referenceScriptLibraries --namespaceName "$namespaceTrunk.$($_.BaseName)s" ;
    $htmlListOfPages = $htmlListOfPages + '<a class="navbar-brand" asp-page="/' + $CrudSchema + '/' + $_.BaseName + '/Index">' + $_.BaseName + '</a>' + "`r`n        ";
} <# END Get-ChildItem $relpath | ForEach-Object #>

#Update the startup cs code to connect to the database.
$startupcontent = Get-Content -Raw .\startup.cs;
Set-Content -Path .\startup.cs -Encoding UTF8 -Value $startupcontent.Replace('services.AddRazorPages();',"services.AddRazorPages();`r`n            services.AddDbContext<$qualifiedDbContextName>();");

#Update the home page with all the data entry pages.
$homecontent = Get-Content -Raw .\Pages\Index.cshtml;
Set-Content -Path .\Pages\Index.cshtml -Encoding UTF8 -Value $homecontent.Replace('<p>Learn about <a href="https://docs.microsoft.com/aspnet/core">building Web apps with ASP.NET Core</a>.</p>'
    ,$htmlListOfPages);

dotnet build;

dotnet publish --configuration Release;

#. .\bin\Release\net5.0\MyWebApp.exe
#### ... to start a debug version. It runs in the console, and echos a port. you can find the data entry interface at: localhost:5001/$CrudSchema/CsvFileNameNoExtension
#### and that's nice, and all, but we really need an actual landing page that has a list of the available data entry interfaces
#### and it needs to actually run somewhere. IIS? Kestrel?


#FIGURE OUT HOW TO TURN ON IIS AND DEPLOY THE WEBAPP TO IT
#THEN LAUNCH A BROWSER POINTED AT THE WEBAPP

#Turn on IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools;


#Deploy the webapp to the physical path where it will live
$dir = New-Item -ItemType Directory -Path C:\inetpub\wwwroot\$WebAppName;
Get-ChildItem .\bin\Release\net5.0\publish\ | Copy-Item -Recurse -Destination $dir;

#Grant the IIS service account access to the data entry database
New-DbaLogin -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Login 'IIS APPPOOL\DefaultAppPool';
New-DbaDbUser -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Login 'IIS APPPOOL\DefaultAppPool';
#Look, I didn't say this uses the principle of least permissions.
Add-DbaDbRoleMember -Database $DatabaseName -Role 'db_owner' -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -User 'IIS APPPOOL\DefaultAppPool' -confirm:$false;

#I think this is the right hosting bundle? Yes, I know it is 6.0, but it seems to be backwards compatible.
$url = 'https://download.visualstudio.microsoft.com/download/pr/eaa3eab9-cc21-44b5-a4e4-af31ee73b9fa/d8ad75d525dec0a30b52adc990796b11/dotnet-hosting-6.0.9-win.exe';
$file = 'outfile.exe';
Invoke-WebRequest -Uri $url -OutFile $file;
Start-Process -FilePath $file -Wait -ArgumentList "/quiet","/install";
net stop was /y;
net start w3svc;
Start-Process -FilePath $file -Wait -ArgumentList "/quiet","/repair"; #This seems to require a repair command, and I have no idea why.
net stop was /y;
net start w3svc;
# we maybe need 6.0.9? which may or may not be what comes from here? ANyway, it looks like this needs to be repaired by the above, for now.
#choco install dotnet-6.0-windowshosting -y;
#bouncing...
#net stop was /y;
#net start w3svc;

#At this point, either manually create the webapp in IIS Manager or proceed...

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;
#Point the IIS stuff at the file stuff to voila-make-a-webapp. Does that need me to be in the IIS provider? Or does it work from normal powershell?
#IIS:\> 
Install-Module IISAdministration;
Import-Module WebAdministration; #need that for the IIS: provider
#switch to IIS, make the webapp happen, then switch back to normal file system.
IIS:
New-Item "IIS:\Sites\Default Web Site\$WebAppName" -physicalPath "C:\inetpub\wwwroot\$WebAppName\" -type Application
C:

#Pretty sure that either the hosting bundle should get installed at this point or the install should work or SOMETHING but if we repair the installation after the creation of the webapp, that seems to work.

#Then launch a web browser
Start-Process msedge "localhost/$WebAppName";

#Leftovers

#Bits for hosting a dotnetcore webapp... maybe? Might need to bounce the service.
#choco install dotnetcore-windowshosting -y;
#bouncing...
#net stop was /y;
#net start w3svc;

#or maybe this?
#choco install dotnet-5.0-windowshosting -y;
#bouncing...
#net stop was /y;
#net start w3svc;


#Downloading and running this and then bouncing the service and deploying the app manually (Create a folder in c:\inetpub\wwwroot\ and then ls ...publish\ | copy -recurse to that folder) worked to make a functional webconfig but the data entry page threw an error (prolly need to turn on development mode:
# https://dotnet.microsoft.com/en-us/download/dotnet/thank-you/runtime-aspnetcore-6.0.9-windows-hosting-bundle-installer)



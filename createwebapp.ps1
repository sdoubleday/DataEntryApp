
#region one-time setup. Install packages, IIS, and SQL Server.

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

Register-PackageSource -Name "nuget.org" -Location "https://api.nuget.org/v3/index.json" -ProviderName NuGet -Force;

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

#Turn on IIS
Install-WindowsFeature -Name Web-Server -IncludeManagementTools;

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted;
#Point the IIS stuff at the file stuff to voila-make-a-webapp.
#IIS:\> 
Install-Module IISAdministration;
Import-Module WebAdministration; #need that for the IIS: provider

#I think this is the right hosting bundle? Yes, I know it is 6.0, but it seems to be backwards compatible.
$url = 'https://download.visualstudio.microsoft.com/download/pr/870aa66a-733e-45fa-aecb-27aaec423f40/833d0387587b9fb35e47e75f2cfe0288/dotnet-hosting-6.0.10-win.exe
';
$file = "$home\outfile.exe";
Invoke-WebRequest -Uri $url -OutFile $file;
Start-Process -FilePath $file -Wait -ArgumentList "/quiet","/install";
net stop was /y;
net start w3svc;

#endregion one-time setup. Install packages, IIS, and SQL Server.





#region Create Database (OR skip this and restore one, adding a login for the DefaultAppPool if you need to)
[String]$DatabaseName = 'DataEntryDB'
Import-Module dbatools;
$SqlInstance = Find-DbaInstance -computerName .;
$db = New-DbaDatabase -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Name $DatabaseName -Owner 'sa';

#Grant the IIS service account access to the data entry database
New-DbaLogin -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Login 'IIS APPPOOL\DefaultAppPool';
New-DbaDbUser -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Login 'IIS APPPOOL\DefaultAppPool';
#Look, I didn't say this uses the principle of least permissions.
Add-DbaDbRoleMember -Database $DatabaseName -Role 'db_owner' -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -User 'IIS APPPOOL\DefaultAppPool' -confirm:$false;
#endregion Create Database (OR skip this and restore one, adding a login for the DefaultAppPool if you need to)




#region Prepare the SQL Server tables for data entry app(s)
<#
    Option one - create a schema, create a few csv files, pump them into SQL Server in that schema, and add identity primary keys to them.
    Option two - create a schema, add tables with simple data types (strings, decimals, ints, dates, datetimes), tack on ID INT IDENTITY(1,1) NOT NULL PRIMARY KEY columns and RowVersion ROWVERSION NOT NULL columns.

NOTE you cannot have multiple dot net core apps per app pool. RIght now this is set up to create one per schema, so let's stick to one schema.
#>









#region OPTION ONE
[String]$WebAppName = 'SampleApp';
[String]$DirectoryOfCsvFiles = "$home\samplecsv\"
$CrudSchema = "Sample";

#region Inline setup of CSV files as sample tables

New-Item -ItemType Directory $DirectoryOfCsvFiles -Force | Out-Null; #Paste csv file here
New-Item -ItemType File $DirectoryOfCsvFiles\sampleTable.csv | Add-Content -Encoding UTF8 -Value "col1,col2,col3`r`n1234,qwer,asdf`r`nfdsa,rewq,4321";
New-Item -ItemType File $DirectoryOfCsvFiles\demoTable.csv | Add-Content -Encoding UTF8 -Value "colA,colB,colC`r`nZ1234,Zqwer,Zasdf`r`nYfdsa,Yrewq,Y4321";

#endregion Inline setup of CSV files as sample tables

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

#endregion OPTION ONE

#region OPTION TWO

<#
You are going to need to do this one yourself, but maybe something like...
#> 
#Invoke-DbaQuery -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Database $db.Name -Query "CREATE SCHEMA [$CrudSchema] AUTHORIZATION [dbo];";
Invoke-DbaQuery -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Database $db.Name -Query "CREATE TABLE [$CrudSchema].[example] (
    [example_Id] [INT] IDENTITY (1,1) NOT NULL PRIMARY KEY
    ,[A_Date] [DATE] NOT NULL
    ,[B_Decimal] [DECIMAL](19,10) NOT NULL
    ,[C_String] [VARCHAR](500) NOT NULL
);";
Invoke-DbaQuery -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Database $db.Name -Query "CREATE TABLE [$CrudSchema].[exampletwo] (
    [exampletwo_Id] [INT] IDENTITY (1,1) NOT NULL PRIMARY KEY
    ,[A_Date] [DATE] NOT NULL
    ,[B_Decimal] [DECIMAL](19,10) NOT NULL
    ,[C_String] [VARCHAR](500) NOT NULL
);";
#endregion OPTION TWO



#endregion Prepare the SQL Server tables for data entry app(s)




#region Build and deploy webapps
#Get schemas (in case we ever fix the app pool thing)
$schemas = @();
$schemas += $(Invoke-DbaQuery -SqlInstance "$($env:COMPUTERNAME)\$($SqlInstance.InstanceName)" -Database $db.Name -Query "SELECT name FROM sys.schemas WHERE name = '$CrudSchema'").name;
foreach ($schema in $schemas) {
#Begin creating webapp
[String]$WebAppName = $schema + 'App';
$CrudSchema = $schema;

dotnet new webapp -o $WebAppName;
Push-Location;
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

dotnet build;

dotnet ef dbcontext scaffold $connectionString Microsoft.EntityFrameworkCore.SqlServer -o $relpath --context-dir .\Data\ --data-annotations --schema $CrudSchema;

#Scaffold first, THEN get the context file
$projname = Split-Path -Leaf $PWD.Path;
$dbcontextname = $(Get-ChildItem ".\Data\*Context.cs")[0].BaseName; #SO FRAGILE. V2 TODO make this an optional parameter. Maybe use a script param validation list to offer up whatever dbcontexts are available? Though, frankly, limiting to just one does lean into the whole "script this and move on" approach.
$qualifiedDbContextName = $projname + '.Data.' + $dbcontextname;
$namespaceTrunk = $projname + '.Pages.' + $CrudSchema;
#Explanation: You need to change the namespace from the unpluralized version because otherwise the .cshtml.cs code tries to refernce the un-qualified class name, which collides with its unqualified namespace. Changing the namespace at generator time is easier than getting the generator to fully qualify its use of the class.

dotnet build;

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

#Deploy the webapp to the physical path where it will live
$dir = New-Item -ItemType Directory -Path C:\inetpub\wwwroot\$WebAppName;
Get-ChildItem .\bin\Release\net5.0\publish\ | Copy-Item -Recurse -Destination $dir;

#switch to IIS, make the webapp happen, then switch back to normal file system.
IIS:
New-Item "IIS:\Sites\Default Web Site\$WebAppName" -physicalPath "C:\inetpub\wwwroot\$WebAppName\" -type Application
C:

#Pretty sure that either the hosting bundle should get installed at this point or the install should work or SOMETHING but if we repair the installation after the creation of the webapp, that seems to work.

Pop-Location
}
#endregion Build and deploy webapps

#region Finally, repair the hosting bundle, since it seems to need it
Start-Process -FilePath $file -Wait -ArgumentList "/quiet","/repair"; #This seems to require a repair command, and I have no idea why.
net stop was /y;
net start w3svc;
#endregion Finally, repair the hosting bundle, since it seems to need it




#Then launch a web browser
Start-Process msedge "localhost/$WebAppName";

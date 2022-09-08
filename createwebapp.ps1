
<#
Dotnet webapp razorpages development setup
#>
PARAM(
     [String]$WebAppName
    ,[String]$DatabaseName
    ,[String]$DirectoryOfCsvFiles
)
$CrudSchema = $WebAppName;


#region PowerShell and Package Managers
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force;

Write-Verbose -Verbose 'Add empty powershell profile...';
#Create an empty powershell profile if none already exists
if(-not $(test-path $profile)) {new-item -ItemType File -Path $profile};

Write-Verbose -Verbose 'Start with package managers...';
#Install Chocolatey Package Manager for Windows
Set-ExecutionPolicy Bypass -Scope Process -Force;
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'));

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

Write-Verbose -Verbose 'Add nuget source...';
dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org

Write-Verbose -Verbose 'Install aspnet codegenerator...';
dotnet tool install --global dotnet-aspnet-codegenerator --version 5.0.0-*

Write-Verbose -Verbose 'Install dotnet-ef...';
dotnet tool install --global dotnet-ef --version 5.0.0-*

#refresh the environment after package installation
. $profile;
refreshenv;

#Create Database and Ingest CSV Files
Import-Module dbatools;
$SqlInstance = Find-DbaInstance -computerName .;

New-DbaDatabase -SqlInstance $SqlInstance -Name $DatabaseName -Owner 'sa';
#Sql command to create a schema with name $WebAppName;
#Sql command to create login for current user as part of $DatabaseName's db_owner role OR WHATEVER I NEED TO DO TO GET Import-DbaCsv working;

Get-ChildItem $DirectoryOfCsvFiles\*csv | Import-DbaCsv -SqlInstance $SqlInstance -Database $DatabaseName -AutoCreateTable;

#Begin creating webapp

dotnet new webapp -o $WebAppName;
Set-Location .\$WebAppName;
dotnet add package Microsoft.EntityFrameworkCore.Design -v 5.0.0-*;
New-Item -ItemType Directory -Name Modules;
New-Item -ItemType Directory -Name Data;

dotnet add package Microsoft.EntityFrameworkCore.SqlServer -v 5.0.0-*;
dotnet add package Microsoft.EntityFramework.Tools -v 5.0.0-*;
dotnet add package Microsoft.VisualStudio.Web.CodeGeneration.Design -v 5.0.0-*;
dotnet add package Microsoft.AspNetCore.Diagnostics.EntityFrameworkCore -v 5.0.0-*;


<#
Possible validation: Confirm that all tables in scope have primary keys of one column and no rowversion (b/c I cannot yet get EF Core 5 to handle concurrency tokens like rowversion correctly without manual configuration).
#>

$relpath = ".\Modules\$CrudSchema";
$relpath_Pages = ".\Pages\$CrudSchema";
$connectionString = New-DbaConnectionString -SqlInstance $SqlInstance -Database $DatabaseName -ConnectTimeout:$null -PacketSize:$null -ClientName:$null ;

New-Item -ItemType Directory -Path $relpath -Force | Out-Null;
New-Item -ItemType Directory -Path $relpath_Pages -Force | Out-Null;

dotnet ef dbcontext scaffold $connectionString Microsoft.EntityFrameworkCore.SqlServer -o $relpath --context-dir .\Data\ --data-annotations --schema $CrudSchema;

#Scaffold first, THEN get the context file
$projname = Split-Path -Leaf $PWD.Path;
$dbcontextname = $(Get-ChildItem ".\Data\*Context.cs")[0].BaseName; #SO FRAGILE. V2 TODO make this an optional parameter. Maybe use a script param validation list to offer up whatever dbcontexts are available? Though, frankly, limiting to just one does lean into the whole "script this and move on" approach.
$qualifiedDbContextName = $projname + '.Data.' + $dbcontextname;
$namespaceTrunk = $projname + '.Pages.' + $CrudSchema;
#Explanation: You need to change the namespace from the unpluralized version because otherwise the .cshtml.cs code tries to refernce the un-qualified class name, which collides with its unqualified namespace. Changing the namespace at generator time is easier than getting the generator to fully qualify its use of the class.

Get-ChildItem $relpath | ForEach-Object {
    dotnet aspnet-codegenerator razorpage -m $($_.BaseName) -dc $qualifiedDbContextName -udl -outDir "$($relpath_Pages)\$($_.BaseName)" –referenceScriptLibraries --namespaceName "$namespaceTrunk.$($_.BaseName)s" ;
} <# END Get-ChildItem $relpath | ForEach-Object #>


#FIGURE OUT HOW TO TURN ON IIS AND DEPLOY THE WEBAPP TO IT
#THEN LAUNCH A BROWSER POINTED AT THE WEBAPP

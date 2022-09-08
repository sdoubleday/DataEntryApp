

# Let's make a low-cost data entry platform with three commands.
1. Provision a VM and install SQL Server.
   - If your target is in Azure, there is a terraform script and instructions in the folder .\terraform that will deploy a SQL Express VM on a 2 core server (size B2ms) with a public IP. Alternatively, deploy without the public IP and join the VM to your network.
1. Upload CSV files to define and populate the data to be entered.
   - Copy and paste one or more csv file to the server in one directory.
1. Run the setup script
   - Copy and paste a script into PowerShell.
   - Provide the directory of the CSV files and the name of your webapp.
1. Review your work
   - The script will open your new webapp when it is done and you can take a look at what you have wrought.

## Description

Low-cost data entry platform.

- You want to let end users put data into a database with a webapp and you want to do it with the a minimal amount of work - it isn't supposed to be pretty, it isn't supposed to be high-performance, it isn't supposed to be cutting edge.
- You want the code to be something you can check into source control and regenerate as needed.

## Technical

- We will be using dotnet 5.0 and dotnetcore razor pages to scaffold and create Create-Read-Update-Delete (CRUD) webapp pages for all the tables you define through providing csv files.
- We will use SQL Server Express by default, but you could adapt this to use full versions of SQL Server if appropriate. 
- We will use the dbatools PowerShell module for interacting with SQL Server.
- We will host the web app on IIS.

# VSTS.EFMigrationsTasks
A build and release task to facilitate easy and secure execution of Entity Framework migrations during Release.
This project was originally forked from https://github.com/tobania/VSTS.Extension.EntityFrameworkMigrations and that project has an additional task to generate the migrations.  
I've added the ability to pass in the connection string without using a config file.  I didn't want to specify my production or uat passwords in source control, now I can use a VSTS variable and lock it.
I also added the ability to add firewall rules, though this is not generally needed.

**Copy Entity Framework migrate.exe**
- Copies the migrate.exe from your nuget packages into the build so it can be used by the Apply task in the Release.

**Apply Entity Framework migrations**
- Executes migrate.exe using the parameters you pass it.  Can use a connection string out of a configuration file, or you can specify the connection string.
- Allows for the manual or automatic addition of Firewall rules if you are using an Azure database.


The database icon I used is from Shmidt Sergey https://thenounproject.com/monstercritic/
---
title: "Provision an Azure VM in an Azure Pipelines Environment"
date: 2021-03-05T00:00:00+01:00
publishdate: 2021-03-05T00:00:00+01:00
lastmod: 2021-03-05T00:00:00+01:00
tags: [ "Azure", "Azure CLI", "Azure DevOps", "Azure Pipelines", "YAML" ]
summary: "To test a custom Azure Pipelines task of mine I created a YAML pipeline in Azure DevOps that automatically provisions an Azure virtual machine and registers the VM in an Azure Pipelines environment. In this blog post I'll show you how it works."
draft: true
---

In the past I've written the post [How to install .NET Core on a Windows server](https://ronaldbosma.github.io/blog/2020/05/07/how-to-install-.net-core-on-a-windows-server/) where I talked about a custom Azure Pipelines task that I've build. To test this task in an actual pipeline I used an Azure virtual machine that I created manually and kept around for this specific purpose. Everytime I wanted to test something I had to start the machine, test my task, log on to the server and check if .NET Core was installed successfully. If I wanted to test a clean install I had to uninstall .NET Core first. Which meant installing 3 different pieces of software for each supported .NET Core version.

As you can see, a lot of manual steps were involved. So I automated this. I've created a pipeline that:
1. Creates an Azure Pipelines environment in Azure DevOps.
1. Provisions a fresh virtual machine in Azure.
1. Registers the virtual machine in the Azure Pipelines environment.
1. Runs my custom task & verifies that the installation is successful.
1. Deletes the Azure Pipelines environment.
1. Deletes the Azure virtual machine.

In the rest of this post I'll explain how [this pipeline](https://github.com/ronaldbosma/blog-code-examples/blob/master/ProvisionAzureVMInAzurePipelinesEnvironment/provision-vm-in-environment-azure-pipeline.yml) works.

### Prerequisites

To make the pipeline work you'll need to create a Personal Access Token and an Azure Resource Manager service connection to connect to your Azure subscription.

#### Create Personal Access Token

Follow these steps to create a Personal Access Token (see [create a PAT](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page#create-a-pat) for more info):
1. Log in to you Azure DevOps organization and open your team project.
1. Open the user settings menu in the top right corner en choose 'Personal access tokens'.
1. Choose New Token.
1. Click the show all scopes link.
1. Give the token access to the scopes 'Environment (Read & manage)' and 'Tokens (read & manage)'.  
  ![User settings menu](../../../../../images/provision-azure-vm-in-azure-pipelines-environment/pat-scopes.png)
  <!-- ![User settings menu](../../static/images/provision-azure-vm-in-azure-pipelines-environment/pat-scopes.png) -->
1. Click on Create.
1. Copy the token so you can use it later on.

To 'Environment (Read & manage)' scope is required to register the virtual machine in the environment. The 'Tokens (read & manage)' scope is required to delete the environment at the end of the pipeline, which doesn't really seemed logical to me. But we're using the `az devops invoke` Azure CLI command which fails without this scope.

### Create Azure Resource Manager service connection

We're going to use the `AzureCLI` task in our pipeline which requires an Azure Resource Manager service connection. Follow these steps to create the service connection (see [Connect to Microsoft Azure](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/connect-to-azure?view=azure-devops) for more info):

1. Log in to you Azure DevOps organization and open your team project.
1. Open the Project setting in the left bottom corner.
1. Under Service connections choose New service connection.
1. Select Azure Resource Manager as the type.
1. Choose Service principal (automatic) as the authentication method.
1. In my case it automatically found my subscription connected to my Azure DevOps account.
1. Leave the resource group empty (we're going to create a new one).
1. Give it a name like MyAzureServiceConnection and choose Save.  
  ![Create Azure service connection](../../../../../images/provision-azure-vm-in-azure-pipelines-environment/create-azure-service-connection.png)
  <!-- ![Create Azure service connection](../../static/images/provision-azure-vm-in-azure-pipelines-environment/create-azure-service-connection.png) -->

### Dynamic environment name

After setting up the prerequisites we can start with the YAML pipeline. The pipeline starts with the variables section.

I want to give the Azure Pipelines environment a random name so I can run multiple instances of the pipeline in parallel without them interfering with eachother. I introduced the following `environmentName` variable for this purpose.

```yaml
variables:
  environmentName: "provision-vm-example-${{ variables['Build.SourceVersion'] }}"        
```

I tried adding the `Build.BuildNumber` variable as the postfix for the environment name to make it unique but it didn't work. The environment name that you use in deployment jobs needs to be available during pipeline intialization. And runtime variables like `Build.BuildNumber` can't be used here. So I settled for the `Build.SourceVersion` variable which contains the latest Git commit ID.

> If you want to know which variables are available are available during pipeline initialization. Go to the [Use predefined variables](https://docs.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml) page. Every variable with a Yes in the 'Available in templates?' column can be used this way.

### Provision Azure virtual machine

The first stage in the pipeline will provision the Azure virtual machine and register the VM in the environment. The start of this stage looks as follows:

```yaml
stages:
- stage: Provision
  jobs:
  - job:
    steps:
    - task: AzureCLI@2
      inputs:
        azureSubscription: 'MyAzureSubscription'
        scriptType: pscore
        scriptLocation: inlineScript
        inlineScript: |
        
```

We're using the `AzureCLI` task with an inline PowerShell script to create the various resources in Azure through the MyAzureSubscription service connection we created earlier. I've chosen Azure CLI for its simplicity and because it has an extension which allows me to also interact Azure DevOps.

#### Provision the Azure virtual machine

The first command of the Azure CLI script is to create a resource group. I'm using the same name as the environment so we can easily match the two.

```powershell
az group create --name $(environmentName) --location westeurope;
```

Next we create the virtual machine. With this command a Windows Server 2019 VM will be created in the resource group.

```powershell
az vm create `
  --name ProvisionedVM `
  --image Win2019Datacenter `
  --admin-password Password12345!`
  --resource-group $(environmentName);
```
The name of the virtual machine will be `ProvisionedVM`. The max length of the name is 15 characters.

The admin password is a required parameter. For demo purposes I've hardcoded the password in the pipeline but you should ofcourse use something like a secret variable.

Notice I haven't provided a name for the admin user. If you don't provide the user name the admin username will match the name of the user running the Azure CLI command. Which in this case will be `vsts`.

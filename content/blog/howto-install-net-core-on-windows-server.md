---
title: "How install .NET Core on a Windows Server"
date: 2020-01-22T00:00:00+01:00
image: "images/howto-install-net-core-on-windows-server/howto-install-net-core-on-windows-server.jpg"
tags: [ "Azure Pipelines", "Azure DevOps", ".NET Core", "IIS", "Windows Server" ]
summary: "In this post I'll show you how I install and update the .NET Core Runtime & Hosting Bundle on Windows Servers using Azure Pipelines."
draft: true
---

At my current client we're transitioning from .NET Framework to .NET Core. We only have a few .NET Core web applications at the moment and the preferred hosting model is to host them in IIS. This means we need to install the .NET Core Runtime & Hosting Bundle on every Windows Sever where a .NET Core web application is deployed. This bundle includes the .NET Core Runtime and IIS support for .NET Core.

Where new versions and patches of the .NET Framework are installed through Windows Update, .NET Core does not provide a similar solution. Which means that for every .NET Core update we manually need to download the installer and execute it on every server in every environment. To make this process simpler and faster I've created an Azure DevOps extension called [Install .NET Core Runtime & Hosting Bundle](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting) that automates this task. You can find the extension in the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting).

In the rest of this post I'll give an example of how you can use this task in Azure DevOps with a [YAML pipeline](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema%2Cparameter-schema) to automate the installation of the .NET Core Runtime & Hosting Bundle on a Windows Server.

> NOTE: if you have an older version of Azure DevOps, that doesn't support YAML pipelines in combination with Environments, you can create a [Deployment Group](https://docs.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/?view=azure-devops) instead of an Environment. In that case you can use a [Release pipeline](https://docs.microsoft.com/en-us/azure/devops/pipelines/release/?view=azure-devops) instead of a YAML pipeline to execute the 'Install .NET Core Runtime & Hosting' task.

### Install the 'Install .NET Core Runtime & Hosting Bundle' extension

Step 1 is to install the extension in your Azure DevOps organization. For this, go to the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting) and click on the 'Get it free' button. 

![Visual Studio Marketplace](../../../../../images/howto-install-net-core-on-windows-server/visual-studio-marketplace.png)

You'll need to log into Azure DevOps if you haven't already. Select the correct organization and click Install. After installation you can proceed to your Azure DevOps organization.

![Install in organization](../../../../../images/howto-install-net-core-on-windows-server/install-in-azure-devops-organization.png)

> NOTE: depending on your permissions, an administrator might have to approve the intallation before you can proceed.

### Enable Multi-stage pipelines preview feature

To use a YAML Pipeline that can deploy to an Environment, you'll need to enable the 'Multi-stage pipelines' preview feature.

Open the 'User settings' menu in the top right corner and choose 'Preview features'.

![User settings menu - Preview features](../../../../../images/howto-install-net-core-on-windows-server/user-settings-menu-preview-features.png)

Enable the 'Multi-stage pipelines' preview feature.

![User settings menu - Preview features](../../../../../images/howto-install-net-core-on-windows-server/multi-stage-pipelines-preview-feature.png)

### Create an Environment

Before creating the pipeline we need an [Environment](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/environments?view=azure-devops). This will enable us to add several servers to one environment and install .NET Core on multiple machines at once. Example environments are Dev, Test, Acceptance and Production.

So go to Pipelines > Environments and choose New environment. Enter a Name and Description and select Virtual machines as the resource.

![New Environment](../../../../../images/howto-install-net-core-on-windows-server/new-environment.png)

Choose Next.

You'll get a screen where can configure the Virtual machine resource. Copy the Registration script command to the clipboard.

![New Environment - Configure Virtual machine resource](../../../../../images/howto-install-net-core-on-windows-server/new-environment-virtual-machine-rescource.png)

Go the the machine on which you want to install .NET Core and add the machine to the environment using the registration script you've just copied. See [Environment - virtual machine resource](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/environments-virtual-machines?view=azure-devops) for more information.

### The YAML Pipeline

Now that we have an environment, we can create the YAML pipeline using the following steps _(see [create your first pipeline](https://docs.microsoft.com/en-us/azure/devops/pipelines/get-started-yaml?view=azure-devops) for a more detailed description)_:

- In the left menu of Azure DevOps choose Pipelines > Pipelines.
- Click the 'New pipeline' button.
- Select the source where you want to store your YAML Pipeline. E.g. 'GitHub'.
- Select the repository that will contain your YAML Pipeline.
- Select the pipeline template you want to start from. In our case the 'Starter pipeline' will do.
- An editor is opened where you can configure your pipeline using YAML. Replace all content with the following.

```yaml
trigger: none

stages:
- stage: 'InstallNetCore'
  jobs:
  - deployment: 'InstallNetCore'
    environment:
      name: 'net-core-test'
      resourceType: 'VirtualMachine'
      tags: 'net-core'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: InstallNetCoreRuntimeAndHosting@0
            inputs:
              version: '3.1'
              useProxy: false
              norestart: false
              iisReset: true
```

The pipeline above will install the .NET Core 3.1 Runtime & Hosting Bundle on every machine in the environment 'net-core-test' that has the tag 'net-core'. After installation it will perform an IIS reset. _(See the description in the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting) for more details about the inputs that you can provide to the task.)_

Choose 'Save and run' to save the pipeline in your repository and execute the pipeline. After executing the pipeline the result should look something like this were the .NET Core Runtime & Hosting Bundle has been installed on the machines 'win-2016-01' and 'win-10'.

![Pipeline Summary](../../../../../images/howto-install-net-core-on-windows-server/pipeline-summary.png)

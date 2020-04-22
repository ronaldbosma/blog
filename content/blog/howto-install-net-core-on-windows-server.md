---
title: "How install .NET Core on a Windows Server"
date: 2020-01-22T00:00:00+01:00
image: "images/howto-install-net-core-on-windows-server/howto-install-net-core-on-windows-server.jpg"
tags: [ "Azure Pipelines", "Azure DevOps", ".NET Core", "IIS", "Windows Server" ]
summary: "In this post I'll show you how I install and update the .NET Core Runtime & Hosting Bundle on Windows Servers using Azure Pipelines."
draft: true
---

At my current client we're transitioning from .NET Framework (WCF services) to .NET Core. We only have a few .NET Core web applications at the moment and the preferred hosting model is to host these in IIS. This means we need to install the .NET Core Runtime & Hosting Bundle on every Windows Sever where a .NET Core web application is deployed. This bundle includes the .NET Core Runtime and IIS support for .NET Core.

Where new versions and patches of .NET Framework are installed through Windows Update, .NET Core does not provide a similar solution. Which means that for every .NET Core update we manually need to download the installer and execute it on every server in every environment. To make this process a little smoother I've created an Azure DevOps extension called [Install .NET Core Runtime & Hosting Bundle](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting) that automates this task. You can find the extension in the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting).

In the rest of this post I'll give an example of how you can use this task in an Azure Pipeline to automate the installation of .NET Core on a Windows Server.

### Install the 'Install .NET Core Runtime & Hosting Bundle' extension

Step 1 is to install the extension in your Azure DevOps organization. For this, go to the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting) and click on the 'Get it free' button. 

![Visual Studio Marketplace](../../../../../images/howto-install-net-core-on-windows-server/visual-studio-marketplace.png)

You'll need to log in to Azure DevOps if you haven't already. Select the correct organization and click Install. After installation you can proceed to your Azure DevOps organization.

![Install in organization](../../../../../images/howto-install-net-core-on-windows-server/install-in-azure-devops-organization.png)

> NOTE: Depending on your permissions, an administrator might have to approve the intallation before you can proceed.

### Enable Multi-stage pipelines preview feature

In this example we'll be using a [YAML pipeline](https://docs.microsoft.com/en-us/azure/devops/pipelines/yaml-schema?view=azure-devops&tabs=schema%2Cparameter-schema). You'll need to enable the Multi-stage pipelines preview feature for this to work.

Open the User settings menu in the top right corner and choose Preview features.

![User settings menu - Preview features](../../../../../images/howto-install-net-core-on-windows-server/user-settings-menu-preview-features.png)

Enable the Multi-stage pipelines preview feature.

![User settings menu - Preview features](../../../../../images/howto-install-net-core-on-windows-server/multi-stage-pipelines-preview-feature.png)

### Create an Environment

Before creating the pipeline we need an [Environment](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/environments?view=azure-devops). This will enable us to add several servers to one environment and install .NET Core on multiple machines at once. Example environments are Dev, Test, Acceptance and Production.

So go to Pipelines > Environments and choose New environment. Enter a Name and Description and select Virtual machines as the resource.

![New Environment](../../../../../images/howto-install-net-core-on-windows-server/new-environment.png)

Choose Next. You'll get a screen where can configure the Virtual machine resource. Copy the Registration script command to the clipboard.

![New Environment - Configure Virtual machine resource](../../../../../images/howto-install-net-core-on-windows-server/new-environment-virtual-machine-rescource.png)

Go the the machine on which you want to install .NET Core and add the machine to the environment using the registration script you've just copied. See [Environment - virtual machine resource](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/environments-virtual-machines?view=azure-devops) for more information.

> NOTE: if you have an older version of Azure DevOps you can create a deployment group instead of an Environment. See [Provision deployment groups
](https://docs.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/?view=azure-devops). In that case you can use a release pipeline instead of a yaml pipeline to execute the 'Install .NET Core Runtime & Hosting Bundle' task.

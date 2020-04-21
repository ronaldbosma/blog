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

### Create a deployment group

Before creating the release pipeline we need a deployment group. This will enable us to add several servers to a group and install .NET Core on multiple machines at once. At my current client we have a deployment group for every environment (Dev, Test, Acceptance and Production).

So go to Pipelines > Deployment groups and choose New. Enter a name and choose Create. After creation you'll get a PowerShell script that you'll need to execute on the machines you want to add to the deployment group. When executing the script, follow the instructions and give the machine a tag like 'net-core'.

The end result might look something like this:
![Install in organization](../../../../../images/howto-install-net-core-on-windows-server/deployment-group.png)

For more information on Deployment Groups and adding servers to a group see [Provision deployment groups](https://docs.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups) and [Provision agents for deployment groups](https://docs.microsoft.com/en-us/azure/devops/pipelines/release/deployment-groups/howto-provision-deployment-group-agents).

### Setting up the release pipeline


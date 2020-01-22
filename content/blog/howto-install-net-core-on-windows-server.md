---
title: "How install .NET Core on a Windows Server"
date: 2020-01-22T00:00:00+01:00
image: "images/howto-install-net-core-on-windows-server/howto-install-net-core-on-windows-server.jpg"
tags: [ "Azure Pipelines", "Azure DevOps", ".NET Core", "IIS", "Windows Server" ]
summary: "In this post I'll show you how I install and update the .NET Core Runtime & Hosting Bundle on Windows Servers using Azure Pipelines."
draft: true
---

At my current client we're transitioning from .NET Framework (WCF services) to .NET Core. We only have a few .NET Core web application and the preferred hosting model at the moment is to host these in IIS. This means we need to install the .NET Core Runtime & Hosting Bundle, which includes the .NET Core Runtime and IIS support, on every Windows Sever where a .NET Core web application is deployed.

Where new versions and patches of .NET Framework are installed through Windows Update, .NET Core does not provide a similar solution. Which means that for every .NET Core update we manually need to download the installer and execute it on every server in every environment. To make this process a little smoother and faster I've created an Azure DevOps extension called [Install .NET Core Runtime & Hosting Bundle](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting) that automates this task. You can find the extension in the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=rbosma.InstallNetCoreRuntimeAndHosting).

In the rest of this post I'll give an example of how you can use this task in an Azure Pipeline to automate the installation of .NET Core on a Windows Server.
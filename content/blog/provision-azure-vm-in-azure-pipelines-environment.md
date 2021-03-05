---
title: "Provision an Azure VM in an Azure Pipelines Environment"
date: 2021-03-05T00:00:00+01:00
publishdate: 2021-03-05T00:00:00+01:00
lastmod: 2021-03-05T00:00:00+01:00
tags: [ "Azure", "Azure CLI", "Azure DevOps", "Azure Pipelines", "YAML" ]
summary: "To test a custom Azure Pipelines task of mine I created a YAML pipeline in Azure DevOps that automatically provisions an Azure virtual machine and registers the VM in an Azure Pipelines environment. In this blog post I'll show you how it works."
draft: true
---

In the past I've written the post [How to install .NET Core on a Windows server](https://ronaldbosma.github.io/blog/2020/05/07/how-to-install-.net-core-on-a-windows-server/) where I talked about a custom Azure Pipelines task that I've build. To test this task in an actual pipeline I used an Azure virtual machine that I created manually and kept around for this specific purpose. Everytime I wanted to test something I had to start the machine, test my task, log on to the server and check if .NET Core was installed successfully. And if I wanted to test a clean install I had to uninstall .NET Core first.

As you can see, a lot of manual steps were involved. So I automated this. I've created a pipeline that:
1. Creates an Azure Pipelines environment in Azure DevOps.
1. Provisions a fresh virtual machine in Azure.
1. Registers the virtual machine in the Azure Pipelines environment.
1. Runs my custom task & verifies that the installation is successful.
1. Deletes the Azure Pipelines environment.
1. Deletes the Azure virtual machine.


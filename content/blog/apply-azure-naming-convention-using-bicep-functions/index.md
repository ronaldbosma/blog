---
title: "Apply Azure naming convention using Bicep functions"
date: 2024-05-10T11:00:00+02:00
publishdate: 2024-05-10T11:00:00+02:00
lastmod: 2024-05-10T11:00:00+02:00
tags: [ "Azure", "Bicep" ]
draft: false
---

When deploying Azure resources, it's a good practice to apply a naming convention to your resources. This will help you to identify the purpose of the resource and the environment it belongs to. In this blog post, I will show you how to apply a naming convention using Bicep user-defined functions. This post also includes a short introduction to the (experimental) Bicep Testing Framework.

Based on [Define your naming convention](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming), I'm using the following naming convention as an example:

![](../../../../../images/apply-azure-naming-convention-using-bicep-functions/naming-convention.png)

The name of a resource consists of the following components:

| Component | Description |
|-|-|
| Resource Type | An abbreviation based on the resource type. For example `vnet` for Virtual Network. |
| Workload / Application | The name of the workload or application that the resouce belongs to. For example `myapp` for My Application. |
| Environment | An abbreviation based on the environment the resource belongs to. For example `dev` for Development. |
| Azure Region | An abbreviation of the region where the resource is deployed. For example `nwe` for Norway East. |
| Instance | A unique identifier for the resource. This can be a number like `001` or a named instance like `main` or `primary`. |


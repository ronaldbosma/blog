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


In the past I've used a Bicep module to apply naming conventions, but in this post we'll be using a relatively new feature called [User-defined functions in Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/user-defined-functions) in combination with [Imports in Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-import). This will allow us to create a reusable function that generates the name of a resource based on the naming convention and use it in our Bicep files.

In my opinion, from a users perspective, using a user-defined function is more elegant then using a module. The function call can be a one liner, while a module call requires a lot more lines of code. A module also shows up as a deployment in Azure, while a function does not.

As a reference, here is how you would use a module to get the name of a virtual network based on the naming convention:

```bicep
module vnetNameBuilder  './get-resource-name.bicep' = {
  name: 'vnetNameBuilder'
  params: {
    resourceType: 'virtualNetwork'
    workload: 'sample'
    environment: 'dev'
    region: 'norwayeast'
    instance: '001'
  }
}
var vnetName = vnetNameBuilder.outputs.resourceName
```

And here is how you do the same with a function:

```bicep
var vnetName = getResourceName('virtualNetwork', 'sample', 'dev', 'norwayeast', '001')
```

That being said. Creating the logic for the naming convention however is a bit more difficult in a function then in a module. In a module, you can create a 'procedural' script that applies the naming convention step-by-step. Using variables for intermediate results. In a function, you can't use variables, so you have to call other functions from within a function to create a chain of functions. This is a bit more cumbersome, but it works.

### Resource Type Prefix


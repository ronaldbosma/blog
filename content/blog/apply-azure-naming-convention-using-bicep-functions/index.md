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

That being said. Creating the logic for the naming convention is a bit more difficult in a function then in a module. In a module, you can create a 'procedural' script that applies the naming convention step-by-step, using variables for intermediate results. In a function, you can't use variables, so you have to call other functions to create the logic. This is a bit more cumbersome, but it works.

### User-defined functions

A lot of the logic consists of keeping the resource names short. This is important due to limitations in the length of resource names. A Key Vault or Storage Account name for example can only be 24 characters long. A Windows virtual machine is even shorter with a maximum of 15 characters.

#### Resource Type Prefix

We'll start with the resource type prefix. I've used [Abbreviation recommendations for Azure resources](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) as input to create a mapping of resource types to prefixes that I commonly use. It's not a complete list, but you can easily extend it with your own resource types and prefixes.

See the snippet below for the function to get the prefix.

```bicep
func getPrefix(resourceType string) string => getPrefixMap()[resourceType]

func getPrefixMap() object => {
  apiManagement: 'apim'
  keyVault: 'kv'
  resourceGroup: 'rg'
  storageAccount: 'st'
  virtualMachine: 'vm'
  virtualNetwork: 'vnet'
  ...
}
```

As mentioned before, we can't use a variable to store the mapping, so I'm using the function `getPrefixMap` to return the mapping. Which in turn is used by the `getPrefix` function to return the prefix of the specified resource type. The call `getPrefix('virtualNetwork')` will for example return `vnet`.

#### Environment

Similar to the resource type prefix, I've created a mapping of environment names to abbreviations. This mapping is used by the `abbreviateEnvironment` function to return the abbreviation of the specified environment. See the snippet below.

```bicep
func abbreviateEnvironment(environment string) string => getEnvironments()[toLower(environment)]

func getEnvironments() object => {
  dev: 'dev'
  development: 'dev'
  tst: 'tst'
  test: 'tst'
  acc: 'acc'
  acceptance: 'acc'
  prd: 'prd'
  prod: 'prd'
  production: 'prd'
}
```

#### Azure Region

Just like the resource type prefix and environment, I'm using a map to abbreviate the Azure region. There doesn't seem to be an official list of abbreviations by Microsoft, so I'm using [Azure Region Abbreviations](https://www.jlaundry.nz/2022/azure_region_abbreviations/) as input. It provides multiple conventions, so you can choose the one that fits your needs best. I'm using the `Short Name (CAF)` convention because it seems to be the most complete.

Here's a snippet of the functions:

```bicep
func abbreviateRegion(region string) string => getRegionMap()[region]

func getRegionMap() object => {
  northeurope: 'ne'
  norwayeast: 'nwe'
  westcentralus: 'wcus'
  westeurope: 'we'
  ...
}
```

#### Sanitize

With these functions as a basis we can create a simple function that applies the naming convention to a resource name. Here's an example:

```bicep
func getResourceName(resourceType string, workload string, environment string, region string, instance string) string => 
  '${getPrefix(resourceType)}-${workload}-${abbreviateEnvironment(environment)}-${abbreviateRegion(region)}-${instance}'
```

However, we're not in full control of the input values. We're putting the workload and instance directly in the name without any processing. We should sanitize these values to make sure they don't contain any characters that are not allowed in a resource name.

Here's a sample function that sanitizes the input values by removing colons, commas, dots, semicolons, underscores and white spaces. It also converts the result to lowercase.

```bicep
func sanitizeResourceName(value string) string => toLower(removeColons(removeCommas(removeDots(removeSemicolons(removeUnderscores(removeWhiteSpaces(value)))))))

func removeColons(value string) string => replace(value, ':', '')
func removeCommas(value string) string => replace(value, ',', '')
func removeDots(value string) string => replace(value, '.', '')
func removeSemicolons(value string) string => replace(value, ';', '')
func removeUnderscores(value string) string => replace(value, '_', '')
func removeWhiteSpaces(value string) string => replace(value, ' ', '')
```


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

![Azure Naming Convention](../../../../../images/apply-azure-naming-convention-using-bicep-functions/naming-convention.png)

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

### User-defined Functions

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

With these functions as a basis we could create a simple function that applies the naming convention to a resource name. Here's an example:

```bicep
func getResourceNameByConvention(resourceType string, workload string, environment string, region string, instance string) string => 
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

#### Short Names

For most resources this will be enough. However, a couple of resources have a small maximum length for the name and some don't allow hyphens. For example, a Key Vault and Storage Account have a maximum length 24 characters. And a Windows virtual machine's maximum length is even shorter with only 15 characters. To make sure the name doesn't exceed the maximum length, we can shorten the name for these specific resources.

First we'll need a function to check if a resource type should be shortened. We'll use an array of resource types that should be shortened and check if the specified resource type is in this list. Here's the function:

```bicep
func shouldBeShortened(resourceType string) bool => contains(getResourcesTypesToShorten(), resourceType)

func getResourcesTypesToShorten() array => [
  'keyVault'
  'storageAccount'
  'virtualMachine'
]
```

Next we'll need a function to shorten the name. We'll remove hyphens and sanitize the resource name. Here's the function:

```bicep
func shortenString(value string) string => removeHyphens(sanitizeResourceName(value))
func removeHyphens(value string) string => replace(value, '-', '')
```

Taking into account the length of the prefix, environment and region, this is enough for the Key Vault and Storage Account if you keep the combination of workload and instance to about 15 characters. For the Virtual Machine, we need to make the name even shorter but it should also be unique. We can use the [uniqueString](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-string#uniquestring) function to generate a unique string based on the workload, environment and region. The result won't be globally unique, but it's close enough for our purpose. The returned value is 13 characters long. For example, `uniqueString('sample', 'dev', 'norwayeast')` will result in the `zmamywx7mjdhw`. 

I want to include the instance in the name, so we need to make the generated unique string a litter shorter depending on the length of the isntance. Using `substring` we kan remove the last characters of the unique string, based on the length of the instance. Here's the function to create the virtual machine name:

```bicep
func getVirtualMachineName(workload string, environment string, region string, instance string) string =>
  'vm${substring(uniqueString(workload, environment, region), 0, 13-length(shortenString(instance)))}${shortenString(instance)}'
```

As you can see, I'm using the `shortenString` function to keep the instance name as short as possible. Take note though, that if the instance name is longer dan 13 characters, the `substring` function will throw an error. Unfortunately, it's not possible yet to set a maximum length on parameters of a function.

With this, we can create a function that will return the shortened name of a resource based on the naming convention. Here's the function:

```bicep
func getShortenedResourceName(resourceType string, workload string, environment string, region string, instance string) string =>
  resourceType == 'virtualMachine'
    ? getVirtualMachineName(workload, environment, region, instance)
    : shortenString(getResourceNameByConvention(resourceType, workload, environment, region, instance))
```

#### Get Resource Name

Finally, we can create a function that will return the name of a resource based on the naming convention. This function will check if the resource type should be shortened and call the appropriate function. Here's the function:

```bicep
@export()
func getResourceName(resourceType string, workload string, environment string, region string, instance string) string => 
  shouldBeShortened(resourceType) 
    ? getShortenedResourceName(resourceType, workload, environment, region, instance)
    : getResourceNameByConvention(resourceType, workload, environment, region, instance)
```

Note the `export` decorator. This is required to make the function available to other Bicep files.

The final result can be found in [naming-conventions.bicep](https://github.com/ronaldbosma/blog-code-examples/blob/master/apply-azure-naming-convention-using-bicep-functions/naming-conventions.bicep).


### Using the Function

To use the function in different Bicep files, you can put all the functions in a reusable Bicep file. You can then import this file in your Bicep files. Here's an example of how to import the file:

```bicep
import { getResourceName } from './naming-conventions.bicep'
```

Note that the import feature is still in preview. Although [Imports in Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-import) states that you need to enable the feature in your Bicep config file, I didn't have to do this. I'm using Bicep version `0.26.170`.

After importing the file, you can use the `getResourceName` function in your Bicep files. Here are some examples:

```bicep
param location string = resourceGroup().location
param workload string
param environment string

param paramExample string = getResourceName('vnet', workload, environment, location, '001')

param varExample string = getResourceName('vnet', workload, environment, location, '002')

resource resourceExample 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: getResourceName('vnet', workload, environment, location, '003')
  location: location
  properties: {
    ...
  }
}

output outputExample string = getResourceName('vnet', workload, environment, location, '004')
```


### Testing the Function

There is quite a bit of logic necessary to get a resource name. To make sure everything works as expected, you can use the Bicep Testing Framework. The blog post [Exploring the awesome Bicep Test Framework](https://rios.engineer/exploring-the-bicep-test-framework-%F0%9F%A7%AA/) explains how to use the framework. I'll cover the basics here.

This testing framework is still experimental so you'll need to enable it in your Bicep config file. You need to create a [bicepconfig.json](https://github.com/ronaldbosma/blog-code-examples/blob/master/apply-azure-naming-convention-using-bicep-functions/bicepconfig.json) and add the following configuration:

```json
{
    "experimentalFeaturesEnabled": {
        "testFramework": true,
        "assertions": true
  }
}
```

Our `getResourceName` function can't be directly called from a Bicep test. We'll need to create a Bicep module that calls the function and asserts the result. Create a file called [test-get-resource-name.bicep](https://github.com/ronaldbosma/blog-code-examples/blob/master/apply-azure-naming-convention-using-bicep-functions/test-get-resource-name.bicep) and add the following code:

```bicep
// Arrange

import { getResourceName } from './naming-conventions.bicep'

param resourceType string
param workload string
param environment string
param region string
param instance string

param expectedResult string

// Act
var actualResult = getResourceName(resourceType, workload, environment, region, instance)

// Assert
assert assertResult = actualResult == expectedResult
```

As you can see, the module:
- imports the function
- defines parameters for the input values of the function
- defines a parameter for the expected result
- calls the `getResourceName` function
- asserts that the actual result is equal to the expected result

Now, create a file called [tests.bicep](https://github.com/ronaldbosma/blog-code-examples/blob/master/apply-azure-naming-convention-using-bicep-functions/tests.bicep) that will contain the tests. Here's an example of a test that checks if the name of a virtual network is crate correctly:

```bicep
test testPrefixVirtualNetwork 'test-get-resource-name.bicep' = {
  params: {
    resourceType: 'virtualNetwork'
    workload: 'sample'
    environment: 'dev'
    region: 'norwayeast'
    instance: '001'
    expectedResult: 'vnet-sample-dev-nwe-001'
  }
}
```

To execute the tests, run the following command:

```bash
bicep test .\tests.bicep
```

The test results will look like this:

![Bicep Test Results](../../../../../images/apply-azure-naming-convention-using-bicep-functions/bicep-test-results.png)

In this example the test `testPrefixResourceGroup` has failed. The output could be improved by adding the actual and expected result. I'm hoping the Bicep team will add this in the future.

You can find the full suite of tests in [tests.bicep](https://github.com/ronaldbosma/blog-code-examples/blob/master/apply-azure-naming-convention-using-bicep-functions/tests.bicep).

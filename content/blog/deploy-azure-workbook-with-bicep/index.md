---
title: "Deploy Azure Workbook with Bicep"
date: 2023-02-03T00:00:00+02:00
publishdate: 2023-02-03T00:00:00+02:00
lastmod: 2023-02-03T00:00:00+02:00
tags: [ "Azure", "Application Insights", "Bicep", "Infra as Code", "PowerShell" ]
summary: "In this post I explain how to deploy an Azure workbook using Bicep and set environment specific variables. To improve maintainability of the Bicep script, I convert the workbook JSON definition to a formatted Bicep object with PowerShell."
draft: true
---

In my [previous blog post](/blog/2023/02/28/azure-workbook-tips-and-tricks/) we created an [Azure Workbook](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview) to gain more insight into the use of our API's hosted in Azure API Management. In this blog post I'll show you how to deploy this workbook, and the kusto function it uses, with Bicep.

### Deploy based on ARM template

You can download an ARM Template of the workbook, which you can convert to a Bicep script. To do this, open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-with-bicep/edit-workbook-advanced-editor.png)

Choose ARM Template as the Template Type and download the template. The result will look like [sample-arm-template.json](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/arm-template/sample-arm-template.json).

The ARM template can then be decompiled to a Bicep script with the following Azure CLI command. 

```powershell
az bicep decompile --file .\sample-arm-template.json
```

The result will be a Bicep file like the snippet below. See [sample-after-decompile.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/arm-template/sample-after-decompile.bicep) for the full script.

```bicep
@description('The friendly name for the workbook that is used in the Gallery or Saved List.  This name must be unique within a resource group.')
param workbookDisplayName string = 'API Management Requests'

@description('The gallery that the workbook will been shown under. Supported values include workbook, tsg, etc. Usually, this is \'workbook\'')
param workbookType string = 'workbook'

@description('The id of resource instance to which the workbook will be associated')
param workbookSourceId string = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-test/providers/microsoft.insights/components/appin-robo-test'

@description('The unique guid for this workbook instance')
param workbookId string = newGuid()

resource workbookId_resource 'microsoft.insights/workbooks@2021-03-08' = {
  name: workbookId
  location: resourceGroup().location
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    serializedData: '{"version":"Notebook/1.0","items":[{"type":9,"content":{"version":.......'
    version: '1.0'
    sourceId: workbookSourceId
    category: workbookType
  }
  dependsOn: []
}

output workbookId string = workbookId_resource.id
```

The workbook definition is set through the `serializedData` property. As you can see it's one long string that contains the entire workbook definition. Including hardcoded environment specific values, like the application insights resource id at the end of the string.

To make it deployable to multiple environments, we can replace the hardcoded application insights id with the `workbookSourceId` parameter. See the example below.

```json
... "fallbackResourceIds":["${workbookSourceId}"] ...
```

We can now deploy the workbook using the following Azure CLI command.

```
$resourceGroupName = '<resource group>'
$applicationInsightsId = '<application insights id>'

az deployment group create `
    --name 'sample-workbook-deployment' `
    --resource-group $resourceGroupName `
    --template-file './sample-arm-template.bicep' `
    --parameters `
        workbookDisplayName='Sample Deployed Workbook (Based on ARM template)' `
        workbookSourceId=$applicationInsightsId `
    --verbose
```

If you run this command multiple times, it will fail with the error `A Workbook with the same name already exists within this subscription.`, because the workbook id is different with every deployment. You can fix this by generating a GUID based on a string that is the same for each deployment. See the example below.

```
param workbookId string = guid('sample-arm-template')
```

A working sample with these changes can be found [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/arm-template/sample-full.bicep). 

The biggest downside of this solution is that the entire workbook definition is a serialized string on one line. This makes it difficult to make minor changes directly in the definition or to see what has changed during a review.


### Deploy with Bicep object

To solve this problem, I convert the workbook JSON definition into a Bicep object. It can be used inside the Bicep script and can be formatted for improved readability. 

The first step is to download the workbook definition. Open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-with-bicep/edit-workbook-advanced-editor.png)

Choose Gallery Template as the Template Type and download the template. The result will be a JSON file containing only the definition of the workbook. It should look like [my-workbook.workbook](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/exports/my-workbook.workbook).

To use this definition in the Bicep script, we need to convert the JSON to valid Bicep. I've created the following PowerShell script to do this.

```powershell
$sourceFile = "./my-workbook.workbook"
$targetFile = "./my-workbook-definition.bicep"

# Key value pair of variables that should replace environment specific values
$variables = @{
    "apimResourceName" = "my-api-management-dev";
    "appInsights.id" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-test/providers/microsoft.insights/components/my-application-insights-dev"
}

$workbook = Get-Content -Path $sourceFile

# For each line in the workbook
for ($i = 0; $i -lt $workbook.Count; $i++)
{
    # 1. Remove " surrounding the property names
    $workbook[$i] = $workbook[$i] -replace '"(.+)":', '$1:'

    # 2. Replace ' with \' so the ' is escaped in values
    $workbook[$i] = $workbook[$i] -replace "'", "\'"

    # 3. Replace " surrounding the values with ' and remove the trailing ,
    $workbook[$i] = $workbook[$i] -replace '"(.*)",?$', '''$1'''

    # 4. Remove leftover trailing ,
    $workbook[$i] = $workbook[$i] -replace ',$', ''

    # 5. Replace \" with ". No need to escape the " in values because the values are surrounded with ' instead of "
    $workbook[$i] = $workbook[$i] -replace '\\"', '"'

    # 6. Remove the JSON schema reference
    $workbook[$i] = $workbook[$i].Replace("`$schema: 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'", "")

    # 7. Replace environment specific values with variables
    foreach ($variable in $variables.Keys)
    {
        $workbook[$i] = $workbook[$i] -replace $variables[$variable],"`${$variable}"
    }
}

Set-Content -Path $targetFile -Value $workbook
```

When this script is executed, the `my-workbook.workbook` file is loaded, and we loop over every line performing the following transformations:
1. Remove the `"` that surrounds the property names. Bicep properties don't have these.
1. Escape all occurrences of `'` with a \`. This will escape for instance a `'` that is used in a query.
1. Surround string values with `'` instead of `"` and remove any trailing `,`
1. Remove all trailing `,` that were skipped by the previous step (in case of non-string value for example)
1. Remove the `\` from `\"`. The `"` in values was escaped, but this is no longer necessary since the values are surround by a `'`
1. Remove the JSON schema property
1. Replace all environment specific values with variables/parameters. The value `my-api-management-dev` becomes `${apimResourceName}` for example.

The result is a Bicep file that looks like [my-workbook-definition.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/exports/my-workbook-definition.bicep).

You can put the contents of the generated definition file in the following Bicep script as the value of the `definition` variable.

```bicep
param name string = 'my-workbook'
param displayName string = 'My Workbook'
param appInsightsName string = 'my-application-insights-dev'
param apimResourceName string = 'my-api-management-dev'

var definition = //PUT YOUR GENERATED BICEP OBJECT HERE

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource workbookId_resource 'microsoft.insights/workbooks@2021-03-08' = {
  name: guid(name)
  location: resourceGroup().location
  kind: 'shared'
  properties: {
    displayName: displayName
    serializedData: string(definition)
    version: '1.0'
    sourceId: appInsights.id
    category: 'workbook'
  }
}
```

As you can see, the definition is first converted with the `string()` function before setting the `serializedData` property. After saving the Bicep file, it should look like [my-workbook.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/my-workbook.bicep).

Because the workbook definition is formatted instead of a one liner string, it's easier to make small changes or see what was changed.

You can now deploy the workbook using the following Azure CLI command and you're done.

```powershell
az deployment group create `
    --name 'my-workbook-deployment' `
    --resource-group 'my-resource-group' `
    --template-file './my-workbook.bicep' `
    --verbose
```
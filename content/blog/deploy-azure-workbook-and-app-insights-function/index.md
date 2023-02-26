---
title: "Deploy Azure Workbook and App Insights Function"
date: 2023-02-03T00:00:00+02:00
publishdate: 2023-02-03T00:00:00+02:00
lastmod: 2023-02-03T00:00:00+02:00
tags: [ "Azure", "Application Insights", "Bicep", "Infra as Code", "PowerShell" ]
summary: "In this post I explain how to deploy an Azure workbook using Bicep and set environment specific variables. I'll also show how to deploy an Application Insights function with the Azure CLI."
draft: true
---

In my [previous blog post](/blog/2023/02/28/azure-workbook-tips-and-tricks/) we created an [Azure Workbook](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview) to gain more insight into the use of our API's hosted in Azure API Management. In this blog post I'll show you how to deploy this workbook, and the kusto function it uses, with Bicep.

- [Deploy workbook based on ARM template](#deploy-workbook-based-on-arm-template)
- [Load workbook from file](#load-workbook-from-file)
- [Deploy App Insights function](#deploy-app-insights-function)

### Deploy workbook based on ARM template

You can download an ARM Template of the workbook, which you can convert to a Bicep script. To do this, open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-and-app-insights-function/edit-workbook-advanced-editor.png)

Choose ARM Template as the Template Type and download the template. The result will look like [sample-arm-template.json](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookAndAppInsightsFunction/arm-template/sample-arm-template.json).

The ARM template can then be decompiled to a Bicep script with the following Azure CLI command. 

```powershell
az bicep decompile --file .\sample-arm-template.json
```

The result will be a Bicep file like the snippet below. See [sample-after-decompile.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookAndAppInsightsFunction/arm-template/sample-after-decompile.bicep) for the full script.

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

```powershell
$resourceGroupName = '<resource group>'
$applicationInsightsId = '<application insights id>'

az deployment group create `
    --name 'sample-workbook-deployment' `
    --resource-group $resourceGroupName `
    --template-file './sample.bicep' `
    --parameters workbookSourceId=$applicationInsightsId `
    --verbose
```

> NOTE: when you open the workbook in the Azure Portal, you'll get the error `Failed to resolve table or column expression named 'ApimRequests'...` because we haven't deployed the `ApimRequests` function yet.

If you run this command multiple times, it will fail with the error `A Workbook with the same name already exists within this subscription` because the workbook id is different with every deployment. You can fix this by generating a GUID based on a string that is the same for each deployment. See the example below.

```
param workbookId string = guid('sample-workbook')
```

A working sample with these changes can be found [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookAndAppInsightsFunction/arm-template/sample.bicep). 

The biggest downside of this solution is that the entire workbook definition is a serialized string on one line. This makes it difficult to make minor changes directly in the definition or to see what has changed during a review. To solve this problem, I load the workbook definition from a file. 

### Load workbook from file

The first step is to download the workbook definition. Open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-and-app-insights-function/edit-workbook-advanced-editor.png)

Choose Gallery Template as the Template Type and download the template. The result will be a JSON file containing only the definition of the workbook. It should look like [sample.workbook](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookAndAppInsightsFunction/exports/sample.workbook).

We can't replace the application insights id with the `workbookSourceId` parameter like we did before, so I've replaced the value inside the sample.workbook JSON file with a placeholder. You can do this for every environment specific value. See the example below.

```json
"fallbackResourceIds": [
  "##applicationInsightsId##"
],
```

Using the bicep script from the previous example as a base, we can now load the workbook definition from the file and replace the `##applicationInsightsId##` placeholder. See the snippet below.

```bicep
var definition = loadTextContent('./sample.workbook')
var serializedData = replace(definition, '##applicationInsightsId##', workbookSourceId)

resource workbookId_resource 'microsoft.insights/workbooks@2021-03-08' = {
  ...
  properties: {
    serializedData: serializedData
    ...
  }
}
```

As you can see the definition is loaded using the `loadTextContent` function. We then use `replace` to replace the placeholder. The last step is to set the `serializedData` property. See [sample.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookAndAppInsightsFunction/exports/sample.bicep) for the full sample.

Using the same Azure CLI command as before, we can deploy the workbook using Bicep.

```powershell
$resourceGroupName = '<resource group>'
$applicationInsightsId = '<application insights id>'

az deployment group create `
    --name 'sample-workbook-deployment' `
    --resource-group $resourceGroupName `
    --template-file './sample.bicep' `
    --parameters workbookSourceId=$applicationInsightsId `
    --verbose
```

> NOTE: when you open the workbook in the Azure Portal, you'll get the error `Failed to resolve table or column expression named 'ApimRequests'...` because we haven't deployed the `ApimRequests` function yet.


### Deploy App Insights function

The last step is to deploy the function that the workbook is dependent on. 
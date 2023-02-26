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
- [Define workbook as Bicep object](#define-workbook-as-bicep-object)
- [Deploy App Insights function](#deploy-app-insights-function)
- [Conclusion](#conclusion)

### Deploy workbook based on ARM template

You can download an ARM Template of the workbook, which you can convert to a Bicep script. To do this, open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-and-app-insights-function/edit-workbook-advanced-editor.png)

Choose ARM Template as the Template Type and download the template. The result will look like [sample-arm-template.json](https://github.com/ronaldbosma/blog-code-examples/blob/master/DeployAzureWorkbookAndAppInsightsFunction/arm-template/sample-arm-template.json).

The ARM template can then be decompiled to a Bicep script with the following Azure CLI command. 

```powershell
az bicep decompile --file .\sample-arm-template.json
```

The result will be a Bicep file like the snippet below. See [sample-after-decompile.bicep](https://github.com/ronaldbosma/blog-code-examples/blob/master/DeployAzureWorkbookAndAppInsightsFunction/arm-template/sample-after-decompile.bicep) for the full script.

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
    serializedData: '{"version":"Notebook/1.0","items":[{"type":9,"content":{"version":.....<long string>.....'
    version: '1.0'
    sourceId: workbookSourceId
    category: workbookType
  }
  dependsOn: []
}

output workbookId string = workbookId_resource.id
```

The workbook definition is set through the `serializedData` property. This is one long string that contains the entire workbook definition. Including hardcoded environment specific values, like the application insights resource id at the end of the string.

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

> NOTE: when you open the workbook in the Azure Portal, you'll get the error `Failed to resolve table or column expression named 'ApimRequests'` because we haven't deployed the `ApimRequests` function yet.

If you run this command multiple times, it will fail with the error `A Workbook with the same name already exists within this subscription`. The workbook id is different with every deployment. You can fix this by generating a GUID based on a string that is the same for each deployment. See the example below.

```
param workbookId string = guid('sample-workbook')
```

A working sample with these changes can be found [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/DeployAzureWorkbookAndAppInsightsFunction/arm-template/sample.bicep). 

The biggest downside of this solution is that the entire workbook definition is a serialized string on one line. This makes it difficult to make minor changes directly in the definition or to see what has changed. To solve this problem, we can load the workbook definition from a separate file. 


### Load workbook from file

The first step is to download the workbook definition. Open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-and-app-insights-function/edit-workbook-advanced-editor.png)

Choose Gallery Template as the Template Type and download the template. The result will be a JSON file containing only the definition of the workbook. It should look like [sample.workbook](https://raw.githubusercontent.com/ronaldbosma/blog-code-examples/master/DeployAzureWorkbookAndAppInsightsFunction/load-workbook-from-file/sample.workbook).

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

As you can see, the definition is loaded using the `loadTextContent` function. We then use `replace` to replace the placeholder. The last step is to set the `serializedData` property. See [sample.bicep](https://github.com/ronaldbosma/blog-code-examples/blob/master/DeployAzureWorkbookAndAppInsightsFunction/load-workbook-from-file/sample.bicep) for the full sample.

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


### Define workbook as Bicep object

I have explored another option to deploy a workbook. You can use a Bicep object for the workbook definition and place it directly in the Bicep script. The first version of this blog post was based on that solution.

The solution was pretty error prone though. Over the past weeks I've found numerous issues with the generated Bicep and had to update the conversion script multiple times.

Loading the workbook definition from a JSON file as a string and doing a simple replace for the placeholders seems to be an easier way to deploy, less error prone and also simpler explain to other developers.

I would not recommend this solution, given the disadvantages, but see this [README.md](https://github.com/ronaldbosma/blog-code-examples/blob/master/DeployAzureWorkbookAndAppInsightsFunction/bicep-object/README.md) if you're still interested.


### Deploy App Insights function

The last step is to deploy the function that the workbook is dependent on. I thought I could simply use the [analyticsItems](https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/components/analyticsitems?pivots=deployment-language-bicep) Bicep resource, but unfortunately this doesn't work at all. The problem has been reported on GitHub in [this issue](https://github.com/Azure/bicep/issues/5518).

The Azure CLI doesn't provide any commands either. The only option seems to be to use the REST API. There is no page about creating an Application Insights function in the [documentation](https://learn.microsoft.com/en-us/rest/api/application-insights/) however. Luckily I found [this blogpost](https://blog.peterschen.de/create-functions-in-application-insights-through-rest-api/) that describes the various operations.

The following `PUT` can be used to create a function.

```
PUT https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.Insights/components/{applicationName}/analyticsItems/item?api-version=2015-05-01

{
    "scope": "shared",
    "type": "function",
    "name": "myFunction",
    "content": "requests | order by timestamp desc",
    "properties": {
        "functionAlias": "myFunction"
    }
}
```

When you execute it a second time, you'll get the following error though: `A function with the same name already exists (ID: 'd939000a-438c-4b77-aa00-060335edf7f6')`. I've tried various things, but there doesn't seem to be a way to update an existing function. As a workaround, I first delete an existing function with the specified name before adding it again.

Here's an extract of the PowerShell script I've created. It uses the `az rest` command to call the REST API.

```powershell
$functions = az rest --method get --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/components/$AppInsightsName/analyticsItems?api-version=2015-05-01"
$function = $functions | ConvertFrom-Json | Where-Object -Property "name" -Value $FunctionName -EQ
if ($null -ne $function)
{
    az rest --method "DELETE" --url """https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/components/$AppInsightsName/analyticsItems/item?api-version=2015-05-01&includeContent=true&scope=shared&type=function&name=$FunctionName"""
}

$content = Get-Content -Path $FunctionFilePath
$content = $content -Replace """", "\"""  # Escape " in the query
foreach ($key in $Placeholders.Keys)
{
    $content = $content -Replace "##$key##", $Placeholders[$key]
}

$requestBodyPath = Join-Path $env:TEMP "create-shared-function-request-body.json"
Set-Content -Path $requestBodyPath -Value @"
{
    "scope": "shared",
    "type": "function",
    "name": "$FunctionName",
    "content": "$content",
    "properties": {
        "functionAlias": "$FunctionName"
    }
}
"@
az rest --method "PUT" --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/components/$AppInsightsName/analyticsItems/item?api-version=2015-05-01" --headers "Content-Type=application/json" --body "@$requestBodyPath"

```

See [deploy-shared-function.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/DeployAzureWorkbookAndAppInsightsFunction/app-insights-function/deploy-shared-function.ps1) for the full script. You can call it with the following command.

```powershell
$placeholders = @{
    "apimName" = "<api management name>";
}

.\deploy-shared-function.ps1 -SubscriptionId "<subscription id>" `
    -ResourceGroup "<resource group with app insights>" `
    -AppInsightsName "<app insights name>" `
    -FunctionName "ApimRequests" `
    -FunctionFilePath ".\ApimRequests.kql" `
    -Placeholders $placeholders
```


### Conclusion

Deploying an Azure Workbook is fairly straightforward. Placing the workbook JSON in a separate file as a nice improvement that makes it a lot easier to make small changes directly in the definition. It also makes it easier to see what has changed.

Deploying a function in Application Insights is poorly supported however. Using Bicep seems to be a no go at the moment. The only alternative is using the REST API. Hopefully the support will improve in the future.
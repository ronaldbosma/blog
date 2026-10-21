---
title: "Deploy Azure Workbooks with a Reusable Bicep Module"
date: 2026-10-21T11:39:00+02:00
publishdate: 2026-10-21T11:39:00+02:00
lastmod: 2026-10-21T11:39:00+02:00
tags: [ "Azure", "Azure Monitor", "Azure Workbook", "Bicep", "Infra as Code" ]
summary: "When deploying Azure Workbooks with Bicep, I use a module that constructs a stable resource name and an environment-specific display name, replaces placeholders in the workbook content and fails the deployment if any placeholders are left. In this post I explain how the module works and how to use it."
draft: true
---

When deploying [Azure Workbooks](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview) with Bicep, I tend to use a module that takes care of a couple of things for me. Without it, I found myself repeating the same boilerplate in every project: constructing a unique name, adding the environment to the display name and replacing environment-specific values in the workbook JSON. I've shared the module on GitHub, so you can use it too.

In this post I'll explain why the module is useful, walk through its logic and show how to use it. I've written about deploying workbooks before in [Deploy Azure Workbook and App Insights Function](/blog/2023/03/10/deploy-azure-workbook-and-app-insights-function/). That post explains how to deploy a workbook using Bicep. This post builds on that and wraps the logic in a reusable module.

### Table of Contents

- [Why a Module?](#why-a-module)
- [The Workbook Module](#the-workbook-module)
  - [Parameters](#parameters)
  - [Resource Name and Display Name](#resource-name-and-display-name)
  - [Replacing Placeholders](#replacing-placeholders)
  - [Failing on Unresolved Placeholders](#failing-on-unresolved-placeholders)
- [Sample Usage](#sample-usage)
- [Conclusion](#conclusion)

### Why a Module?

A workbook is deployed with the [Microsoft.Insights/workbooks](https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/workbooks?pivots=deployment-language-bicep) resource. The resource itself is simple, but a few details need extra attention:

- The resource name of a workbook is a GUID and not something readable. What you see in the Azure portal is the display name. You want the GUID to be stable, so a redeployment updates the existing workbook instead of creating a duplicate.
- When you deploy the same workbook to multiple environments in the same subscription, you want to be able to tell them apart. Adding the environment name to the display name solves that.
- The workbook JSON contains resource IDs, such as the ID of an Application Insights instance or an API Management service. These are different for each environment, so they have to be replaced before deployment.

The module handles all of these. You can find it [here](https://github.com/ronaldbosma/bicep-samples/tree/main/modules/workbook).

### The Workbook Module

Let's start with the parameters and then look at the logic in the module.

#### Parameters

The module has the following parameters:

| Name | Description | Value |
|---|---|---|
| `environmentName` | Name of the environment. Appended to the display name when not empty. | `string (default: '')` |
| `location` | Location of the workbook. | `string (required)` |
| `tags` | Tags to associate with the workbook. | `resourceInput<'Microsoft.Insights/workbooks@2023-06-01'>.tags?` |
| `displayName` | User-defined display name of the workbook. | `string (required)` |
| `serializedData` | The workbook content as a string with valid JSON. Placeholders use the format `##<name>##`. | `string (required)` |
| `placeholders` | Map of placeholder names to the values that replace them in `serializedData`. | `{ *: string }?` |
| `sourceId` | Resource ID of the source resource, such as an Application Insights instance or Log Analytics workspace. | `string (default: 'azure monitor')` |
| `category` | Workbook category. | `string (default: 'workbook')` |
| `version` | Workbook schema version, which should match the workbook content. | `string (default: 'Notebook/1.0')` |

The `tags` parameter reuses the type of the `tags` property of the workbook resource, so I don't have to define it myself. The `placeholders` parameter is optional, because not every workbook needs placeholders.

#### Resource Name and Display Name

The module starts with two variables and the workbook resource. This is the part that constructs the name and display name:

```bicep
var workbookDisplayName = environmentName == '' ? displayName : '${displayName} (${environmentName})'

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, displayName, environmentName)
  location: location
  tags: tags
  kind: 'shared' // Only valid value for kind is 'shared'
  properties: {
    displayName: workbookDisplayName
    category: category
    serializedData: ...
    sourceId: sourceId
    version: version
  }
}
```

The display name is what users see in the portal. If you specify `Sample Workbook` as display name and `dev` as environment name, the workbook is shown as `Sample Workbook (dev)`. Without an environment name, the display name is used as-is.

For the resource name, I use the [guid](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-string#guid) function with the resource group ID, display name and environment name as input. This creates a deterministic GUID. The same input always results in the same name, so redeploying the workbook updates it. Because the environment name is part of the input, workbooks for different environments in the same resource group also get different names.

The `kind` is set to `shared`. According to the comment I left in the module, that's the only valid value for this property.

#### Replacing Placeholders

The workbook content is a JSON string. To replace placeholders in that string, the module uses the approach I described in [Replace placeholders in string with user-defined Bicep function](/blog/2024/06/21/replace-placeholders-in-string-with-user-defined-bicep-function/). Please read that post for the full explanation of how the `reduce` function is used to replace multiple placeholders in a string. Here's the part of the module that does this:

```bicep
var workbookContent = placeholders == null ? serializedData : replacePlaceholders(serializedData, items(placeholders!))

#disable-next-line use-user-defined-types // The used reduce function expects an array, so using array as the type here is correct.
func replacePlaceholders(originalString string, placeholders array) string =>
  reduce(
    placeholders,
    originalString, // this is the first 'current'
    (current, next) => replacePlaceholder(current, next.key, next.value)
  )

func replacePlaceholder(originalString string, placeholder string, value string) string =>
  replace(originalString, '##${placeholder}##', value)
```

The `workbookContent` variable does the following:

- If no placeholders are specified, `serializedData` is used unchanged.
- If placeholders are specified, the `placeholders` object is converted to an array of key/value pairs with the [items](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-object#items) function. The `!` operator tells Bicep the value isn't null at that point.
- The `replacePlaceholders` function loops over that array with `reduce` and calls `replacePlaceholder` for each item.
- The `replacePlaceholder` function replaces a single placeholder with its value. A placeholder named `ApplicationInsightsId` is replaced where the content contains `##ApplicationInsightsId##`.

Compared to the functions in my earlier post, there are two differences. The functions are defined in the module itself to keep it self-contained, so you don't need to import anything. And the placeholder format is `##name##` instead of `$(name)`. This format makes it easy to detect placeholders that haven't been replaced, as you'll see next.

Because the values are inserted as-is, they need to be valid inside a JSON string. That's no problem for resource IDs and subscription IDs, but keep it in mind if you use other values.

#### Failing on Unresolved Placeholders

The last piece of logic is the `serializedData` property of the workbook, which I left out of the previous snippet. This is the complete line:

```bicep
serializedData: !like(workbookContent, '*##*##*') ? workbookContent : fail('Workbook "${workbookDisplayName}" still contains unresolved placeholders.')
```

The [like](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-string#like) function checks if the content contains two `##` markers with something optional around them. If it doesn't, the content is used as-is. If it does, a placeholder is left and the [fail](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-logical#fail) function stops the deployment with a message like this:

```text
Workbook "Sample Workbook (dev)" still contains unresolved placeholders.
```

That gives you an early and clear error instead of a workbook with empty or broken queries.

There's a limitation to this check. It matches any two occurrences of `##` in the content, not only the format of a placeholder. If your workbook has text items with Markdown headings, such as `## Heading`, two of them in one workbook would trigger the error. That's a trade-off for a simple check. If you run into this, you can change the placeholder format or make the check more specific.

### Sample Usage

Let's look at how to use the module. The following Bicep template deploys a workbook with the content loaded from a file:

```bicep
param environmentName string = 'dev'
param location string = resourceGroup().location

param tags { *: string } = {
  environment: environmentName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'appi-aisquick-sdc-taqld'
}

resource apiManagementService 'Microsoft.ApiManagement/service@2025-09-01-preview' existing = {
  name: 'apim-aisquick-sdc-taqld'
}

module workbook 'workbook.bicep' = {
  params: {
    environmentName: environmentName
    location: location
    tags: tags
    displayName: 'Sample Workbook'
    serializedData: string(loadJsonContent('./sample.workbook'))
    placeholders: {
      AzureSubscriptionId: subscription().subscriptionId
      ApplicationInsightsId: appInsights.id
      ApiManagementId: apiManagementService.id
    }
    sourceId: appInsights.id
  }
}
```

The workbook content is loaded with [loadJsonContent](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-files#loadjsoncontent) and converted back to a string, because the module expects the JSON as a string. The existing Application Insights and API Management resources are used to supply their resource IDs. The Application Insights instance is also the `sourceId` of the workbook.

The `sample.workbook` file is the workbook JSON that you can export from the Advanced Editor in the portal, as described in [my earlier post](/blog/2023/03/10/deploy-azure-workbook-and-app-insights-function/). In that file, you replace the hard-coded values with placeholders. A simplified example looks like this:

```json
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "requests | summarize count() by name",
        "queryType": 0,
        "resourceType": "microsoft.insights/components",
        "crossComponentResources": [ "##ApplicationInsightsId##" ]
      },
      "name": "requests-per-operation"
    }
  ]
}
```

When the module is deployed, `##ApplicationInsightsId##` is replaced with the resource ID of the Application Insights instance. The same goes for `##AzureSubscriptionId##` and `##ApiManagementId##` if you use them in your workbook. Because the environment name is `dev`, the workbook shows up as `Sample Workbook (dev)`.

### Conclusion

With this module, I no longer have to think about the details of deploying a workbook. It creates a stable resource name, makes the display name environment-specific, replaces placeholders in the workbook content and stops the deployment if a placeholder is left behind. That solves the problems I described at the start: repeated boilerplate, duplicate workbooks and broken queries after a deployment.

You can find the module and its README on [GitHub](https://github.com/ronaldbosma/bicep-samples/tree/main/modules/workbook). For more details on the workbook resource itself, see the [Microsoft.Insights/workbooks Bicep resource](https://learn.microsoft.com/en-us/azure/templates/microsoft.insights/workbooks?pivots=deployment-language-bicep) reference.

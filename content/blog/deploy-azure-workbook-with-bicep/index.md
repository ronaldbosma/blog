---
title: "Deploy Azure Workbook with Bicep"
date: 2023-02-03T00:00:00+02:00
publishdate: 2023-02-03T00:00:00+02:00
lastmod: 2023-02-03T00:00:00+02:00
tags: [ "Azure", "Bicep", "Infra as Code", "PowerShell" ]
summary: "In this post I explain how to deploy an Azure workbook using Bicep and set environment specific variables. To improve maintainability of the Bicep script, I convert the workbook JSON definition to a formatted Bicep object with PowerShell."
draft: true
---

For my current project I've created an [Azure Workbook](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview) to gain more insight into the use of our API's hosted in Azure API Management. We create and deploy all our resources with Bicep. So, I wanted to do the same with my workbook. In this blog post I'll show you how.

> If you're interested in creating your own workbooks. [The Azure Workbook documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview) is a good starting point.

### Table of contents

- [The workbook](#the-workbook)
- [Deploy with ARM template](#deploy-with-arm-template)
- [Deploy with Bicep object](#deploy-with-bicep-object)


### The workbook

Here's a screenshot of the workbook we'll be deploying.

![My Workbook](../../../../../images/deploy-azure-workbook-with-bicep/workbook.png)

The workbook has a couple of parameters and a table. All populated with query results from Application Insights. Here's an example of the query for the Subscription parameter.

```kusto
requests
| where customDimensions["Service ID"] == "my-api-management-dev"
| project Subscription = tostring(column_ifexists('customDimensions', '')['Subscription Name'])
| distinct Subscription
| sort by Subscription asc
```

Note the filter on the API Management instance `my-api-management-dev`. This name is environment specific and we're going to set this during deployment.

### Deploy with ARM template

I always start by creating my workbook through the Azure Portal in my Dev environment. Once you're done, you can download an ARM Template that you can convert to a Bicep script. To do this, open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-with-bicep/edit-workbook-advanced-editor.png)

Choose ARM Template as the Template Type and download the template. The result will look like [my-workbook-arm-template.json](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/exports/my-workbook-arm-template.json).

The ARM template can then be decompiled to a Bicep script with the following command. 
> You can find the Bicep CLI on [Bicep Tools](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)

```powershell
 bicep decompile ./my-workbook-arm-template.json
```

The result will be a Bicep file like the snippet below. See [my-workbook-arm-template.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/exports/my-workbook-arm-template.bicep) for the full script.

```bicep
@description('The friendly name for the workbook that is used in the Gallery or Saved List.  This name must be unique within a resource group.')
param workbookDisplayName string = 'My Workbook'

@description('The gallery that the workbook will been shown under. Supported values include workbook, tsg, etc. Usually, this is \'workbook\'')
param workbookType string = 'workbook'

@description('The id of resource instance to which the workbook will be associated')
param workbookSourceId string = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-test/providers/microsoft.insights/components/my-application-insights-dev'

@description('The unique guid for this workbook instance')
param workbookId string = newGuid()

resource workbookId_resource 'microsoft.insights/workbooks@2021-03-08' = {
  name: workbookId
  location: resourceGroup().location
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    serializedData: '{"version":"Notebook/1.0","items":[{"type":9,"content":{"version":"KqlParameterItem/1.0",.......'
    version: '1.0'
    sourceId: workbookSourceId
    category: workbookType
  }
  dependsOn: []
}

output workbookId string = workbookId_resource.id
```

The workbook definition is set through the `serializedData` property. As you can see it's one long string that contains the entire workbook definition. Including hardcoded environment specific values, like the API Management instance name `my-api-management-dev`.

To make it deployable to multiple environments, add an extra parameter to the Bicep script for the API Management instance name as shown below.

```bicep
@description('The name of the API Management resource that is queried in the workbook.')
param apimResourceName string = 'my-api-management-dev'
``` 

You can then replace every value of `my-api-management-dev` with `${apimResourceName}` in the workbook definition string.

The biggest downside of this solution is that the entire workbook definition is a serialized string on one line. This makes it difficult to make minor changes directly in the definition or to see what has changed during a review. You'll also need to replace the environment specific values with parameters (or variables) after every change to the workbook and export of the ARM template.

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
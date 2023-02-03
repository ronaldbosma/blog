---
title: "Deploy Azure Workbook with Bicep"
date: 2023-02-03T00:00:00+02:00
publishdate: 2023-02-03T00:00:00+02:00
lastmod: 2023-02-03T00:00:00+02:00
tags: [ "Azure", "Bicep", "Infra as Code" ]
summary: "In this post I explain how to deploy an Azure workbook using Bicep and use environment specific variables. To improve maintainability of the Bicep script, I convert the workbook JSON definition to a formatted Bicep object with PowerShell."
draft: true
---

At my current project I've created an [Azure Workbook](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview) to gain more insights into the use of our API's hosted in Azure API Management. We create and deploy all our resources with Bicep. So I wanted to do the same with my workbook. In this blog post I'll show you how.

> If you're interested in creating you're own workbooks. The [Azure Workbook](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview) documentation is a good starting point.

### Table of contents

- [The workbook](#the-workbook)
- [Use ARM Template](#use-arm-template)
- [Use Bicep object](#use-bicep-object)


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

### Use ARM Template

I always start by creating my workbook through the Azure Portal in my Dev environment. Once your done, you can download an ARM Template that you can convert to a Bicep script. To do this, open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-with-bicep/edit-workbook-advanced-editor.png)

Choose ARM Template as the Template Type and download the template. The result will look like [my-workbook-arm-template.json](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/exports/my-workbook-arm-template.json).

The ARM template can then be decompiled to a Bicep script with the following command. 
> You can find the Bicep CLI on [Bicep Tools](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)

```powershell
 bicep decompile .\my-workbook-arm-template.json
```

The result will be a Bicep file similar to the snippet below. See [my-workbook-arm-template.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/exports/my-workbook-arm-template.bicep) for the full script.

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

The value of the `serializedData` property is one long string that contains the entire workbook definition. This includes the hardcoded environment specific API Management instance name `my-api-management-dev`.

To make it deployable on multiple environments, add an extra parameter for the API Management instance name as shown below.

```bicep
@description('The name of the API Management resource that is queried in the workbook.')
param apimResourceName string = 'my-api-management-dev'
``` 

You can then replace every value of `my-api-management-dev` with `${apimResourceName}` in the workbook definition.

The biggest downside of this solution is that the entire workbook definition is a serialized string on one line. This makes it difficult to make small changes directly in the definition, to see what has changed and perform a review. You'll also need to replace the environment specific values with parameters (or variables) every single time.

### Use Bicep object

To solve this problem I convert the workbook JSON definition into a Bicep object that can be used inside the Bicep script. The first step is to download the workbook definition. Open the workbook in Edit mode and click the Advanced Editor button.

![Edit Workbook - Advanced Editor](../../../../../images/deploy-azure-workbook-with-bicep/edit-workbook-advanced-editor.png)

Choose Gallery Template as the Template Type and download the template. The result will be a JSON file containing only the definition of the workbook. It should look like [my-workbook.workbook](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/exports/my-workbook.workbook).

To use this in the Bicep script, we need to convert the JSON to valid Bicep. I've created the following PowerShell script to do this.

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

When this script is executed, the `my-workbook.workbook` is loaded and we loop over every line performing the following transformations:
1. Bicep property names are not surround by ", so we remove them from the property names.
1. Escape all occurences of ' with \`'. This will escape for instance a ' that is used in a query.
1. Bicep string values should be surround by ', so replace the " surround the values with a '. Also removing any trailing , at the end of the line.
1. Remove all trailing , that were skipped by the previous step (e.g. in case of non string property values).
1. The " in values was escaped with a \ but now that the values are surround with a ' the escape character is no longer required and we remove it.
1. Remove the JSON schema property.
1. Replace all environment specific values with variables/parameters. E.g. `my-api-management-dev` becomes `${apimResourceName}`.

The result is a Bicep file that looks like [my-workbook-definition.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/exports/my-workbook-definition.bicep).

You can put the contents of the definition file in the following Bicep script as the value of the `definition` variable. Before setting the `serializedData` property, the variable is converted to a string using the `string()` function.

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

After saving the Bicep file, it should look like [my-workbook.bicep](https://github.com/ronaldbosma/blog-code-examples/tree/master/DeployAzureWorkbookWithBicep/my-workbook.bicep). The definition variable now contains the definition of the workbook as a Bicep object. Because it's formatted instead of a one liner string, it's easier to make small changes, see what has changed and perform a review. 

You can now deploy the workbook using the following Azure CLI command and your done.

```powershell
az deployment group create `
    --name 'my-workbook-deployment' `
    --resource-group 'my-resource-group' `
    --template-file './my-workbook.bicep' `
    --verbose
```
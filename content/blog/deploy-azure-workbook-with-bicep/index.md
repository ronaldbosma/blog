---
title: "Deploy Azure Workbook with Bicep"
date: 2023-02-03T00:00:00+02:00
publishdate: 2023-02-03T00:00:00+02:00
lastmod: 2023-02-03T00:00:00+02:00
tags: [ "Azure", "Bicep", "Infra as Code" ]
draft: true
---


```powershell
 bicep decompile .\my-workbook-arm-template.json
```


```powershell
$sourceFile = "./my-workbook.workbook"
$targetFile = "./my-workbook.bicep"

# Key value pair of variables that should replace environment specific values
$variables = @{
    "apimResourceName" = "my-api-management-dev";
    "appInsights.id" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/my-test/providers/microsoft.insights/components/my-application-insights-dev"
}

$workbook = Get-Content -Path $sourceFile

# For each line in the workbook
for ($i = 0; $i -lt $workbook.Count; $i++)
{
    # Remove " surrounding the property names
    $workbook[$i] = $workbook[$i] -replace '"(.+)":', '$1:'

    # Replace ' with \` so the ` is escaped in values
    $workbook[$i] = $workbook[$i] -replace "'", "\'"

    # Replace " surrounding the values with ' and remove the trailing ,
    $workbook[$i] = $workbook[$i] -replace '"(.*)",?$', '''$1'''

    # Remove leftover trailing ,
    $workbook[$i] = $workbook[$i] -replace ',$', ''

    # Replace \" with ". No need to escape the " in values because the values are surrounded with ' instead of "
    $workbook[$i] = $workbook[$i] -replace '\\"', '"'

    # Remove the JSON schema reference
    $workbook[$i] = $workbook[$i].Replace("`$schema: 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'", "")

    # Replace environment specific values with variables
    foreach ($variable in $variables.Keys)
    {
        $workbook[$i] = $workbook[$i] -replace $variables[$variable],"`${$variable}"
    }
}

Set-Content -Path $targetFile -Value $workbook
```



```powershell
az deployment group create `
    --name 'my-workbook-deployment' `
    --resource-group 'my-resource-group' `
    --template-file './my-workbook.bicep' `
    --verbose
```
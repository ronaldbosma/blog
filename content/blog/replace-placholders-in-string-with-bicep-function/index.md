---
title: "Replace placeholders in string with Bicep function"
date: 2024-06-12T17:00:00+02:00
publishdate: 2024-06-12T17:00:00+02:00
lastmod: 2024-06-12T17:00:00+02:00
tags: [ "Azure", "Bicep", "Test Automation" ]
draft: true
---

When you have a string value in Bicep with multiple placeholders that you want to replace. It can be tricky to find a good way to do this. In this blog post, I will show you how you can replace placeholders in a string with a couple of user-defined functions.

Normally in Bicep, you would use string interpolation to set environment specific values in a resource. In some cases I find it useful to store certain data in a separate text file and use one of the [file functions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions#file-functions) to read the content of the file and use it in Bicep. For example, I do this when deploying an Azure workbook like I explained in one of my previous blog posts. See [Deploy Azure Workbook and App Insights Function](/blog/2023/03/10/deploy-azure-workbook-and-app-insights-function/). In such a case, I add placeholders to the input file in a certain format and replace them with the actual values before deploying the resource.

For example, if I have the following input string, where a placeholder is defined with the format `$(placeholder)`:

```bicep
var input = '''
  first = $(first)
  second = $(second)
  third = $(third)
  '''
```

And I have the following dictionary with placeholders and values:

| Placeholder | Value |
|-|-|
| first | one |
| second | 2 |
| third | III |

Then, after replacing the placeholders, the end result should the following string:

```bicep
first = one
second = 2
third = III
```

In for example C#, I would create a dictionary with placeholders as keys and the actual values as values. Then I would loop through the dictionary and replace the placeholders with the actual values. Unfortunately, in Bicep, variables are immutable. So, you can't just loop through a dictionary and replace the placeholders in the input string. 

Up until now, I've been using 'temporary' variables to store the intermediate results. See the following example:

```bicep
var input = '''
  first = $(first)
  second = $(second)
  third = $(third)
  '''

var temp1 = replace(input, 'first', 'one')
var temp2 = replace(temp1, 'second', '2')
var result = replace(temp2, 'third', 'III')
```

This can become quite cumbersome when you have a lot of placeholders. It's also not very flexible and a mistake is easily made. I've had quite a few times that I used the wrong variable as an input for the replace function, resulting an incorrect output.


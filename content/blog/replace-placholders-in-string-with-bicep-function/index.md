---
title: "Replace placeholders in string with user-defined Bicep function"
date: 2024-06-12T17:00:00+02:00
publishdate: 2024-06-12T17:00:00+02:00
lastmod: 2024-06-12T17:00:00+02:00
tags: [ "Azure", "Bicep", "Test Automation" ]
draft: true
---

When you have a string value in Bicep with multiple placeholders that you want to replace. It can be tricky to find a good way to do this. In this blog post, I will show you how you can replace placeholders in a string with a couple of user-defined functions.

Normally in Bicep, you would use string interpolation to set environment specific values in a resource. In some cases I find it useful to store certain data in a separate text file and use one of the [file functions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions#file-functions) to read the content of the file and use it in Bicep. For example, I do this when deploying an Azure workbook like I explained in one of my previous blog posts. See [Deploy Azure Workbook and App Insights Function](/blog/2023/03/10/deploy-azure-workbook-and-app-insights-function/). In such a case, I add placeholders to the input file in a certain format and replace them with the actual values before deploying the resource.

For example, if we have the following input string, where a placeholder is defined with the format `$(placeholder)`:

```bicep
var input = '''
  first = $(first)
  second = $(second)
  third = $(third)
  '''
```

And we have the following dictionary with placeholders and values:

```bicep
var placeholders = {
  first: 'one'
  second: '2'
  third: 'III'
}
```

Then, after replacing the placeholders, the end result should be as follows:

```bicep
var result = '''
  first = one
  second = 2
  third = III
  '''
```

In for example C#, I would create a dictionary with placeholders as keys and the actual values as values. Then I would loop through the dictionary and replace the placeholders with the actual values. Unfortunately, in Bicep, variables are immutable. So, you can't just loop through a dictionary and replace the placeholders in the input string. 

Up until now, I've been using 'temporary' variables to store the intermediate results. See the following example:

```bicep
var input = '''
  first = $(first)
  second = $(second)
  third = $(third)
  '''

var temp1 = replace(input, '$(first)', 'one')
var temp2 = replace(temp1, '$(second)', '2')
var result = replace(temp2, '$(third)', 'III')
```

This can become quite cumbersome when you have a lot of placeholders. It's also not very flexible and a mistake is easily made. I've had quite a few times that I used the wrong variable as an input for the replace function, resulting in incorrect output.

With the introduction of user-defined functions, I thought I could perhaps use a recursive function to loop over the placeholders and replace them with the actual values. However, Bicep doesn't allow functions to call themselves directly or indirectly. So, I had to come up with another solution.

Fortunately, I found the [reduce](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-lambda#reduce) function, which actually has been around for a couple of years already. This function reduces an array to a single value. The signature is:

```bicep
reduce(inputArray, initialValue, lambda expression)
```

We can pass our placeholders into the `inputArray`, the initial string into the `initialValue` and use the `lambda expression` to replace the placeholders with the actual values. The lambda expression has the current and next value parameters and an optional index.

The following Bicep code shows how you can use the `reduce` function to replace placeholders in a string:

```bicep
var input = '''
  first = $(first)
  second = $(second)
  third = $(third)
  '''

var placeholders = {
  first: 'one'
  second: '2'
  third: 'III'
}

var placeholdersArray = items(placeholders)
var result = reduce(
  placeholdersArray, 
  input, // this is the first 'current'
  (current, next) => replace(string(current), '$(${next.key})', next.value)
)
```
We first convert the placeholders object to an array. Then we use the `reduce` function to loop over the placeholders. On the first iteration, `current` will have the value of the `input` string and `next` will be the first item in the `placeholders` array. The result of `replace` will be the new `current` value for the next iteration. 

If `input` has the value `$(first) $(second) $(third)` and we use the placeholders from our previous example, then it would look like this:

---
| index | current | next | result of replace |
|-|-|-|-|
| 1 | `'$(first) $(second) $(third)'` | 	`{ first: one }` | `'one $(second) $(third)'` |
| 2 | `'one $(second) $(third)'` | `{ second: 2 }` | `'one 2 $(third)'` |
| 3 | `'one 2 $(third)'` | `{ third: III }` | `'one 2 III'` |
---


We can create a user-defined function to convert this into reusable logic. See the following code:

```bicep
@export()
func replacePlaceholders(originalString string, placeholders { *: string }) string =>
  replacePlaceholderInternal(originalString, items(placeholders))

func replacePlaceholderInternal(originalString string, placeholders array) string =>
  reduce(
    placeholders, 
    originalString, // this is the first 'current'
    (current, next) => replacePlaceholder(current, next.key, next.value)
  )

@export()
func replacePlaceholder(originalString string, placeholder string, value string) string =>
  replace(originalString, '$(${placeholder})', value)
```

As you can see, I've created 3 functions:
1. The `replacePlaceholders` function is the one you can call from your Bicep code. It takes the original string and a dictionary with placeholders and values. The values have to be of type string as specified by `{ *: string }`. It converts the `placeholders` object into an array and calls `replacePlaceholderInternal`.
1. The `replacePlaceholderInternal` function uses the `reduce` function to loop over the placeholders and call the `replacePlaceholder` function for each placeholder. 
1. The `replacePlaceholder` function replaces the placeholder with the actual value. I've made this a separate function, so you can call it directly if you want to replace a single placeholder.

And here's a sample of how you can use the `replacePlaceholders` function in your Bicep code:

```bicep
import { replacePlaceholders } from './replace-placeholders.bicep'

var input = '''
  first = $(first)
  second = $(second)
  third = $(third)
  '''
var placeholders = {
  first: 'one'
  second: '2'
  third: 'III'
}

var result = replacePlaceholders(input, placeholders)
```

You can find the final result [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/replace-placholders-in-string-with-bicep-function/replace-placeholders.bicep). Similar to my previous blog post, I've written some tests to verify the behavior of the `replacePlaceholders` function. You can find the tests [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/replace-placholders-in-string-with-bicep-function/tests.bicep). For more information on the (experimental) Bicep Testing Framework, see [my previous post]([my previous blog post](/blog/2024/06/05/apply-azure-naming-convention-using-bicep-functions/#testing-the-function)) or checkout the blog post [Exploring the awesome Bicep Test Framework](https://rios.engineer/exploring-the-bicep-test-framework-%F0%9F%A7%AA/) by Dan Rios.

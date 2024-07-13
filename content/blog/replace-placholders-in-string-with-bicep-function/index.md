---
title: "Replace placeholders in string with user-defined Bicep function"
date: 2024-06-21T15:00:00+02:00
publishdate: 2024-06-21T15:00:00+02:00
lastmod: 2024-06-21T15:00:00+02:00
summary: When you have a string value in Bicep with multiple placeholders that you want to replace, it can be tricky to find a good way to do this. In this blog post, I will show you how you can replace placeholders in a string with a couple of user-defined functions.
tags: [ "Azure", "Bicep", "Infra as Code", "Test Automation" ]
---

When you have a string value in Bicep with multiple placeholders that you want to replace, it can be tricky to find a good way to do this. In this blog post, I will show you how you can replace placeholders in a string with a couple of [user-defined functions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/user-defined-functions).

Normally in Bicep, you would use string interpolation to set environment-specific values in a resource. In some cases, I find it useful to store certain data in a separate text file and use one of the [file functions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions#file-functions) to read the content of the file and use it in Bicep. For example, I do this when deploying an Azure workbook, as I explained in one of my previous blog posts: [Deploy Azure Workbook and App Insights Function](/blog/2023/03/10/deploy-azure-workbook-and-app-insights-function/). In such a case, I add placeholders to the input file in a specific format and replace them with the actual values before deploying the resource.

For example, if we have the following input string, where a placeholder is defined with the format `$(placeholder)`:

```bicep
var input = '''
  first = $(first)
  second = $(second)
  third = $(third)
  '''
```

Here's the continuation with the reviewed and refined text:

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

This can become quite cumbersome when you have a lot of placeholders. It's also not very flexible, and a mistake is easily made. I've had quite a few times when I used the wrong variable as an input for the replace function, resulting in incorrect output.

With the introduction of user-defined functions, I thought I could perhaps use a recursive function to loop over the placeholders and replace them with the actual values. However, Bicep doesn't allow functions to call themselves directly or indirectly. So, I had to come up with another solution.

Fortunately, I found the [reduce](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions-lambda#reduce) function, which has actually been around for a couple of years already. This function reduces an array to a single value. The signature is:

```bicep
reduce(inputArray, initialValue, lambda expression)
```

We can pass our placeholders into the `inputArray`, the initial string into the `initialValue`, and use the `lambda expression` to replace the placeholders with the actual values. The lambda expression has the current and next value parameters and an optional index.

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

We can create a [user-defined function](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/user-defined-functions) to convert this into reusable logic. See the following code:

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

1. The `replacePlaceholders` function is the one you can call from your Bicep code. It takes the original string and a object with placeholders and values. The values have to be of type string as specified by `{ *: string }`. It converts the `placeholders` object into an array and calls `replacePlaceholderInternal`.
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

You can access the final Bicep code [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/replace-placholders-in-string-with-bicep-function/replace-placeholders.bicep).

Similar to my previous blog post, I've included tests to validate the functionality of the `replacePlaceholders` function. You can view the test cases and implementation details [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/replace-placholders-in-string-with-bicep-function/tests.bicep). For more insights on the (experimental) Bicep Testing Framework used, refer to [my previous blog post](/blog/2024/06/05/apply-azure-naming-convention-using-bicep-functions/#testing-the-function).

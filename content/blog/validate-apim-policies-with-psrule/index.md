---
title: "Validate API Management policies with PSRule"
date: 2024-08-12T00:00:00+02:00
publishdate: 2024-08-12T00:00:00+02:00
lastmod: 2024-08-12T00:00:00+02:00
tags: [ "Azure", "API Management", "Infra as Code", "PSRule", "Test Automation" ]
draft: true
---

I've been working with Azure API Management for a while now, and one of the challenges I’ve faced is finding a reliable way to validate the XML policies I write. When working with .NET, tools like SonarQube are available for code quality checks, but these tools don’t support the kind of checks I want to perform on the policies used in Azure API Management.

After some searching, I discovered [PSRule](https://microsoft.github.io/PSRule)—a cross-platform PowerShell module to validate infrastructure as code (IaC) files and objects using PowerShell rules. It's created by Bernie White and hosted on the Microsoft Github account [here](https://github.com/microsoft/PSRule). It's also included in [Microsoft Defender for Cloud](https://learn.microsoft.com/en-us/azure/defender-for-cloud/iac-vulnerabilities#view-details-and-remediation-information-for-applied-iac-rules) as part of Template Analyzer.

In this blog post, I’ll demonstrate how to use PSRule to validate your Azure API Management policies. But fefore we start, let's start with some requirements first.


### Requirements

First off, we'll store our policies in separate files. This makes it easier to manage and maintain them. I commonly use the `.cshtml` file extension for these files, because it this enables IntelliSense on policies when using the [Azure API Management for VS Code](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-apimanagement) extension. So, PSRule will need to recognize these files as API Management policies.

As you might be aware, policies in API Management can be applied to different [scopes](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-policies#scopes). We'll be creating several rules, where some will apply to all scopes and others to specific scopes. Because there's nothing in the policy files to indicate the scope, we'll use the file name to determine the scope. For example, a file named `test.api.cshtml` will apply to the API scope, while a file named `test.operation.cshtml` will apply to the operation scope.

We'll create the following custom rules:
1. The inbound section should always start with a `base` policy to make sure important logic, like security checks, are applied first. This rule should apply to all scopes, except for the global scope and policy fragments.
1. Files with the `.cshtml` extension should following the naming convention and specify the scope.
1. The subscription key header (`Ocp-Apim-Subscription-Key`) should be removed in the inbound section of the global policy to prevent it from being forwarded to the backend.
1. A `set-backend-service` policy should use a backend entity (by setting the `backend-id` attribute) so the backend configuration is reusable and easier to maintain.
1. Files with API Management policies should have valid XML syntax.


### Sample policies

We'll need some sample policies to test our rules against. You can download them [here](https://github.com/ronaldbosma/blog-code-examples/raw/master/validate-apim-policies-with-psrule/start-sample-policies.zip). Create a new root folder and unzip the sample policies in this folder. You should now have the following folder structure:

```
/your-root
    /src
        /good
            global.cshtml
            good.api.cshtml
        /bad
            global.cshtml
            bad.api.cshtml
```

Have a look at the different policies. The files in the `good` folder conform to the rules we'll create, while the ones in the `bad` folder don't.


### Load policies using convention

At this moment in time, PSRule doesn't support loading XML files out-of-the-box. I've created an issue for this on Github, which can be found [here](https://github.com/microsoft/PSRule/issues/1537). Luckily, PSRule is extensible, and Bernie White, the creator of PSRule, has provided a sample in my issue that we can use to load XML files. It uses a [convention](https://microsoft.github.io/PSRule/stable/concepts/PSRule/en-US/about_PSRule_Conventions/).

Conventions, rules and other PSRule relates files are commonly stored in a `.ps-rule` folder in the root of your repository as described [here](https://microsoft.github.io/PSRule/v2/authoring/storing-rules/). You can create this folder in the root

Inside the `.ps-rule` folder, create a file named `APIM.Policy.Conventions.Rule.ps1` (_the `.Rule.ps1` extension is required for PSRule to recognize the file_). Add the following code to the file:

```powershell
# Synopsis: Imports the APIM XML policy file for analysis. File names should match: *.cshtml
Export-PSRuleConvention "APIM.Policy.Conventions.Import" -Initialize {

    $policies = @()
    $policyFiles = Get-ChildItem -Path "." -Include "*.cshtml" -Recurse -File

    foreach ($policyFile in $policyFiles) {
        # Use the relative path of the file as the object name, this makes it easier to e.g. apply suppressions.
        # Also replace backslashes with forward slashes, so the path doesn't differ between Windows and Linux.
        # Example: ./src/my.api.cshtml
        $name = ($policyFile.FullName | Resolve-Path -Relative).Replace('\', '/')

        $policies += [PSCustomObject]@{
            Name = $name
            Content = [Xml](Get-Content -Path $policyFile.FullName -Raw)
        }
    }

    $PSRule.ImportWithType("APIM.Policy", $policies);
}
```

This convention will select all files with the `.cshtml` extension and create a custom object with the name and the XML content of the file. 

The object's name is used by PSRule to identify the object in output and in suppressions. I prefer using the relative path because this makes it easier to manage. Any `\` in the path is also replaced with `/` to ensure the path is consistent across platforms.

At the end of the convention, the policies are imported with the `APIM.Policy` type. We'll use this type to apply our rules only to API Management policies, and not to other file types and objects.

The last step is to include the convention in the PSRule configuration. Create a file named `ps-rule.yml` in the `.ps-rule` folder and add the following content:

```yaml
binding:
  preferTargetInfo: true
  
convention:
  include:
  - 'APIM.Policy.Conventions.Import'
```

Setting `preferTargetInfo` to `true` will make sure that PSRule uses the `APIM.Policy` type for our policies. The convention `APIM.Policy.Conventions.Import` is included to actually import the policies.


### Implement first rule APIM.Policy.InboundBasePolicy

Now, if you would execute PSRule from the root folder using the following command, you'll get the message `WARNING: Could not find a matching rule. Please check that Path, Name and Tag parameters are correct` because we haven't created any rules yet. 

```powershell
Invoke-PSRule -InputPath ".\src\" -Option ".\.ps-rule\ps-rule.yaml"
```

Let's start with the first rule:  

_The inbound section should always start with a `base` policy to make sure important logic, like security checks, are applied first. This rule should apply to all scopes, except for the global scope and policy fragments._

Create a new file named `APIM.Policy.Rule.ps1` in the `.ps-rule` folder and add the following code:

```powershell
# Synopsis: The first policy inside the inbound section should be the base policy to make sure important logic like security checks are applied first.
Rule "APIM.Policy.InboundBasePolicy" -Type "APIM.Policy" {
    $policy = $TargetObject.Content.DocumentElement
    
    $Assert.HasField($policy, "inbound")
    $Assert.HasField($policy.inbound, "base")
    $Assert.HasFieldValue($policy, "inbound.FirstChild.Name", "base")
}
```

The [Rule](https://microsoft.github.io/PSRule/v2/concepts/PSRule/en-US/about_PSRule_Rules/) keyword is used to define a new rule. The name of the rule is `APIM.Policy.InboundBasePolicy` and it applies to the `APIM.Policy` type that we've specified in our convention. This will make sure that the rule is only executed on our API Management policies. Other files and objects will be ignored by this rule.

The `Synopsis` is a short description of the rule. It's used in the output of PSRule to describe the rule. More information on documentation can be found [here](https://microsoft.github.io/PSRule/v2/concepts/PSRule/en-US/about_PSRule_Docs/).

The [$TargetObject](https://microsoft.github.io/PSRule/v2/concepts/PSRule/en-US/about_PSRule_Variables/#targetobject) is the object that is processed by the rule. In our case, it's the custom object that we created in the convention for each `.cshtml` file. The `Content` property contains the XML content of the policy file and is of type [XmlDocument](https://learn.microsoft.com/en-us/dotnet/api/system.xml.xmldocument?view=net-8.0).

Using the different [assertion methods](https://microsoft.github.io/PSRule/v2/concepts/PSRule/en-US/about_PSRule_Assert/) that come with PSRule, we check that the inbound section exists, that the base policy exists inside the inbound section and that it's the first policy in the inbound section.

Run PSRule again using the following command:

```powershell
Invoke-PSRule -InputPath ".\src\" -Option ".\.ps-rule\ps-rule.yaml"
```

The output should look similar to this:

![Output](../../../../../images/validate-apim-policies-with-psrule/output-inboundbasepolicy-1.png)

As you can see, the rule was executed on all policy files. Only the `good.api.cshtml` file conforms to the rule and passes. All other files fail the rule. 

> Although the `.cshtml` files are processed, we still get warnings from PSRule that the files have not been processed because no matching rules were found. This is most likely due to the fact that we're importing these files using a custom convention. By adding the `-WarningAction Ignore` parameter, you can suppress these warnings.


### Filter on scope

The `APIM.Policy.InboundBasePolicy` rule should have been skipped for the two global policy files because the `base` policy can't be used at the global scope since there is now higher level. We can add a filter to the rule to exclude the global scope, but first we'll need to determine the scope of the policy during the import.

Open `APIM.Policy.Conventions.Rule.ps1` and replace its contents with the following code:

```powershell
# Synopsis: Imports the APIM XML policy file for analysis. File names should match: *.cshtml
Export-PSRuleConvention "APIM.Policy.Conventions.Import" -Initialize {

    $policies = @()
    $policyFiles = Get-ChildItem -Path "." -Include "*.cshtml" -Recurse -File

    foreach ($policyFile in $policyFiles) {
        # Use the relative path of the file as the object name, this makes it easier to e.g. apply suppressions.
        # Also replace backslashes with forward slashes, so the path doesn't differ between Windows and Linux.
        # Example: ./src/my.api.cshtml
        $name = ($policyFile.FullName | Resolve-Path -Relative).Replace('\', '/')

        # Determine the scope of the policy based on the file name.
        $scope = $null
        if ($policyFile.Name -eq "global.cshtml") { $scope = "Global" }
        elseif ($policyFile.Name.EndsWith(".workspace.cshtml")) { $scope = "Workspace" }
        elseif ($policyFile.Name.EndsWith(".product.cshtml")) { $scope = "Product" }
        elseif ($policyFile.Name.EndsWith(".api.cshtml")) { $scope = "API" }
        elseif ($policyFile.Name.EndsWith(".operation.cshtml")) { $scope = "Operation" }
        elseif ($policyFile.Name.EndsWith(".fragment.cshtml")) { $scope = "Fragment" }

        # Only create a policy object to analyse if the scope is recognized.
        if ($null -ne $scope) {
            $policies += [PSCustomObject]@{
                Name = $name
                Scope = $scope
                Content = [Xml](Get-Content -Path $policyFile.FullName -Raw)
            }
        }
    }

    $PSRule.ImportWithType("APIM.Policy", $policies);
}
```

We determine the scope of the policy based on the file name. The scope is stored in the `Scope` property of the custom object. If we can't determine the scope, no object is created. We'll create a another rule in the next section to check if all `.cshtml` files have a valid scope.

Now we can add a filter to the `APIM.Policy.InboundBasePolicy` rule to exclude the global scope and policy fragments. Open `APIM.Policy.Rule.ps1` and replace its contents with the following code:

```powershell
# Synopsis: The first policy inside the inbound section should be the base policy... to make sure important logic like security checks are applied first.
Rule "APIM.Policy.InboundBasePolicy" `
    -If { $TargetObject.Scope -ne "Global" -and $TargetObject.Scope -ne "Fragment" } `
    -Type "APIM.Policy" `
{
    $policy = $TargetObject.Content.DocumentElement
    
    $Assert.HasField($policy, "inbound")
    $Assert.HasField($policy.inbound, "base")
    $Assert.HasFieldValue($policy, "inbound.FirstChild.Name", "base")
}
```

The `-If` parameter is used to only execute the rule if the scope is not `Global` and not `Fragment`.

Run PSRule again using the following command:

```powershell
Invoke-PSRule -InputPath ".\src\" -Option ".\.ps-rule\ps-rule.yaml" -WarningAction Ignore
```

The output should now only display the results for the API scoped files as show below:

![Output](../../../../../images/validate-apim-policies-with-psrule/output-inboundbasepolicy-2.png)


### Implement rule APIM.Policy.FileExtension

As mentioned in the previous section, we want to check that each `.cshtml` file has a valid scope. So, we'll create the following rule for this:

_Files with the `.cshtml` extension should following the naming convention and specify the scope._

Let's start by creating a new file that doesn't specify a scope in the name. Navigate to the `bad` folder, create a file named `unknown-scope.cshtml` and add the following content: `<policies/>`. When you run PSRule this file should still be ignored, because we haven't created a rule for it yet.

Now, open `APIM.Policy.Rule.ps1` and add the following rule:

```powershell
# Synopsis: APIM policy file name should specify the scope. The name should be global.cshtml or end with: .workspace.cshtml, .product.cshtml, .api.cshtml, .operation.cshtml, or .fragment.cshtml.
Rule "APIM.Policy.FileExtension" -Type ".cshtml" {
    
    $knownScope = $TargetObject.Name -eq "global.cshtml" -or `
                  $TargetObject.Name.EndsWith(".workspace.cshtml") -or 
                  $TargetObject.Name.EndsWith(".product.cshtml") -or 
                  $TargetObject.Name.EndsWith(".api.cshtml") -or 
                  $TargetObject.Name.EndsWith(".operation.cshtml") -or 
                  $TargetObject.Name.EndsWith(".fragment.cshtml")

    if ($knownScope) {
        $Assert.Pass()
    } else {
        $Assert.Fail("Unknown API Management policy scope. Expected file name global.cshtml or name ending with: .workspace.cshtml, .product.cshtml, .api.cshtml, .operation.cshtml, or .fragment.cshtml")
    }
}
```

As you can see, the `-Type` parameter filters on `.cshtml` files, not on the `APIM.Policy` as was the case with the previous rule. This rule is executed on all `.cshtml` files, even if our convention didn't import them as `APIM.Policy` objects.

The rule checks if the file name specifies a valid scope. If the file name is `global.cshtml` or ends with `.workspace.cshtml`, `.product.cshtml`, `.api.cshtml`, `.operation.cshtml`, or `.fragment.cshtml`, the rule passes. Otherwise, it fails.

When you execute PSRule again, you should see that the `APIM.Policy.FileExtension` rule is executed for each `.cshtml` file. The `unknown-scope.cshtml` file should fail the rule.

> By adding the `-Outcome Fail` parameter, PSRule will only output the failures. And if you're only interested in the results of a single rule, you can use the `-Name`. For example: `-Name "APIM.Policy.InboundBasePolicy"`.


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
1. The inbound section should always start with a `base` policy to make sure important logic, like security checks, are applied first. This rule should apply to all levels, except for the global level and policy fragments.
1. The subscription key header (`Ocp-Apim-Subscription-Key`) should be removed in the inbound section of the global policy to prevent it from being forwarded to the backend.
1. A `set-backend-service` policy should use a backend entity (by setting the `backend-id` attribute) so the backend configuration is reusable and easier to maintain.
1. Files with the `.cshtml` extension should following the naming convention and specify the scope.
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

Have a look at the different policies. The ones in the `good` folder conform to the rules we'll create, while the ones in the `bad` folder don't.


### Load policies using convention

At this moment in time, PSRule doesn't support loading XML files out-of-the-box. I've created an issue for this on Github, which can be found [here](https://github.com/microsoft/PSRule/issues/1537). Luckily, PSRule is extensible, and Bernie White, the creator of PSRule, has provided a sample in my issue that we can use to load XML files. It uses a [convention](https://microsoft.github.io/PSRule/stable/concepts/PSRule/en-US/about_PSRule_Conventions/).

Conventions, rules and other PSRule relates files are commonly stored in a `.ps-rule` folder in the root of your repository as described [here](https://microsoft.github.io/PSRule/v2/authoring/storing-rules/). So create this folder. 

Inside the `.ps-rule` folder, create a file named `APIM.Policy.Conventions.Rule.ps1`. Note that the `.Rule.ps1` extension is required for PSRule to recognize the file. Add the following code to the file:

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

This convention will import all files with the `.cshtml` extension and create a custom object with the name and the XML content of the file. 

The name is used by PSRule to identify the object in output and in suppressions. I found using the relative path makes this easier to manage. Any `\` in the path is also replaces with `/` to ensure the path is consistent across platforms.

At the end, the policies are imported with the `APIM.Policy` type. We'll use this type to apply our rules only to API Management policies, but not to other file types and objects.


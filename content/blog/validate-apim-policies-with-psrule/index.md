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


### First rule: APIM.Policy.InboundBasePolicy

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

We determine the scope of the policy based on the file name. The scope is stored in the `Scope` property of the custom object. If we can't determine the scope, no object is created. We'll create a another rule later on to check if all `.cshtml` files have a valid scope.

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


### Unit test the rule

In our sample file `bad.api.cshtml`, the `base` policy is missing from the inbound section. There are however other scenarios where the `APIM.Policy.InboundBasePolicy` rule should fail. The `base` policy could be present for example, but not be the first policy in the inbound section. Since this rule is code and I'm a fan of Test Driven Development, I want to create unit tests for the rule to cover these scenarios. Because the rule is written in PowerShell, we can use [Pester](https://pester.dev/) to create these tests.

> Pester is beyond the scope of this blog post, but I'll show you how to create a simple test for the `APIM.Policy.InboundBasePolicy` rule. If you're interested in learning more about Pester, I recommend reading the [Pester documentation](https://pester.dev/docs/quick-start).

Create a new `test` folder in the root folder. Inside this folder, create a new file named `APIM.Policy.InboundBasePolicy.Tests.ps1` and add the following code:

```powershell
BeforeAll {
    # Setup error handling
    $ErrorActionPreference = 'Stop';
    Set-StrictMode -Version latest;

    if ($Env:SYSTEM_DEBUG -eq 'true') {
        $VerbosePreference = 'Continue';
    }
}

Describe "APIM.Policy.InboundBasePolicy" {

    It "Should return true if base policy is the only policy in the inbound section" {
        $policy = [PSCustomObject]@{
            PSTypeName = "APIM.Policy" # This is necessary for the -Type filter on a Rule to work
            Name = "test.api.cshtml"
            Scope = "API"
            Content = [xml]@"
                <policies>
                    <inbound>
                        <base />
                    </inbound>
                </policies>
"@
        } 

        $result = Invoke-PSRule -InputObject $policy -Name "APIM.Policy.InboundBasePolicy" -Path "$PSScriptRoot/../.ps-rule" -Option "$PSScriptRoot/../.ps-rule/ps-rule.yaml"

        $result | Should -not -BeNullOrEmpty
        $result.IsSuccess() | Should -Be $True
    }
    
    It "Should return false if the base policy is missing from the inbound section" {
        $policy = [PSCustomObject]@{
            PSTypeName = "APIM.Policy" # This is necessary for the -Type filter on a Rule to work
            Name = "test.api.cshtml"
            Scope = "API"
            Content = [xml]@"
                <policies>
                    <inbound>
                        <not-base />
                    </inbound>
                </policies>
"@
        } 

        $result = Invoke-PSRule -InputObject $policy -Name "APIM.Policy.InboundBasePolicy" -Path "$PSScriptRoot/../.ps-rule" -Option "$PSScriptRoot/../.ps-rule/ps-rule.yaml"

        $result | Should -not -BeNullOrEmpty
        $result.IsSuccess() | Should -Be $False
        $result.Reason.Length | Should -BeGreaterOrEqual 1
        $result.Reason[0] | Should -BeLike "*base*not exist*"
    }
}
```

This sample contains the following two tests for `APIM.Policy.InboundBasePolicy`:
1. Should return true if base policy is the only policy in the inbound section
1. Should return false if the base policy is missing from the inbound section

Each test performs the following steps:
1. Create a custom object with the same properties as the custom object created in the convention.  
   1. The `PSTypeName` is important to set, because it's used by PSRule to determine the type of the object when using the `-Type` on a rule.
1. Execute PSRule on the custom object. 
   1. We've used the `-InputPath` up until now to analyse all files in a specific folder. By using the `-InputObject` parameter we can execute PSRule on a single object.
   1. The `-Name` parameter is used to specify the rule to execute. This is useful when we have multiple rules defined and we only want to execute one.  
   1. The load our custom rules, we use the `-Path` parameter to specify the path to the `.ps-rule` folder.
1. Checks if the result is not empty and if the rule has either passed or has failed with the expected reason.

From a terminal window, navigate to the `test` folder and execute the following command to run the tests:

```powershell
$tests = (Get-ChildItem -Path "." -Recurse | Where-Object {$_.Name -like "*.Tests.ps1"}).FullName
Invoke-Pester $tests
```

The output should look similar to this:

![Test Results](../../../../../images/validate-apim-policies-with-psrule/test-results.png)

As you can see, both tests succeeded. We can now create more tests to cover other scenarios, like when the `base` policy is not the first policy in the inbound section or to check that the rule is skipped for a policy fragment. I've already done the legwork for you so you can find the complete test file [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/APIM.Policy.InboundBasePolicy.Tests.ps1).

Note that these tests look a little bit different (cleaner in my opinion) than the sample above. There's a lot of code in the tests that is duplicated. So, I've created reusable functions inside [Functions.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/Functions.ps1) to create the policy objects, execute PSRule and perform assertions on the result.

I've also included the [Invoke-PesterTests.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/Invoke-PesterTests.ps1) script to execute the tests. It's based on an example from the blog post [Increase the success rate of Azure DevOps pipelines using Pester](https://www.logitblog.com/increase-the-success-rate-of-azure-devops-pipelines-using-pester/) by Ryan Ververs-Bijkerk and includes additional logic to run the tests from a pipeline.

```powershell
.\Invoke-PesterTests.ps1 -ModulePath .
```
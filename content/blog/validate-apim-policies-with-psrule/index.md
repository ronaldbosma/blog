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

In this blog post, I’ll demonstrate how to use PSRule to validate your Azure API Management policies. But before we start, let's start with some requirements first.

### Table of Contents

- [Requirements](#requirements)
- [Sample policies](#sample-policies)
- [Import policies using convention](#import-policies-using-convention)
- [Implement first rule: inbound section should start with base policy](#implement-first-rule-inbound-section-should-start-with-base-policy)
- [Filter on scope](#filter-on-scope)
- [More rules](#more-rules)
  - [Check that policy files specify the scope](#check-that-policy-files-specify-the-scope)
  - [Check that the subscription key header is removed](#check-that-the-subscription-key-header-is-removed)
  - [Check that a backend entity is used](#check-that-a-backend-entity-is-used)
- [Handle invalid XML syntax](#handle-invalid-xml-syntax)
- [Conclusion](#conclusion)


### Requirements

I usually use [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview?tabs=bicep) to deploy my policies. And although you can specify your policies directly in a Bicep file, I prefer to store them in separate files. This makes it easier to manage and maintain them. I usually use the `.cshtml` file extension for these files, because this enables IntelliSense on policies when using the [Azure API Management for VS Code](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-apimanagement) extension. So, PSRule will need to recognize these files as API Management policies.

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


### Import policies using convention

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


### Implement first rule: inbound section should start with base policy

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


### More rules

In this section, we'll create a couple more rules to validate the API Management policies.


#### Check that policy files specify the scope

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


#### Check that the subscription key header is removed

One of the features of API Management is that it will forward all headers to the backend by default. This is very useful, but can also pose a security risk. The API Management subscription key header (`Ocp-Apim-Subscription-Key`) is also forwarded to the backend, while the backend usually doesn't need to know about this key. Especially when calling an external backend. To prevent this, we should remove this header in the inbound section of the global policy. We'll create a rule for this:

_The subscription key header (`Ocp-Apim-Subscription-Key`) should be removed in the inbound section of the global policy to prevent it from being forwarded to the backend._

The rule should check that the following policy is present in the inbound section of the global policy:

```xml
<set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
```

The sample `global.cshtml` files that you've downloaded already have this scenario in place, so we can create a new rule right away. Open `APIM.Policy.Rule.ps1` and add the following rule:

```powershell
# Synopsis: The subscription key header (Ocp-Apim-Subscription-Key) should be removed in the inbound section of the global policy to prevent it from being forwarded to the backend.
Rule "APIM.Policy.RemoveSubscriptionKeyHeader" -If { $TargetObject.Scope -eq "Global" } -Type "APIM.Policy" {
    $policy = $TargetObject.Content.DocumentElement
    
    $Assert.HasField($policy, "inbound")
    
    # Select all set-header policies that remove the Ocp-Apim-Subscription-Key header.
    # We only check direct children of the inbound section, because the header should always be removed and not optionally (e.g. when it's nested in a choose.when).
    # The expression is surround by @(...) because the result is a XmlElement if only one occurence is found, but we want an array.
    $removeSubscriptionKeyPolicies = @( $policy.inbound.ChildNodes | Where-Object { 
        $_.LocalName -eq "set-header" -and 
        $_.name -eq "Ocp-Apim-Subscription-Key" -and 
        $_."exists-action" -eq "delete" 
    } )

    if ($removeSubscriptionKeyPolicies.Count -gt 0) {
        $Assert.Pass()
    } else {
        $Assert.Fail("Unable to find a set-header policy that removes the Ocp-Apim-Subscription-Key header as a direct child of the inbound section.")
    }
}
```

The rule is executed on every object of type `APIM.Policy` where the scope is `Global`. It checks if there's a `set-header` policy for the `Ocp-Apim-Subscription-Key` header with the `delete` action in the inbound section. If the policy is found, the rule passes. Otherwise, it fails.

When you execute PSRule again, you should see that the `APIM.Policy.RemoveSubscriptionKeyHeader` rule is executed for the `global.cshtml` files. The output should show that the rule passes for the `./src/good/global.cshtml` file and fails for the `./src/bad/global.cshtml` file.


#### Check that a backend entity is used

There are several ways in API Management to configure the backend configuration to use. I prefer to create a separate backend entity in the API Management service that has the service URL and other settings, like authentication, configured. This way, the backend configuration is reusable, easier to maintain, and it is also checked by several [Azure Policies](https://learn.microsoft.com/en-us/azure/api-management/policy-reference#azure-api-management). We'll create the following rule for this:

_A `set-backend-service` policy should use a backend entity (by setting the `backend-id` attribute) so the backend configuration is reusable and easier to maintain._

Here are two samples of the `set-backend-service` policy, where the first is accepted and the second is not:

```xml
<!-- Good -->
<set-backend-service backend-id="test" />

<!-- Bad -->
<set-backend-service base-url="https://test.nl" />
```

The sample `*.api.cshtml` files that you've downloaded already have this scenario in place, so we can create a new rule right away. Open `APIM.Policy.Rule.ps1` and add the following rule:

```powershell
# Synopsis: A set-backend-service policy should use a backend entity (by setting the backend-id attribute) so it's reusable and easier to maintain.
Rule "APIM.Policy.UseBackendEntity" `
    -If { $TargetObject.Content.DocumentElement.SelectNodes(".//*[local-name()='set-backend-service']").Count -ne 0  } `
    -Type "APIM.Policy" `
{
    $policy = $TargetObject.Content.DocumentElement

    # Select all set-backend-service policies
    $setBackendServicePolicies = $policy.SelectNodes(".//*[local-name()='set-backend-service']")

    # Check that each set-backend-service policy has the backend-id attribute set
    foreach ($setBackendServicePolicy in $setBackendServicePolicies) {
        $Assert.HasField($setBackendServicePolicy, "backend-id")
    }
}
```

The rule is executed on every object of type `APIM.Policy` no matter the scope. We only want to execute the rule if the policy file actually has a `set-backend-service` policy, which is achieved by the condition: `$TargetObject.Content.DocumentElement.SelectNodes(".//*[local-name()='set-backend-service']").Count -ne 0`. It performs an XPath query to select all `set-backend-service` policies in the XML content of the policy file.

The rule itself will check that each `set-backend-service` policy has the `backend-id` attribute set. If the attribute is set, the rule passes. Otherwise, it fails.

When you execute PSRule again, you should see that the `APIM.Policy.UseBackendEntity` rule is executed for all `.cshtml` files with a valid scope. The output should show that the rule passes for the files in the `good` folder and fails for the files in the `bad` folder.


### Handle invalid XML syntax

With a couple of these tests done, I thought: Great! Lets run it on an actual code base. But I immediately got an error that the XML in at least one of the files was invalid. None of the rules for the `APIM.Policy` type were executed, because the convention failed to import the policies. Only the `APIM.Policy.FileExtension` rule was executed, because it's not dependent on the convention.

The problem is that API Management accepts invalid XML when dealing with policy expressions. See the following two snippets for examples:

```xml
<!-- This will result in an error when loading the policy as XML, because of the use of < and > in the policy expression -->
<set-body>@{
    return context.Request.Body.As<string>();
}</set-body>


<choose>
    <!-- This will result in an error when loading the policy as XML, because of the use of " inside the attribute value -->
    <when condition="@(context.Response.StatusCode.ToString() == "200")">
        <!-- Do something -->
    </when>
</choose>
```

The `set-body` snippet is invalid because of the `<string>` generic, which is recognized as a start XML tag. The second snippet is invalid because of the double quotes inside the `condition` attribute value. Even the examples in the official documentation have invalid XML. See the [set-body policy examples](https://learn.microsoft.com/en-us/azure/api-management/set-body-policy#examples).


The easiest way to get valid XML inside an element is to use `<![CDATA[]]>`. The first snippet would look like this:

```xml
<set-body><![CDATA[@{
    return context.Request.Body.As<string>();
}]]></set-body>
```

I was concerned that API Management would not work properly with this syntax, but it does. The policy expression is still executed as expected.

For attribute values there are a couple of solutions. You can surround the value with single quotes: `'{value}'`. When you upload this snippet to API Management, it will automatically convert the single quotes to double quotes. The second solution is to use `&quot;` inside the attribute value. Here are two examples:

```xml
<choose>
    <when condition='@(context.Response.StatusCode.ToString() == "200")'>
        <!-- Do something -->
    </when>
    <when condition="@(context.Response.StatusCode.ToString() == &quot;200&quot;)">
        <!-- Do something -->
    </when>
</choose>
```

To test this yourself, download [invalid-xml-1.operation.cshtml](https://raw.githubusercontent.com/ronaldbosma/blog-code-examples/master/validate-apim-policies-with-psrule/src/bad/invalid-xml-1.operation.cshtml) and [invalid-xml-2.operation.cshtml](https://raw.githubusercontent.com/ronaldbosma/blog-code-examples/master/validate-apim-policies-with-psrule/src/bad/invalid-xml-2.operation.cshtml), and place them in the `bad` folder. Also download [good.operation.cshtml](https://raw.githubusercontent.com/ronaldbosma/blog-code-examples/master/validate-apim-policies-with-psrule/src/good/good.operation.cshtml), and place it in the `good` folder. This has the suggested solutions for the invalid XML syntax.

When you run PRSule again, you might think that every works, because you see output for the `APIM.Policy.FileExtension` rule. However, if you scroll up to the top of the output, you'll see the following error, indicating that a policy file with invalid XML could not be loaded:

```
Invoke-PSRule: Cannot convert value "<policies>
    <inbound>
        <base />
        <!-- This will result in an error when loading the policy as XML, because of the use of < and > in the policy expression -->
        <set-body>@{
            return context.Request.Body.As<string>();
        }</set-body>
    </inbound>
    ... TRUNCATED ...
</policies>" to type "System.Xml.XmlDocument". Error: "The 'string' start tag on line 7 position 44 does not match the end tag of 'set-body'. Line 8, position 12."
```

To handle policy files with invalid XML syntax gracefully, we'll need to make some changes to the convention. I also want to report on the files with invalid XML, because they won't be processed by the other rules. Open `APIM.Policy.Conventions.Rule.ps1` and replace its contents with the following code:

```powershell
# Synopsis: Imports the APIM XML policy file for analysis. File names should match: *.cshtml
Export-PSRuleConvention "APIM.Policy.Conventions.Import" -Initialize {

    $policies = @()
    $policyFilesWithInvalidXml = @()

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
        # The 'APIM.Policy.FileExtension' rule will report on unknown file extensions.
        if ($null -ne $scope) {
            try {
                $policies += [PSCustomObject]@{
                    Name = $name
                    Scope = $scope
                    Content = [Xml](Get-Content -Path $policyFile.FullName -Raw)
                }
            }
            catch {
                # Add policy files with invalid XML to a separate list, so we can report them in a separate rule.
                # By adding them as a different type, we don't have to exclude them from every APIM Policy rule that expects valid XML.
                $policyFilesWithInvalidXml += [PSCustomObject]@{
                    Name = $name
                    Error = $_.Exception.Message
                }
            }
        }
    }

    $PSRule.ImportWithType("APIM.Policy", $policies);
    $PSRule.ImportWithType("APIM.PolicyWithInvalidXml", $policyFilesWithInvalidXml);
}
```

This snippet has several changes compared to the previous version:
1. At the top, a new array called `$policyFilesWithInvalidXml` is created which will hold the `.cshtml` files with invalid XML.
1. The creation of the custom object has been placed in a `try catch` block. When the XML content of the policy file can't be loaded, an exception is thrown. This exception is caught and a new custom object is created with the file name and the exception message. This object is added to the `$policyFilesWithInvalidXml` array.
1. At the end, the files with invalid XML are imported as a new type `APIM.PolicyWithInvalidXml`.

I've chosen to import the files with invalid XML as a separate type called `APIM.PolicyWithInvalidXml`. This way, we can use the `-Type "APIM.Policy"` filter on the rules that validate policies without having to worry about invalid XML. Simplifying the creation of new rules.

Now, to report on policy files with invalid XML, we'll create a new rule. Open `APIM.Policy.Rule.ps1` and add the following rule:

```powershell
# Synopsis: A policy file should contain valid XML
Rule "APIM.Policy.ValidXml" -Type "APIM.Policy", "APIM.PolicyWithInvalidXml" {
    if ($PSRule.TargetType -eq "APIM.Policy") {
        $Assert.Pass()
    } else {
        $Assert.Fail($TargetObject.Error)
    }
}
```

As you can see, the rule is executed for objects of type `APIM.Policy` and `APIM.PolicyWithInvalidXml`. When the type is `APIM.Policy`, we know the XML content was loaded successfully and the rule passes. Otherwise, the rule fails with the error message as the reason.

> By filtering on both types, the `APIM.Policy.ValidXml` rule will report a `Pass` on policy files with valid XML. Which I like. You can also choose to only report on invalid XML by executing the rule for the `APIM.PolicyWithInvalidXml` type only and always failing the rule.

When you run PSRule again, you should see that all our custom rules are executed again. The rule `APIM.Policy.ValidXml` will fail for the files `invalid-xml-1.operation.cshtml` and `invalid-xml-2.operation.cshtml`, and succeed for all other policy files.


### Considerations

Microsoft has created a module on top of PSRule to validate Azure Infrastructure as Code resources called [PSRule for Azure](https://azure.github.io/PSRule.Rules.Azure/). It comes with a standard set of rules and my colleague Caspar Eldermans has written the blog post [Validating Azure Bicep templates with PSRule](https://blogs.infosupport.com/validating-azure-bicep-templates-with-psrule/) about it.

This module actually has a couple of rules that check API Management policies as well. For example the [Azure.APIM.PolicyBase](https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.APIM.PolicyBase/) rule that checks that each section of a policy has a `base` policy. Here's the implementation of this rule:

```powershell
# Synopsis: Base element for any policy element in a section should be configured.
Rule 'Azure.APIM.PolicyBase' -Ref 'AZR-000371' -Type 'Microsoft.ApiManagement/service', 'Microsoft.ApiManagement/service/apis', 'Microsoft.ApiManagement/service/apis/resolvers', 'Microsoft.ApiManagement/service/apis/operations', 'Microsoft.ApiManagement/service/apis/resolvers/policies', 'Microsoft.ApiManagement/service/products/policies', 'Microsoft.ApiManagement/service/apis/policies',
'Microsoft.ApiManagement/service/apis/operations/policies' -If { $Null -ne (GetAPIMPolicyNode -Node 'policies' -IgnoreGlobal) } -Tag @{ release = 'GA'; ruleSet = '2023_06'; 'Azure.WAF/pillar' = 'Security'; } {
    $policies = GetAPIMPolicyNode -Node 'policies' -IgnoreGlobal
    foreach ($policy in $policies) {
        Write-Debug "Got policy: $($policy.OuterXml)"
        
        $Assert.HasField($policy.inbound, 'base').PathPrefix('inbound')
        $Assert.HasField($policy.backend, 'base').PathPrefix('backend')
        $Assert.HasField($policy.outbound, 'base').PathPrefix('outbound')
        $Assert.HasField($policy.'on-error', 'base').PathPrefix('on-error')
    }
}
```

It's very similar to the rules created in this post, but the filtering is done based on the resource type that you use in Bicep or ARM templates. Every rule that we've created to check our policies can also be created using this module. An advantage of using this module is that it also works for inline policies that you define in e.g. a Bicep file. A disadvantage is that the rules won't always work for ARM templates when you load your policies from external files. Additionally, PSRule for Azure doesn't support other deployment tools like Terraform. That's the reason why I usually prefer to store my policies in separate `.cshtml` files and use the approach that I've described in this blog post.


### Conclusion

PSRule is a powerful tool that can help manage the quality of your Azure API Management policies. By creating custom rules, you can validate your policies against your own standards. 

The rules can be as simple or complex as you want. The same goes for the logic in the convention. Since I'm a big fan of test automation, I've written the rules using a TDD approach and created a bunch of tests. In the next blog post, I'll dive deeper into how I did this.

You can find a full working sample [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/validate-apim-policies-with-psrule). I've included a couple more rules and samples.

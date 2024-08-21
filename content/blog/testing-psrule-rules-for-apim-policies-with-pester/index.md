---
title: "Testing PSRule Rules for API Management Policies with Pester"
date: 2024-08-14T00:00:00+02:00
publishdate: 2024-08-14T00:00:00+02:00
lastmod: 2024-08-14T00:00:00+02:00
tags: [ "Azure", "API Management", "Infra as Code", "Pester", "PSRule", "Test Automation" ]
draft: true
---

In my previous blog post, [Validate API Management policies with PSRule](/blog/2024/08/12/validate-api-management-policies-with-psrule/), I showed you how to use PSRule to validate Azure API Management policy files. We created a PSRule convention and several custom rules, which all contain logic. Since I'm a big fan of Test Driven Development, I created these rules using a test-first approach. So, in this blog post, I'll show you how to create automated tests for these rules using [Pester](https://pester.dev/)-a testing and mocking framework for PowerShell.

An explanation of the concepts of Pester is out-of-scope for this blog post. If you're new to Pester, I recommend having a look at the [Quick Start](https://pester.dev/docs/quick-start) documentation.

### Table of Contents

- [Prerequisites](#prerequisites)
- [Unit tests for APIM.Policy.InboundBasePolicy](#unit-tests-for-apim.policy.inboundbasepolicy)
  - [Should pass if base policy is the only policy in the inbound section](#should-pass-if-base-policy-is-the-only-policy-in-the-inbound-section)
  - [Should fail if the inbound section is missing](#should-fail-if-the-inbound-section-is-missing)
  - [Should fail if the base policy is missing from the inbound section](#should-fail-if-the-base-policy-is-missing-from-the-inbound-section)
  - [Should not apply to global](#should-not-apply-to-global)
  - [Other scenarios](#other-scenarios)
- [Refactor tests](#refactor-tests)
    - [Policy object creation](#policy-object-creation)
    - [Execute PSRule](#execute-psrule)
    - [Assertions](#assertions)
    - [Update tests](#update-tests)
- [Integration tests](#integration-tests)


### Prerequisites

Follow the instructions on [Install PSRule](https://microsoft.github.io/PSRule/v2/install/) to install PSRule if you haven't done so already. Please note that this blog post is written using version `2.9.0` of PSRule.

To install Pester, follow the instructions on [Installation and Update](https://pester.dev/docs/introduction/installation). The sample tests are created using version `v5` of Pester.

You'll also need the rules, policies, etc. from the previous blog post. You can download them [here](https://github.com/ronaldbosma/blog-code-examples/raw/master/validate-apim-policies-with-psrule/start-testing-psrule-rules-for-apim-policies-with-pester.zip). To get started, create a new root folder and unzip the files into this folder. After unzipping, your folder structure should look like this:

```
/your-root
    /.ps-rule
        APIM.Policy.Conventions.Rule.ps1
        APIM.Policy.Rule.ps1
        APIM.Policy.Suppressions.Rule.yaml
        ps-rule.yaml
    /src
        /bad
            bad.api.cshtml
            bad.fragment.cshtml
            ...
        /good
            global.cshtml
            good.api.cshtml
            ...
        /suppressed
            global.cshtml
            suppressed-unknown-scope.cshtml
            ...
```

Open a PowerShell terminal and run the following command to verify that the custom rules are executed correctly:

```powershell
Invoke-PSRule -InputPath ".\src\" -Option ".\.ps-rule\ps-rule.yaml"
```


### Unit tests for APIM.Policy.InboundBasePolicy

In the previous blog post, we created a rule named `APIM.Policy.InboundBasePolicy` that implements the following logic:

_The inbound section should always start with a `base` policy to ensure that critical logic, such as security checks, is applied first. This rule should apply to all scopes except for the global scope and policy fragments._

It's implemented in the [/.ps-rule/APIM.Policy.Rule.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/.ps-rule/APIM.Policy.Rule.ps1) file and has the following logic:

```powershell
# Synopsis: The first policy inside the inbound section should be the base policy to make sure important logic like security checks are applied first.
Rule "APIM.Policy.InboundBasePolicy" -If { $TargetObject.Scope -ne "Global" -and $TargetObject.Scope -ne "Fragment" } -Type "APIM.Policy" {
    $policy = $TargetObject.Content.DocumentElement
    
    $Assert.HasField($policy, "inbound")
    $Assert.HasField($policy.inbound, "base")
    $Assert.HasFieldValue($policy, "inbound.FirstChild.Name", "base")
}
```

To make sure that the tests are correct, we'll simulate a TDD approach. Locate the `APIM.Policy.InboundBasePolicy` rule in your `APIM.Policy.Rule.ps1` file and replace it with the following code:

```powershell
# Synopsis: The first policy inside the inbound section should be the base policy to make sure important logic like security checks are applied first.
Rule "APIM.Policy.InboundBasePolicy" <#-If { $TargetObject.Scope -ne "Global" -and $TargetObject.Scope -ne "Fragment" }#> -Type "APIM.Policy" {
    $policy = $TargetObject.Content.DocumentElement
    
    # $Assert.Pass()
    # $Assert.HasField($policy, "inbound")
    # $Assert.HasField($policy.inbound, "base")
    # $Assert.HasFieldValue($policy, "inbound.FirstChild.Name", "base")
}
```

As you can see, we've commented out the `-If` parameter to make sure the rule always executes. We've also commented out the assertions. This way, the rule always fails, but without a reason.

Create a new `tests` folder under the root folder. Inside this folder, create a new file named `APIM.Policy.InboundBasePolicy.Tests.ps1`. As you can see, the file name is the same as the rule name with `.Tests` appended. Although the rules are all bundled together in a single file, I prefer to create a separate test file for each rule. This makes it easier to find and maintain the tests.

Add the following code to `APIM.Policy.InboundBasePolicy.Tests.ps1`:

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

}
```

This is the basic structure of a Pester test file that we'll use. In the `BeforeAll` section, we set up error handling and verbose logging. This block is executed once before the tests are executed. The `Describe` block is used to group tests together. In this case, we group all tests for the `APIM.Policy.InboundBasePolicy` rule. 


#### Should pass if base policy is the only policy in the inbound section

Let's start with a first scenario to test this rule: 

_APIM.Policy.InboundBasePolicy should pass if base policy is the only policy in the inbound section_

Locate the `Describe` block and add the following code:

```powershell
    It "Should pass if base policy is the only policy in the inbound section" {
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
```

As you can see, the `It` block is used to define a test and is followed by the scenario name. 

The test starts by creating a custom object that represents an API-scoped policy. The object structure is the same as we create in our [custom convention](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/.ps-rule/APIM.Policy.Conventions.Rule.ps1). The `PSTypeName` property is important to set, because it's used by PSRule to determine the type of the object when using the `-Type` filter on a rule. The policy XML is defined in the `Content` property. In this case, it has only an inbound section with a base policy. 

> Note that you could also create a `.cshtml` file on disk for each scenario and execute the rule against these files. However, I prefer to have the contents of the XML policy directly in the test, because I can see at a glance what the test does, without needing to open multiple files.

We then execute PSRule on the custom object. We've used the `-InputPath` up until now to analyse all files in a specific folder. By using the `-InputObject` parameter we can execute PSRule on a single object. The `-Name` parameter is used to specify the rule to execute. This is useful because we have multiple rules defined and we only want to execute one. To load our custom rules, we use the `-Path` parameter to specify the path to the `.ps-rule` folder.

Finally, we assert that the result is not empty and that the rule passed. See [the Pester documentation](https://pester.dev/docs/assertions/) for more information on assertions.

To execute the test with Pester, from a terminal window, navigate to the `test` folder and execute the following command:

```powershell
Invoke-Pester ".\APIM.Policy.InboundBasePolicy.Tests.ps1"
```

The test should fail and the output should look similar to this:

![Test Results with Failure](../../../../../images/testing-psrule-rules-for-apim-policies-with-pester/test-results-failure.png)

The test failed with the reason `Expected $true, but got $false`, because the rule failed but we expected it to pass. To fix the test, locate the `APIM.Policy.InboundBasePolicy` rule and uncomment the `$Assert.Pass()` line. 

When you rerun test, it should pass and the output should look similar to this:

![Test Results with Success](../../../../../images/testing-psrule-rules-for-apim-policies-with-pester/test-results-pass.png)


#### Should fail if the inbound section is missing

Let's implement a second test for the following scenario:

_APIM.Policy.InboundBasePolicy should fail if the inbound section is missing_

> Note that when the inbound section is missing, API Management will create it automatically with the `base` policy included. However, I want to force that the inbound section with `base` policy is explicitly defined.

This time the policy doesn't conform to the rule. Add the following test to the `Describe` block:

```powershell
It "Should fail if the inbound section is missing" {
    $policy = [PSCustomObject]@{
        PSTypeName = "APIM.Policy" # This is necessary for the -Type filter on a Rule to work
        Name = "test.api.cshtml"
        Scope = "API"
        Content = [xml]"<policies></policies>"
    } 

    $result = Invoke-PSRule -InputObject $policy -Name "APIM.Policy.InboundBasePolicy" -Path "$PSScriptRoot/../.ps-rule" -Option "$PSScriptRoot/../.ps-rule/ps-rule.yaml"

    $result | Should -not -BeNullOrEmpty
    $result.IsSuccess() | Should -Be $False
    $result.Reason.Length | Should -BeGreaterOrEqual 1
    $result.Reason[0] | Should -BeLike "*inbound*not exist*"
}
```

This test is similar to the first test, but the inbound section is missing. At the bottom of the test, we assert that the result is not empty, that the rule failed, and that the reason contains the expected message. By using the `-BeLike` assertion, we can use wildcards to match the message, making it more robust against changes in the message.

When running the tests, the new test should fail. To make it pass, remove `$Assert.Pass()` and uncomment `$Assert.HasField($policy, "inbound")`.

#### Should fail if the base policy is missing from the inbound section

Let's implement another test for the following scenario:

_APIM.Policy.InboundBasePolicy should fail if the base policy is missing from the inbound section_

Add the following test to the `Describe` block:

```powershell
    It "Should fail if the base policy is missing from the inbound section" {
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
```

Again very similar to the previous test. The only difference is the XML policy content and the expected reason message.

When running the tests, the new test should fail. To make it pass, uncomment `$Assert.HasField($policy.inbound, "base")`.

### Should not apply to global

Finally, let's implement a test for the following scenario:

_APIM.Policy.InboundBasePolicy should not apply to global_

Add the following test to the `Describe` block:

```powershell
It "Should not apply to global" {
    $policy = [PSCustomObject]@{
        PSTypeName = "APIM.Policy" # This is necessary for the -Type filter on a Rule to work
        Name = "global.cshtml"
        Scope = "Global"
        Content = [xml]"<policies></policies>"
    } 

    $result = Invoke-PSRule -InputObject $policy -Name "APIM.Policy.InboundBasePolicy" -Path "$PSScriptRoot/../.ps-rule" -Option "$PSScriptRoot/../.ps-rule/ps-rule.yaml"

    $result | Should -BeNull
}
```

This test is a bit different. The scope of the policy is set to `Global` and the name of the policy is `global.cshtml`. The rule should not be executed for this policy, so we assert that the result is null.

When running the tests, the new test should fail. To make it pass, uncomment the `-If` condition `-If { $TargetObject.Scope -ne "Global" -and $TargetObject.Scope -ne "Fragment" }` behind the rule name.


#### Other scenarios

The assertion `$Assert.HasFieldValue($policy, "inbound.FirstChild.Name", "base")` is still commented out in the rule. So, we're still missing at least one scenario. And f you look at the implementation of the rule, you can see that there are more scenarios missing. We could also add tests for the following scenarios:
- Should pass if base policy is the first policy in the inbound section
- Should fail if base policy is NOT the first policy in the inbound section
- Should fail if the inbound section is empty
- Should apply to workspace
- Should apply to product
- Should apply to operation
- Should not apply to policy fragment

Before you add these scenarios, we'll first refactor the tests to make them more maintainable in the next section.

### Refactor tests

You might have noticed a lot of code duplication in each test. The creation of the custom object with the policy, the execution of PSRule, and the assertions are all very similar. We can refactor this code into reusable functions.

I've placed the functions in a separate file called `Functions.ps` in the `tests` folder. You can find the full implementation [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/Functions.ps1). I'll highlight the most important parts in the following sections.

#### Policy object creation

The custom policy object has the same structure for all tests. Only the scope, name and XML content differ. Here is an example of the functions to create a global and API policy object:

```powershell
function New-GlobalPolicy([Parameter(Mandatory=$true)]$Xml)
{
    return New-Policy -Scope "Global" -Name "global.cshtml" -Xml $Xml
}

function New-APIPolicy([Parameter(Mandatory=$true)]$Xml)
{
    return New-Policy -Scope "API" -Name "test.api.cshtml" -Xml $Xml
}

function New-Policy([Parameter(Mandatory=$true)]$Scope, [Parameter(Mandatory=$true)]$Name, [Parameter(Mandatory=$true)]$Xml)
{
    return [PSCustomObject]@{
        PSTypeName = "APIM.Policy" # This is necessary for the -Type filter on a Rule to work
        Name = $Name
        Scope = $Scope
        Content = [xml]$Xml
    }
}
```

I've created a generic function `New-Policy` that creates a policy object with the correct structure. The other two functions are wrappers create a policy object with the correct scope and name.


#### Execute PSRule

When executing PSRule, the `-Path` and `-Option` parameters are always the same. I've created a function that executes PSRule with these parameters so we don't have to repeat them in each test. Here is the function:

```powershell
function Invoke-CustomPSRule([Parameter(Mandatory=$true)]$InputObject, [Parameter(Mandatory=$true)]$Rule)
{
    # The Path should point to the directory containing the rule files, else they won't be loaded
    # The Option should point to the PSRule configuration file, else the conventions won't be loaded

    return Invoke-PSRule -InputObject $InputObject -Name $Rule -Path "$PSScriptRoot/../.ps-rule" -Option "$PSScriptRoot/../.ps-rule/ps-rule.yaml"
}
```

#### Assertions

Lastly, every set of assertions can be extracted into its own function. Here are the functions to assert if a rule failed.

```powershell
function Assert-RuleFailedWithReason {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline)][PSRule.Rules.RuleRecord]$RuleRecord, 
        [Parameter(Mandatory=$true)][string]$ExpectedReasonPattern
    )
    
    $RuleRecord | Assert-RuleFailed
    $RuleRecord.Reason[0] | Should -BeLike $ExpectedReasonPattern
}

function Assert-RuleFailed {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true, ValueFromPipeline)][PSRule.Rules.RuleRecord]$RuleRecord
    )
    
    $RuleRecord | Should -not -BeNullOrEmpty
    $RuleRecord.IsSuccess() | Should -Be $False
    $RuleRecord.Reason.Length | Should -BeGreaterOrEqual 1
}
```

As you can see, they perform the assertions on the `RuleRecord` object, which is the result of the `Invoke-PSRule` function. The result of the `Invoke-PSRule` can be piped to the assertion functions.


#### Update tests

To use these functions in the tests yourself, download [Functions.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/Functions.ps1) and place it in the `tests` folder. Then open `APIM.Policy.InboundBasePolicy.Tests.ps1` and add the following code to the end of the `BeforeAll` block to load the functions:

```powershell
# Load functions
. $PSScriptRoot/Functions.ps1
```

With the functions in place, the tests can be refactored. The test for scenario _"Should fail if the inbound section is missing"_ can be changed to the following for example:

```powershell
    It "Should fail if the inbound section is missing" {
        $policy = New-APIPolicy "<policies></policies>"
        $result = Invoke-CustomPSRule $policy "APIM.Policy.InboundBasePolicy"
        $result | Assert-RuleFailedWithReason -ExpectedReasonPattern "*inbound*not exist*"
    }
```

The old test was 13 lines long, while the refactored implementation only has 5 lines. It is more readable and easier to maintain.

You can find the final implementation of `APIM.Policy.InboundBasePolicy.Tests.ps1` with refactored tests and all scenarios [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/APIM.Policy.InboundBasePolicy.Tests.ps1). I've also created tests for the other rules. See for example [APIM.Policy.UseBackendEntity.Tests.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/APIM.Policy.UseBackendEntity.Tests.ps1) and [APIM.Policy.FileExtension.Tests.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/APIM.Policy.FileExtension.Tests.ps1).


### Integration tests

As I mentioned before, I prefer creating the custom object with policy inside my test so I have the policy XML directly in the test. There is however a downside to this approach. Our custom convention, that we've defined in [APIM.Policy.Conventions.Rule.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/.ps-rule/APIM.Policy.Conventions.Rule.ps1), is not executed and tested by these tests. 

I tried the [Get-PSRuleTarget](https://microsoft.github.io/PSRule/v2/commands/PSRule/en-US/Get-PSRuleTarget/) to get a list with all the `APIM.Policy` and `APIM.PolicyWithInvalidXml` types, but this only seems to return the `.cshtml` type. So instead, I've created integration tests that execute the rules on all the actual policy files like we would do in a real-world scenario.

To create these tests, create a file called `APIM.Policy.Tests.ps1` in the `tests` folder and add the following code to the file:

```powershell
BeforeAll {
    # Setup error handling
    $ErrorActionPreference = 'Stop';
    Set-StrictMode -Version latest;

    if ($Env:SYSTEM_DEBUG -eq 'true') {
        $VerbosePreference = 'Continue';
    }

    # Load functions
    . $PSScriptRoot/Functions.ps1


    # If you execute Invoke-PSRule from inside the test folder, no files will be analysed. So, we go up one level.
    Push-Location "$PSScriptRoot/.."
    try {
        # Analyse policies in src folder using PSRule
        $result = Invoke-PSRule -InputPath "./src/" -Option "./.ps-rule/ps-rule.yaml"
    }
    finally {
        Pop-Location
    }
}

Describe "APIM.Policy" {

}
```

Similar to the other test files, we setup error handling, verbose logging and load the functions in the `BeforeAll` block. The difference is that we also execute PSRule on the `src` folder and store the result in a variable.

> Note that we use `Push-Location` and `Pop-Location` to change the current location to the root folder and back. This is necessary because otherwise PSRule won't find any files to analyse.

Now, let's add a test to check if the `APIM.Policy.InboundBasePolicy` rule is executed on the correct policy files in the `src` folder. Add the following code to the `Describe` block:

```powershell
It "InboundBasePolicy" {
    $ruleResults = @( $result | Where-Object { $_.RuleName -eq 'APIM.Policy.InboundBasePolicy' } );
    $ruleResults.Count | Should -Be 8

    Assert-RulePassedForTarget $ruleResults "good.workspace.cshtml"
    Assert-RulePassedForTarget $ruleResults "good.product.cshtml"
    Assert-RulePassedForTarget $ruleResults "good.api.cshtml"
    Assert-RulePassedForTarget $ruleResults "good.operation.cshtml"
    
    Assert-RuleFailedForTarget $ruleResults "bad.workspace.cshtml"
    Assert-RuleFailedForTarget $ruleResults "bad.product.cshtml"
    Assert-RuleFailedForTarget $ruleResults "bad.api.cshtml"
    Assert-RuleFailedForTarget $ruleResults "bad.operation.cshtml"
}
```

This test selects all results related to the `APIM.Policy.InboundBasePolicy` rule and asserts that the correct number of results is found. It then asserts that the rule passed for the good policy files and failed for the bad. The files in the `suppressed` folder should not be included, because these are skipped.

The `Assert-RulePassedForTarget` and `Assert-RuleFailedForTarget` functions only check if the rule passed or failed without checking the reason, since this is already checked using the unit tests. The functions can be found in [Functions.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/Functions.ps1).

We can add similar tests for the other rules. For example, the `APIM.Policy.RemoveSubscriptionKeyHeader` rule:

```powershell
It "RemoveSubscriptionKeyHeader" {
    $ruleResults = @( $result | Where-Object { $_.RuleName -eq 'APIM.Policy.RemoveSubscriptionKeyHeader' } );
    $ruleResults.Count | Should -Be 2

    Assert-RulePassedForTarget $ruleResults "good/global.cshtml"
    Assert-RuleFailedForTarget $ruleResults "bad/global.cshtml"
}
```

You can find the fully implemented `APIM.Policy.Tests.ps1` file [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/APIM.Policy.Tests.ps1).


### Pipeline

> TODO

I've also included the [Invoke-PesterTests.ps1](https://github.com/ronaldbosma/blog-code-examples/blob/master/validate-apim-policies-with-psrule/tests/Invoke-PesterTests.ps1) script to execute the tests. It's based on an example from the blog post [Increase the success rate of Azure DevOps pipelines using Pester](https://www.logitblog.com/increase-the-success-rate-of-azure-devops-pipelines-using-pester/) by Ryan Ververs-Bijkerk and includes additional logic to run the tests from a pipeline.

```powershell
.\Invoke-PesterTests.ps1 -ModulePath .
```
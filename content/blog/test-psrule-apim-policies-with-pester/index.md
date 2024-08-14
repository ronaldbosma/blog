


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
---
title: "GitHub Actions Workflow for Azure Developer CLI (azd) Templates"
date: 2026-02-21T16:30:00+01:00
publishdate: 2026-02-21T16:30:00+01:00
lastmod: 2026-02-21T16:30:00+01:00
tags: [ "Azure", "Azure Developer CLI", "azd", "GitHub Actions" ]
summary: "In this post, I'll show how I structure a GitHub Actions workflow for azd templates so I can automate the process of building, deploying, verifying and cleaning up. The workflow makes it easier to validate my own changes and review external contributions. I'll walk through each job with practical snippets and explain why I split build, deployment and verification."
draft: true
---

I've been working with Azure Developer CLI (azd) templates where each change can affect both infrastructure and application behavior. To make changes with more confidence, I include a GitHub Actions workflow that automates build, deployment, verification and cleanup.

This setup also helps when reviewing pull requests from other developers or automated tools. I can open a PR, let the workflow validate everything end to end and automatically remove all resources afterward.

### Table of Contents

- [Workflow Structure](#workflow-structure)
- [Common Configuration](#common-configuration)
- [Build, Verify and Package](#build-verify-and-package)
- [Deploy to Azure](#deploy-to-azure)
- [Verify Deployment](#verify-deployment)
- [Clean Up Resources](#clean-up-resources)
- [Add Cleanup Input Parameter](#add-cleanup-input-parameter)
- [Tips](#tips)
- [Conclusion](#conclusion)

### Workflow Structure

My workflows usually contain four jobs:

- **Build, Verify and Package**: Sets up the build environment, validates the Bicep template, executes unit tests and packages the project's code and integration tests
- **Deploy to Azure**: Provisions the Azure infrastructure and deploys the packaged applications to the created resources
- **Verify Deployment**: Runs automated integration tests to verify the deployed resources and application. It can also verify monitoring and logging, for example by checking that availability tests succeed.
- **Clean Up Resources**: Removes all deployed Azure resources

See the follow screenshot for a summary of a workflow run:

![GitHub Actions Workflow Summary](../../../../../images/github-actions-workflow-for-azd-templates/github-actions-workflow-summary.png)

Splitting the workflow up in different jobs makes it easier to understand and maintain. Each job has a clear purpose and a focused set of steps. If we can't build the code or validate the template, we don't need to deploy anything. If deployment fails, we know the issue is in provisioning or deployment steps instead of application code. If verification fails, we know the issue is likely in application code or test code instead of infrastructure.

These two repositories contain complete workflow examples that match the structure described above:

- [call-apim-with-managed-identity/.github/workflows/azure-dev.yml](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/.github/workflows/azure-dev.yml)
	- This template contains application code (Function App and Logic App) that is packaged during the build job
	- It also includes .NET integration tests that are packaged during build and executed in the Verify Deployment job
- [track-availability-in-app-insights/.github/workflows/azure-dev.yml](https://github.com/ronaldbosma/track-availability-in-app-insights/blob/main/.github/workflows/azure-dev.yml)
	- This template has a Function App and Logic App with unit tests that are executed during build, but no integration tests
	- Instead of integration tests, the Verify Deployment job runs a PowerShell script that checks availability test execution in Azure Monitor

> I used [Azure Developer CLI: From Dev to Prod with Azure DevOps Pipelines](https://devblogs.microsoft.com/devops/azure-developer-cli-from-dev-to-prod-with-azure-devops-pipelines/) for inspiration while creating my first azd workflow.

### Common Configuration

If my template has hooks, they are usually written in PowerShell. So I set PowerShell Core as the default shell at workflow level:

```yaml
defaults:
  run:
    shell: pwsh # Use PowerShell Core for all scripts (the azd hooks are written in PowerShell)
```

I also define these `env` variables which are mandatory for azd:

```yaml
env:
  # Add a unique suffix to the environment name for pull requests to avoid name conflicts
  AZURE_ENV_NAME: ${{ github.event.pull_request.number && format('{0}-pr{1}', vars.AZURE_ENV_NAME, github.event.pull_request.number) || vars.AZURE_ENV_NAME }}
  AZURE_LOCATION: ${{ vars.AZURE_LOCATION }}
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID || vars.AZURE_SUBSCRIPTION_ID }}
```

I add a pull request suffix to `AZURE_ENV_NAME` so parallel PRs in the same repository don't overwrite each other.

Notice the pattern `${{ secrets.AZURE_SUBSCRIPTION_ID || vars.AZURE_SUBSCRIPTION_ID }}`. When you run [azd pipeline config](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/reference#azd-pipeline-config) and choose OpenID Connect (OIDC) as the authentication mechanism, azd creates `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` as GitHub variables by default. However, [Microsoft recommends using secrets for these values](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect) to reduce the risk of exposing them in logs. Supporting both `secrets` and `vars` makes migration easy. 

> I usually add a tip in the 'Setting Up the Pipeline' section of the README of a template to replace the variables with secrets for better security.

Most jobs will sign into Azure and need the `id-token: write` permission to use OIDC authentication, so I set that at job level. For example:

```yaml
build-verify-package:
  name: Build, Verify and Package
  runs-on: ubuntu-latest
  permissions:
    id-token: write # Required to fetch an OIDC token for Azure authentication
```

Most jobs also require azd, which can be installed using the [Azure/setup-azd](https://github.com/Azure/setup-azd) action:

```yaml
- name: Setup azd
  uses: Azure/setup-azd@v2
```

And lastly, they need to authenticate with Azure. I use Azure CLI authentication with azd commands. That way, credentials are shared between azd commands and az (Azure CLI) commands used in hooks.

```yaml
# Use Azure CLI authentication with azd commands so credentials are shared between azd commands and az (Azure CLI) commands used in hooks.
- name: Configure azd to use Azure CLI Authentication
  run: |
    azd config set auth.useAzCliAuth "true"

# Login to the Azure CLI with OpenID Connect (OIDC) using federated identity credentials.
- name: Azure CLI Login
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID || vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID || vars.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID || vars.AZURE_SUBSCRIPTION_ID }}
```

> The page [Use the Azure Login action with OpenID Connect](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect) describes how to set up OIDC authentication for GitHub Actions and Azure manually, but I recommend using [azd pipeline config](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/reference#azd-pipeline-config), because it guides you through the process and automatically creates the necessary resources.

### Build, Verify and Package

In this job, I set up required tools, validate infrastructure and package everything needed for deployment and verification.

If the template contains application code, this job usually installs additional tools besided azd such as .NET and Node.js.

I also print the tool versions. I once used a new Bicep feature that failed in the workflow because the runner had an older version. This step made the mismatch obvious:

```yaml
- name: Print Tool Versions
  run: |
	az version
	az bicep version
	azd version
	Write-Host ".NET SDK Version: $(dotnet --version)"
	Write-Host "Node.js Version: $(node --version)"
	Write-Host "npm Version: $(npm --version)"
```

Then I run Bicep lint:

```yaml
- name: Bicep Lint
  run: |
	az bicep lint --file ./infra/main.bicep
```

My repositories include a `bicepconfig.json` where almost all rules are set to `error`, so the workflow fails quickly when the template doesn't comply. For details, see [Add linter settings in the Bicep config file](https://docs.azure.cn/en-us/azure-resource-manager/bicep/bicep-config-linter).

Linting is useful, but I also validate the full deployment at subscription scope because it catches additional issues (note that this requires Azure login):

```yaml
- name: Validate Template
  run: |
	az deployment sub validate `
		--template-file './infra/main.bicep' `
		--location $env:AZURE_LOCATION `
		--parameters environmentName=$env:AZURE_ENV_NAME `
		             location=$env:AZURE_LOCATION
```

If the application code has unit tests, I run those too. The test results are stored in the `artifacts` folder and uploaded as workflow artifacts, which can be helpful for later inspection. Here's an example of running .NET tests, but you can adapt it to your test framework and language:

```yaml
- name: Run Unit Tests for Function App
  run: |
    dotnet run --report-trx --results-directory "${{ github.workspace }}/artifacts/TestResults/functionApp"
  working-directory: ./src/functionApp/TrackAvailabilityInAppInsights.FunctionApp.Tests

- name: Run Unit Tests for Logic App Workflows
  run: |
    dotnet run --report-trx --results-directory "${{ github.workspace }}/artifacts/TestResults/logicApp"
  working-directory: ./src/logicApp/Workflows.Tests

- name: Upload Unit Test Results
  if: always()
  uses: actions/upload-artifact@v6
  with:
    name: unit-test-results
    path: ./artifacts/TestResults/
    retention-days: 1
```

Note that the `if: always()` condition ensures that test results are uploaded even if some tests fail, which is important for diagnosing issues.

After validation, I package each app with `azd package` and upload artifacts. Here's an example for a Function App:

```yaml
- name: Create artifacts folder
	run: |
		mkdir -p ./artifacts

- name: Package Function App
	run: |
		azd package functionApp --output-path ./artifacts/functionapp-package.zip --no-prompt

- name: Upload Function App Package
	uses: actions/upload-artifact@v6
	with:
		name: functionapp-package
		path: ./artifacts/functionapp-package.zip
		retention-days: 1
```

A retention period of one day is enough for my PR validation scenario, but you can increase it if you need to debug runs later.

If the template includes integration tests, I build and publish those artifacts too:

```yaml
- name: Build Integration Tests
	run: |
		dotnet build ./tests/IntegrationTests/IntegrationTests.csproj --configuration Release --output ./artifacts/integration-tests

- name: Upload Integration Tests Package
	uses: actions/upload-artifact@v6
	with:
		name: integration-tests-package
		path: ./artifacts/integration-tests/
		retention-days: 1
```

I build the integration tests in this job, because if they don't build, there's no point in deploying to Azure. By building them here, I can fail fast and save time and resources.

### Deploy to Azure

I keep provisioning and app deployment in separate steps. We already packaged applications in the build job, and separation makes failures easier to diagnose.

Provisioning usually runs with `azd provision`. During provisioning, azd creates `.azure/<environment-name>/.env` and stores values from `main.bicep` outputs. Later jobs often need those values to connect to deployed resources.

In my workflows, I use this script to export selected azd environment values into job outputs:

- [export-azd-env-variables.ps1](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/.github/workflows/scripts/export-azd-env-variables.ps1)

The script reads values with [`azd env get-value`](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/reference#azd-env-get-value), then writes them as [job outputs in GitHub Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/pass-job-outputs). That makes it easy for later jobs to reuse values without recalculating them.

### Verify Deployment

The verification strategy depends on the template.

For templates with end-to-end tests, I download the integration test artifact and run .NET tests against deployed resources:

```yaml
- name: Download Integration Tests Package
	uses: actions/download-artifact@v6
	with:
		name: integration-tests-package
		path: ./artifacts/integration-tests

- name: Run Integration Tests
	run: |
		dotnet test ./tests/IntegrationTests/IntegrationTests.csproj `
			--configuration Release `
			--logger "trx;LogFileName=integration-tests.trx"
	env:
		APIM_BASE_URL: ${{ needs.deploy.outputs.apim-base-url }}
		FUNCTION_BASE_URL: ${{ needs.deploy.outputs.function-base-url }}

- name: Upload Integration Test Results
	if: always()
	uses: actions/upload-artifact@v6
	with:
		name: integration-test-results
		path: ./tests/IntegrationTests/TestResults/
		retention-days: 7
```

Templates can also perform other types of verification. For example, check that Azure Monitor availability tests executed successfully using a custom script:

```yaml
- name: Verify Availability Tests in Azure Monitor
	run: |
		./scripts/verify-availability-tests.ps1 `
			-ResourceGroupName ${{ needs.deploy.outputs.resource-group-name }} `
			-ApplicationInsightsName ${{ needs.deploy.outputs.appinsights-name }}
```

> You can find the script [here](https://github.com/ronaldbosma/track-availability-in-app-insights/blob/main/.github/workflows/scripts/) if you're interested.

If a script needs environment-specific values, use outputs from the deploy job.

### Clean Up Resources

The cleanup job runs `azd down` to remove all deployed resources.

If your `predown` or `postdown` hooks need values from the deployed environment, pass them from deploy job outputs just like in verification.

For pull request validation, automatic cleanup keeps subscription hygiene under control and prevents unnecessary cost.

### Add Cleanup Input Parameter

Besides PR verification, the workflow can also be used to spin up a temporary environment from e.g. the `main` branch. That's useful when you don't have azd installed locally or when you want to demo a branch quickly.

By default, I still clean up at the end. But I include a `cleanup-resources` input so I can keep resources when manually running the workflow:

```yaml
workflow_dispatch:
	inputs:
		cleanup-resources:
			description: 'Clean up resources after deployment'
			required: false
			default: true
			type: boolean
```

When the workflow is triggered manually, this input appears in the UI:

![GitHub Actions Workflow Manual Trigger](../../../../../images/github-actions-workflow-for-azd-templates/github-actions-workflow-manual-trigger.png)

When I uncheck this input in a manual run, the cleanup job is skipped. Later, I can trigger another run with cleanup enabled to remove the environment.


### Tips

- Keep the workflow understandable for template consumers
- Avoid too many custom tasks so others can adopt the template in their own repositories
- Print tool versions early to diagnose agent differences quickly
- Prefer workflow outputs for passing deployment values across jobs

### Conclusion

This workflow pattern gives me confidence when changing azd templates. It validates infrastructure and application behavior, supports external contributions and removes resources automatically.

The key is to keep jobs focused: build and package once, deploy predictably, verify behavior and clean up. With this setup, each pull request gets a repeatable end-to-end check that mirrors real usage.

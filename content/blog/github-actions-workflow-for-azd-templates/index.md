---
title: "GitHub Actions Workflow for Azure Developer CLI (azd) Templates"
date: 2026-02-21T16:30:00+01:00
publishdate: 2026-02-21T16:30:00+01:00
lastmod: 2026-02-21T16:30:00+01:00
tags: [ "Azure", "Azure Developer CLI", "GitHub Actions" ]
summary: "In this post, I'll show how I structure a GitHub Actions workflow for azd templates so I can build, deploy, verify and clean up with confidence. The workflow makes it easier to validate my own changes and review external contributions. I'll walk through each job with practical snippets and explain why I split build, deployment and verification."
draft: true
---

I've been working with Azure Developer CLI (azd) templates where each change can affect both infrastructure and application behavior. To make changes with more confidence, I include a GitHub Actions workflow that automates build, deployment, verification and cleanup.

This setup also helps when reviewing pull requests from other developers or automated tools. I can open a PR, let the workflow validate everything end to end and automatically remove all resources afterward.

### Table of Contents

- [Reference Workflows](#reference-workflows)
- [Workflow Structure](#workflow-structure)
- [Common Configuration](#common-configuration)
- [Build, Verify and Package](#build-verify-and-package)
- [Deploy to Azure](#deploy-to-azure)
- [Verify Deployment](#verify-deployment)
- [Clean Up Resources](#clean-up-resources)
- [Add Cleanup Input Parameter](#add-cleanup-input-parameter)
- [Tips](#tips)
- [Conclusion](#conclusion)

### Reference Workflows

I used the following resources while designing my workflow:

- [Explore Azure Developer CLI support for CI/CD pipelines](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/configure-devops-pipeline)
- [Create a GitHub Actions CI/CD pipeline using the Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/pipeline-github-actions)
- [Azure Developer CLI: From Dev to Prod with Azure DevOps Pipelines](https://devblogs.microsoft.com/devops/azure-developer-cli-from-dev-to-prod-with-azure-devops-pipelines/)

These two repositories contain complete workflow examples that match the approach in this post:

- [call-apim-with-managed-identity/.github/workflows/azure-dev.yml](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/.github/workflows/azure-dev.yml)
	- This template contains application code (Function App and Logic App) that is packaged during the build job
	- It also includes .NET integration tests that are packaged during build and executed in the Verify Deployment job
- [track-availability-in-app-insights/.github/workflows/azure-dev.yml](https://github.com/ronaldbosma/track-availability-in-app-insights/blob/main/.github/workflows/azure-dev.yml)
	- This template also contains a Function App and Logic App
	- It runs unit tests during build
	- Instead of integration tests, the Verify Deployment job runs a PowerShell script that checks availability test execution in Azure Monitor

### Workflow Structure

My workflows usually contain four jobs:

- **Build, Verify and Package**: Set up tools, validate Bicep and package deployable artifacts
- **Deploy to Azure**: Provision infrastructure and deploy packaged applications
- **Verify Deployment**: Run automated verification such as integration tests or Azure Monitor checks
- **Clean Up Resources**: Remove all deployed resources

Splitting these concerns into separate jobs makes troubleshooting easier. If provisioning succeeds but deployment fails, I can quickly see where it broke and which artifacts were used.

### Common Configuration

If my template has hooks, they are usually written in PowerShell. So I set PowerShell Core as the default shell at workflow level:

```yaml
defaults:
	run:
		shell: pwsh # Use PowerShell Core for all scripts (the azd hooks are written in PowerShell)
```

I also define these `env` variables for azd:

```yaml
env:
	# Add a unique suffix to the environment name for pull requests to avoid name conflicts
	AZURE_ENV_NAME: ${{ github.event.pull_request.number && format('{0}-pr{1}', vars.AZURE_ENV_NAME, github.event.pull_request.number) || vars.AZURE_ENV_NAME }}
	AZURE_LOCATION: ${{ vars.AZURE_LOCATION }}
	AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID || vars.AZURE_SUBSCRIPTION_ID }}
```

I add a pull request suffix to `AZURE_ENV_NAME` so parallel PRs in the same repository don't overwrite each other.

Notice the pattern `${{ secrets.AZURE_SUBSCRIPTION_ID || vars.AZURE_SUBSCRIPTION_ID }}`. Running `azd pipeline config` creates `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` as GitHub variables by default. However, [Microsoft recommends using secrets for these values](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect) to reduce the risk of exposing them in logs. Supporting both `secrets` and `vars` makes migration easy.

Most jobs use these steps:

1. Setup azd

```yaml
- name: Setup azd
	uses: Azure/setup-azd@v2
```

2. Configure azd to use Azure CLI auth and sign in with OIDC

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

3. Add `id-token: write` permission for any job that signs in to Azure with OIDC

```yaml
build-verify-package:
	name: Build, Verify and Package
	runs-on: ubuntu-latest
	permissions:
		id-token: write # Required to fetch an OIDC token for Azure authentication
```

### Build, Verify and Package

In this job, I set up required tools, validate infrastructure and package everything needed for deployment and verification.

If the template contains application code, this job usually installs tools such as .NET and Node.js.

I also print tool versions early. I once used a new Bicep feature that failed in CI because the runner had an older version. This step made the mismatch obvious:

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

My repositories usually include a `bicepconfig.json` where almost all rules are set to `error`, so the workflow fails quickly when the template doesn't comply. For details, see [Add linter settings in the Bicep config file](https://docs.azure.cn/en-us/azure-resource-manager/bicep/bicep-config-linter).

Linting is useful, but I also validate the full deployment at subscription scope because it catches additional issues:

```yaml
- name: Validate Template
	run: |
		az deployment sub validate `
			--template-file './infra/main.bicep' `
			--location $env:AZURE_LOCATION `
			--parameters environmentName=$env:AZURE_ENV_NAME `
									 location=$env:AZURE_LOCATION
```

This command requires Azure authentication.

After validation, I package each app with `azd package` and upload artifacts:

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

If integration tests exist, I build and publish those artifacts too:

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

This avoids deploying to Azure when tests fail to build.

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

For templates without integration tests, I run a PowerShell validation script instead, for example to check that Azure Monitor availability tests executed successfully:

```yaml
- name: Verify Availability Tests in Azure Monitor
	run: |
		./scripts/verify-availability-tests.ps1 `
			-ResourceGroupName ${{ needs.deploy.outputs.resource-group-name }} `
			-ApplicationInsightsName ${{ needs.deploy.outputs.appinsights-name }}
```

If a script needs environment-specific values, use outputs from the deploy job.

### Clean Up Resources

The cleanup job runs `azd down` to remove all deployed resources.

If your `predown` or `postdown` hooks need values from the deployed environment, pass them from deploy job outputs just like in verification.

For pull request validation, automatic cleanup keeps subscription hygiene under control and prevents unnecessary cost.

### Add Cleanup Input Parameter

Besides PR verification, this workflow can also spin up a temporary environment. That's useful when you don't have azd installed locally or when you want to demo a branch quickly.

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

When I uncheck this input in a manual run, the cleanup job is skipped. Later, I can trigger another run with cleanup enabled to remove the environment.

### Tips

- Keep the workflow understandable for template consumers
- Avoid too many custom tasks so others can adopt the template in their own repositories
- Print tool versions early to diagnose agent differences quickly
- Prefer workflow outputs for passing deployment values across jobs

### Conclusion

This workflow pattern gives me confidence when changing azd templates. It validates infrastructure and application behavior, supports external contributions and removes resources automatically.

The key is to keep jobs focused: build and package once, deploy predictably, verify behavior and clean up. With this setup, each pull request gets a repeatable end-to-end check that mirrors real usage.

# Research: Logic Apps Standard Workflow Client

## Key Findings

- All four source files from `ronaldbosma/call-apim-with-managed-identity` were successfully fetched and verified.
- `WorkflowTriggerResource.CreateResourceIdentifier` and `GetCallbackUrlAsync()` are confirmed present in `Azure.ResourceManager.AppService` v1.4.1 (published 2025-08-11) per official Microsoft Learn docs.
- The `Lazy<Task<HttpClient>>` pattern, `ChainedTokenCredential`, `PostAsync<T>`, and `IDisposable` implementation are all in the live source file as the brief describes.
- The Logic Apps Standard ARM REST API path for `listCallbackUrl` is under `Microsoft.Web/sites` (not `Microsoft.Logic`); the SDK wraps this correctly.
- **RBAC action claim in brief is incorrect.** The actual action is `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action`, not the brief's suspected `Microsoft.Web/sites/workflows/triggers/listCallbackUrl/action`.
- Default trigger name `When_a_HTTP_request_is_received` is consistent with the Logic Apps Standard designer, which names the trigger "When a HTTP request is received" (spaces become underscores in the internal resource name).
- `AzureDeveloperCliCredentialOptions.TenantId` property exists in Azure.Identity v1.21.0 (released 2026-04-10); the TenantId workaround remains relevant in CI/CD.
- Target framework is `net10.0`; the post should note this explicitly.
- `LogicAppTests.cs` exists in the repo and provides a concrete usage example.

---

## Official Documentation

### Azure.ResourceManager.AppService — WorkflowTriggerResource

- **URL**: https://learn.microsoft.com/en-us/dotnet/api/azure.resourcemanager.appservice.workflowtriggerresource?view=azure-dotnet
- **Type**: Official Microsoft Learn API reference
- `WorkflowTriggerResource.CreateResourceIdentifier(String, String, String, String, String)` — static method that generates a `ResourceIdentifier`. Parameters: `subscriptionId`, `resourceGroupName`, `name` (Logic App site name), `workflowName`, `triggerName`.
- `GetCallbackUrlAsync(CancellationToken)` — async method; wraps the ARM operation `WorkflowTriggers_ListCallbackUrl`.
  - Request path: `POST /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Web/sites/{name}/hostruntime/runtime/webhooks/workflow/api/management/workflows/{workflowName}/triggers/{triggerName}/listCallbackUrl`
  - Default API version used by SDK: **2024-11-01**
- Both methods are confirmed present in the package as of the latest docs page.

### NuGet — Azure.ResourceManager.AppService v1.4.1

- **URL**: https://www.nuget.org/packages/Azure.ResourceManager.AppService/1.4.1
- Published: **2025-08-11**
- Latest stable version as of research date.
- Targets: `netstandard2.0`, `net8.0` (and computes for net9.0, net10.0).
- Dependencies: `Azure.Core >= 1.47.1`, `Azure.ResourceManager >= 1.13.2`.

### ARM REST API — Logic Apps Standard (Microsoft.Web)

- **URL**: https://learn.microsoft.com/en-us/rest/api/appservice/workflow-triggers/list-callback-url
- `POST https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Web/sites/{name}/hostruntime/runtime/webhooks/workflow/api/management/workflows/{workflowName}/triggers/{triggerName}/listCallbackUrl?api-version=2025-05-01`
- Response body `value` field contains the full callback URL including SAS query parameters (`sig`, `sp`, `sv`, `se`).
- **Important**: This is the **Standard** (App Service-hosted) path. The Consumption Logic Apps path is different: `providers/Microsoft.Logic/workflows/{workflowName}/triggers/{triggerName}/listCallbackUrl` (api-version 2019-05-01). The SDK class `WorkflowTriggerResource` targets the Standard path only.

### ARM REST API — Logic Apps Consumption (Microsoft.Logic) — for contrast only

- **URL**: https://learn.microsoft.com/en-us/rest/api/logic/workflow-triggers/list-callback-url
- Listed here only to document the difference; the blog post's implementation does **not** use this path.

### RBAC Permissions — Microsoft.Web

- **URL**: https://learn.microsoft.com/en-us/azure/role-based-access-control/permissions/web-and-mobile#microsoftweb
- The action covering the callback URL retrieval is:
  - `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action`
  - Description: "Get Web Apps Hostruntime Workflow Trigger Uri."
- **The brief's suspected action `Microsoft.Web/sites/workflows/triggers/listCallbackUrl/action` does not appear in the permissions list and appears to be incorrect.**
- Also relevant in the same namespace: `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/run/action` (triggering the workflow directly).

### Logic Apps Standard Built-in RBAC Roles

- **URL**: https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app
- Four Standard-specific roles (all currently in **Preview**):
  - **Logic Apps Standard Reader (Preview)** — read-only.
  - **Logic Apps Standard Operator (Preview)** — enable/disable workflows, resubmit runs, create connections. Likely covers `listCallbackUrl`.
  - **Logic Apps Standard Developer (Preview)** — create/edit workflows and connections.
  - **Logic Apps Standard Contributor (Preview)** — full management, no access/ownership changes.
- The generic **Contributor** role also grants the `listCallbackUrl` action via its broad `Microsoft.Web/sites/*` permissions.
- **The minimum role for GetCallbackUrlAsync()** is most likely **Logic Apps Standard Operator (Preview)** or **Logic Apps Standard Contributor (Preview)**. A custom role containing only `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action` would also suffice.
- ⚠️ The Standard roles are marked **(Preview)** — flag this in the post if recommending them.

### Logic Apps HTTP Endpoint (Trigger Name Verification)

- **URL**: https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-http-endpoint
- The Logic Apps Standard designer names the HTTP trigger **"When a HTTP request is received"**.
- The ARM resource identifier uses underscores for spaces, so the internal `triggerName` is `When_a_HTTP_request_is_received`.
- **Claim verified**: The default value used in the constructor matches the designer-generated name.

### Azure.Identity — AzureDeveloperCliCredential and Options

- **URL (credential)**: https://learn.microsoft.com/en-us/dotnet/api/azure.identity.azuredeveloperclicredential?view=azure-dotnet
- **URL (options)**: https://learn.microsoft.com/en-us/dotnet/api/azure.identity.azuredeveloperclicredentialoptions?view=azure-dotnet
- `AzureDeveloperCliCredentialOptions.TenantId` property is confirmed present.
  - Docs say: "If not specified, the credential will authenticate to any requested tenant, and will default to the tenant provided to the 'azd auth login' command."
  - In CI/CD, `azd auth login` with a service principal may default to the **Microsoft Services tenant** (`72f988bf-86f1-41af-91ab-2d7cd011db47`) rather than the target subscription's tenant. Providing an explicit `TenantId` forces the credential to the correct tenant.
- The `TenantId` workaround is **still relevant in Azure.Identity v1.21.0**.

### Azure.Identity Changelog (v1.21.0)

- **URL**: https://github.com/Azure/azure-sdk-for-net/blob/main/sdk/identity/Azure.Identity/CHANGELOG.md
- v1.21.0 released **2026-04-10**: All `Azure.Identity` types moved to `Azure.Core` via `TypeForwardedTo` — non-breaking change.
- v1.18.0 (2026-02-25): `AzureDeveloperCliCredential` now parses JSON error output from `azd auth token` for cleaner error messages.
- v1.16.0 (2025-09-09): `AzureDeveloperCliCredential` now throws `AuthenticationFailedException` when `TokenRequestContext` includes claims (does not support claims challenges).
- No changes in v1.21.0 that affect the TenantId behaviour or the credential chain pattern used in the sample.

---

## GitHub Evidence

### Repository: `ronaldbosma/call-apim-with-managed-identity` (branch `main`)

**Primary source: `LogicAppWorkflowClient.cs`**

- **URL**: https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/Clients/LogicAppWorkflowClient.cs
- File fetched and verified. Full content below in Code Examples.

Key design decisions observed in the live file:

| Element | Detail |
|---|---|
| Namespace | `IntegrationTests.Clients` |
| Access modifier | `internal` |
| Credential chain | `ChainedTokenCredential(new AzureCliCredential(), new AzureDeveloperCliCredential(...))` |
| Lazy init | `Lazy<Task<HttpClient>>` — deferred, executes once on first `PostAsync` |
| Callback URL retrieval | `WorkflowTriggerResource.CreateResourceIdentifier` + `armClient.GetWorkflowTriggerResource` + `GetCallbackUrlAsync()` |
| HttpClient base address | `callbackUrl.Value.Value` (the full URL string from ARM response) |
| Default trigger name | `"When_a_HTTP_request_is_received"` |
| `PostAsync<T>` | Serialises `data` to JSON, sends to `string.Empty` relative URI (BaseAddress is the full URL) |
| Disposal | Checks `_httpClientLazy.IsValueCreated` and `httpClientTask.IsCompletedSuccessfully` before disposing |
| `ArgumentNullException` guard | Applied to all constructor parameters in the 6-argument overload; `tenantId` is notably **not** null-checked (can be empty/null for `AzureCliCredential` path) |

**Usage example: `LogicAppTests.cs`**

- **URL**: https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/LogicAppTests.cs
- File fetched and verified.
- Uses `[ClassInitialize]` / `[ClassCleanup]` pattern to create and dispose a single shared `LogicAppWorkflowClient` instance across all tests in the class (avoids redundant callback URL fetches).
- Passes `"call-protected-api-workflow"` as the workflow name; uses default trigger name (not specified, so constructor defaults to `"When_a_HTTP_request_is_received"`).
- Three test methods: GET → 200, POST → 200, DELETE → 401 (tests RBAC on the protected downstream API, not on Logic Apps itself).
- Configuration loaded from `TestConfiguration.Load()` — reads `AzureTenantId`, `AzureSubscriptionId`, `AzureResourceGroup`, `AzureLogicAppName`.

**Supporting file: `IntegrationTestHttpClient.cs`**

- **URL**: https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/Clients/IntegrationTestHttpClient.cs
- Extends `HttpClient`; sets `BaseAddress` in constructor.
- Uses `HttpMessageLoggingHandler(new HttpClientHandler())` as the message handler chain — logs HTTP requests and responses.
- The handler is in the `IntegrationTests.Clients.Handlers` namespace (handler source not fetched separately; not in scope for this post).
- `LogicAppWorkflowClient` passes `callbackUrl.Value.Value` (a `string`) to `IntegrationTestHttpClient(string baseAddress)` constructor.

**Project file: `IntegrationTests.csproj`**

- **URL**: https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/IntegrationTests.csproj
- SDK: `MSTest.Sdk/4.2.2`
- Target framework: `net10.0`
- Language version: `latest`
- NuGet packages relevant to this post:
  - `Azure.Identity` **1.21.0**
  - `Azure.ResourceManager.AppService` **1.4.1**
  - `dotenv.net` 4.0.2 (config loading for local dev)
  - `Microsoft.Extensions.Configuration` 10.0.7 (and related packages)

---

## Best Practices

### Why not hardcode the callback URL

- The URL contains a SAS token with query parameters `sig` (signature), `sp` (permissions), `sv` (version), and optionally `se` (expiry timestamp). **(Official, from ARM REST API docs)**
- Hardcoding causes failures when the SAS rotates; retrieving it programmatically at test startup is the safe pattern.

### Lazy initialisation

- `Lazy<Task<HttpClient>>` defers the ARM API call until the first HTTP request is actually needed, keeping test class setup fast. **(Implementation evidence, LogicAppWorkflowClient.cs)**
- A single instance is shared across tests in a class (see `LogicAppTests.cs`) so the ARM lookup runs only once per test class execution.

### ChainedTokenCredential for local + CI/CD portability

- `AzureCliCredential` works for local development when the developer is logged in with `az login`.
- `AzureDeveloperCliCredential` covers CI/CD pipelines that use `azd auth login`; `TenantId` must be set explicitly to prevent it picking up the Microsoft Services tenant in multi-tenant CI/CD environments. **(Implementation evidence + Azure.Identity official docs)**
- Ordering matters: `AzureCliCredential` is first so it wins for local dev; `AzureDeveloperCliCredential` is the fallback.

### Disposal pattern for async-initialised resources

- The `Dispose` method checks `_httpClientLazy.IsValueCreated` before accessing `.Value` to avoid triggering initialisation during disposal.
- `httpClientTask.IsCompletedSuccessfully` prevents accessing `.Result` on a faulted or cancelled task. **(Implementation evidence)**

### RBAC for pipeline identity

- Grant the pipeline's service principal `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action` on the Logic App resource (or resource group).
- The minimum built-in role is likely **Logic Apps Standard Operator (Preview)**. **Contributor** also works but is over-privileged for this single operation.
- A custom role containing only the `listCallbackUrl` action is the least-privilege option. **(Official RBAC permissions docs)**

---

## Code Examples

### LogicAppWorkflowClient.cs (full, from repo)

```csharp
using System.Text;
using System.Text.Json;

using Azure.Identity;
using Azure.ResourceManager;
using Azure.ResourceManager.AppService;

namespace IntegrationTests.Clients
{
    internal class LogicAppWorkflowClient : IDisposable
    {
        private readonly string _tenantId;
        private readonly string _subscriptionId;
        private readonly string _resourceGroupName;
        private readonly string _logicAppName;
        private readonly string _workflowName;
        private readonly string _triggerName;

        private readonly Lazy<Task<HttpClient>> _httpClientLazy;
        private bool _disposed;

        public LogicAppWorkflowClient(string tenantId, string subscriptionId, string resourceGroupName, string logicAppName, string workflowName)
            : this(tenantId, subscriptionId, resourceGroupName, logicAppName, workflowName, "When_a_HTTP_request_is_received")
        {
        }

        public LogicAppWorkflowClient(string tenantId, string subscriptionId, string resourceGroupName, string logicAppName, string workflowName, string triggerName)
        {
            _tenantId = tenantId;
            _subscriptionId = subscriptionId ?? throw new ArgumentNullException(nameof(subscriptionId));
            _resourceGroupName = resourceGroupName ?? throw new ArgumentNullException(nameof(resourceGroupName));
            _logicAppName = logicAppName ?? throw new ArgumentNullException(nameof(logicAppName));
            _workflowName = workflowName ?? throw new ArgumentNullException(nameof(workflowName));
            _triggerName = triggerName ?? throw new ArgumentNullException(nameof(triggerName));

            _httpClientLazy = new Lazy<Task<HttpClient>>(CreateHttpClientAsync);
        }

        private async Task<HttpClient> CreateHttpClientAsync()
        {
            var tokenCredential = new ChainedTokenCredential(
                new AzureCliCredential(),
                new AzureDeveloperCliCredential(new AzureDeveloperCliCredentialOptions { TenantId = _tenantId })
            );
            var armClient = new ArmClient(tokenCredential);

            var workflowTriggerId = WorkflowTriggerResource.CreateResourceIdentifier(
                subscriptionId: _subscriptionId,
                resourceGroupName: _resourceGroupName,
                name: _logicAppName,
                workflowName: _workflowName,
                triggerName: _triggerName
            );

            var workflowTrigger = armClient.GetWorkflowTriggerResource(workflowTriggerId);
            var callbackUrl = await workflowTrigger.GetCallbackUrlAsync();

            return new IntegrationTestHttpClient(callbackUrl.Value.Value);
        }

        public async Task<HttpResponseMessage> PostAsync<T>(T data)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);

            var httpClient = await _httpClientLazy.Value;

            var requestUri = string.Empty;
            var json = JsonSerializer.Serialize(data);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            return await httpClient.PostAsync(requestUri, content);
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                if (_httpClientLazy.IsValueCreated)
                {
                    var httpClientTask = _httpClientLazy.Value;
                    if (httpClientTask.IsCompletedSuccessfully)
                    {
                        httpClientTask.Result.Dispose();
                    }
                }
                _disposed = true;
            }
        }
    }
}
```

*Source: `tests/IntegrationTests/Clients/LogicAppWorkflowClient.cs`, branch `main`*

### LogicAppTests.cs — usage pattern

```csharp
[TestClass]
public sealed class LogicAppTests
{
    private static LogicAppWorkflowClient? WorkflowClient;

    [ClassInitialize]
    public static void ClassInitialize(TestContext context)
    {
        var config = TestConfiguration.Load();
        WorkflowClient = new LogicAppWorkflowClient(
            config.AzureTenantId,
            config.AzureSubscriptionId,
            config.AzureResourceGroup,
            config.AzureLogicAppName,
            "call-protected-api-workflow"
        );
    }

    [ClassCleanup]
    public static void ClassCleanup() => WorkflowClient?.Dispose();

    [TestMethod]
    public async Task PostAsyncWithGetHttpMethod_..._200OkReturned()
    {
        var requestData = new { httpMethod = "GET" };
        var response = await WorkflowClient!.PostAsync(requestData);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }
}
```

*Source: `tests/IntegrationTests/LogicAppTests.cs`, branch `main` (condensed for illustration)*

### ARM REST API path for Logic Apps Standard (for writer's reference)

```
POST https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}
     /providers/Microsoft.Web/sites/{name}/hostruntime/runtime/webhooks/workflow/api/management
     /workflows/{workflowName}/triggers/{triggerName}/listCallbackUrl?api-version=2025-05-01
```

*Source: https://learn.microsoft.com/en-us/rest/api/appservice/workflow-triggers/list-callback-url*

---

## Versions and Dates

| Component | Version | Date / Notes |
|---|---|---|
| `Azure.ResourceManager.AppService` | 1.4.1 | Published 2025-08-11 (latest stable) |
| `Azure.Identity` | 1.21.0 | Released 2026-04-10 |
| Target framework | `net10.0` | — |
| MSTest SDK | 4.2.2 | — |
| ARM API default version (SDK) | 2024-11-01 | Used by `WorkflowTriggerResource` |
| ARM REST API (docs) | 2025-05-01 | Latest in REST reference |
| Logic Apps Standard RBAC roles | — | All four roles are marked **(Preview)** |

---

## Notes for Writers

### Claims verified

1. **Default trigger name** — ✅ Verified. The Logic Apps Standard designer labels the trigger "When a HTTP request is received"; the ARM internal name uses underscores: `When_a_HTTP_request_is_received`. The default value in the constructor is correct.

2. **ARM SDK types** — ✅ Verified. `WorkflowTriggerResource.CreateResourceIdentifier(String, String, String, String, String)` and `GetCallbackUrlAsync()` both exist in `Azure.ResourceManager.AppService`. The 5-parameter signature of `CreateResourceIdentifier` matches the code: `(subscriptionId, resourceGroupName, name, workflowName, triggerName)`.

3. **RBAC action** — ⚠️ **Brief's suspected action is wrong.** The correct action is `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action`, not `Microsoft.Web/sites/workflows/triggers/listCallbackUrl/action`. The description on the RBAC page is "Get Web Apps Hostruntime Workflow Trigger Uri." Recommend using **Logic Apps Standard Operator (Preview)** as the minimum named role, or creating a custom role. Note the Logic Apps Standard roles are in preview; alternatively use **Contributor** with a caveat about over-provisioning.

4. **AzureDeveloperCliCredential TenantId** — ✅ Still relevant in Azure.Identity v1.21.0. The `TenantId` property in `AzureDeveloperCliCredentialOptions` exists and is documented as "defaults to the tenant provided to the 'azd auth login' command", which in CI/CD may be the Microsoft Services tenant. No change to this behaviour in v1.21.0.

### Open questions from brief

- **Open question #2 (series membership)**: No evidence found that this should be part of the `oauth-and-api-management` series. The topic (integration testing via callback URL) is distinct from the OAuth/managed-identity focus of that series. Standalone post is the safe default; cross-reference to the existing series post is appropriate.
- **Open question #4 (Bicep scope)**: The brief says the author wants to "explain the code" only; no Bicep snippet for RBAC role assignment was found in the source files. The ARM RBAC action name identified above would be needed if Bicep is added in scope, but it should be confirmed with the author. Out of scope for now.
- **Open question #5 (`IntegrationTestHttpClient` depth)**: Source file confirms it is a thin wrapper: sets `BaseAddress` and wraps `HttpClientHandler` with `HttpMessageLoggingHandler`. Recommended treatment: brief mention with a link/reference, not a deep dive.
- **Open question #6 (CI/CD auth mechanism)**: The csproj and test files use `AzureDeveloperCliCredential` but do not show the pipeline YAML. The `call-apim-with-managed-identity` repo likely has an `azure-pipelines.yml` or GitHub Actions file; not fetched. The credential chain comment in the source code implies `azd auth login` is used in CI, consistent with the related "GitHub Actions Workflow for azd Templates" post.

### Gaps and things still to confirm

- **`HttpMessageLoggingHandler` source not fetched**: It is in `IntegrationTests.Clients.Handlers` namespace but the file path was not in the brief's source list. If the author wants to mention logging, note it exists without detailing it.
- **`TestConfiguration` class source not fetched**: Used in `LogicAppTests.cs` to read environment variables/config. Sufficient context is available from usage; no need to fetch for this post.
- **Logic Apps Standard Operator role permissions detail**: The securing-a-logic-app page lists the role exists but does not enumerate its exact actions. It is reasonable to assert it covers `listCallbackUrl` but this is an inference. A custom minimal role is the safest recommendation.
- **SAS expiry**: The REST API response schema includes `se` (SAS timestamp) in the queries object. The docs do not specify how long the token is valid; the "cannot be hardcoded" motivation is correct but the exact expiry period is not documented here. Do not state a specific time.
- **`ObjectDisposedException.ThrowIf`**: This API was introduced in .NET 7. Since the project targets `net10.0` this is fine, but worth noting if the author plans to support older frameworks.
- **MCP tools**: Azure MCP and Bicep MCP were not used (not available in this environment). All research was performed via `web_fetch` against official Microsoft Learn docs, NuGet, and raw GitHub source files. GitHub MCP was not used; raw file URLs were fetched directly. All source URLs returned live content at time of research.

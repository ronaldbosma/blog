# Plan: Logic Apps Standard Workflow Client

## Meta

| Field | Value |
|---|---|
| Slug | `logic-apps-standard-workflow-client` |
| Audience | .NET developers writing integration tests for Azure solutions that include Logic Apps Standard workflows with HTTP triggers |
| Post Type | Short tutorial / code walkthrough |
| Candidate Titles | "Calling a Logic Apps Standard Workflow from C# Integration Tests" *(recommended — most search-friendly and action-oriented)* · "A C# Client for Triggering Logic Apps Standard Workflows in Integration Tests" · "Retrieving the Logic Apps Standard Callback URL Programmatically in C#" |
| Primary Takeaway | Use `WorkflowTriggerResource.GetCallbackUrlAsync()` from `Azure.ResourceManager.AppService` to retrieve the SAS-bearing callback URL at test startup, wrap it in a `Lazy<Task<HttpClient>>`, and invoke the workflow from C# integration tests — no hardcoding required. |
| Table of Contents | **No.** Author flagged this as a small post; a ToC would not add value here. |
| Series | Standalone (not part of the `oauth-and-api-management` series; topic is distinct). Cross-reference to related posts where relevant. |

---

## Angle

### The concrete problem

Every Logic Apps Standard HTTP-triggered workflow exposes a unique callback URL that contains a short-lived SAS token (query parameters `sig`, `sp`, `sv`, `se`). Hardcoding this URL in integration tests causes failures as soon as the token rotates. The URL also cannot be stored safely in source control.

### The practical solution

A small helper class, `LogicAppWorkflowClient`, calls the Azure Resource Manager API through the `Azure.ResourceManager.AppService` SDK to retrieve a fresh callback URL at test startup. A `Lazy<Task<HttpClient>>` defers the ARM call until the first request is needed and ensures it runs only once per test class. A `ChainedTokenCredential` makes the same code work locally (via `az login`) and in CI/CD pipelines (via `azd auth login`) without changes.

---

## Outline

### Section 1 — Introduction

**Learning objective:** Understand why callback URLs cannot be hardcoded and what the post will demonstrate.

**Key points:**
- Brief personal context: writing integration tests for a Logic Apps Standard workflow.
- The callback URL embeds a SAS token; it changes over time and must not be hardcoded.
- The post walks through `LogicAppWorkflowClient`, a C# helper class that retrieves the URL dynamically via the ARM SDK.
- Note target framework (`net10.0`) and NuGet packages used.

**Code examples:** None in this section.

**Supporting references:**
- SAS token fields documented in ARM REST API response: `research.md` § *ARM REST API — Logic Apps Standard (Microsoft.Web)*
- NuGet package versions and target framework: `research.md` § *Project file: IntegrationTests.csproj*

---

### Section 2 — NuGet Packages

**Learning objective:** Know which packages to add and why.

**Key points:**
- `Azure.ResourceManager.AppService` 1.4.1 — provides `WorkflowTriggerResource` and the ARM client abstraction.
- `Azure.Identity` 1.21.0 — provides `ChainedTokenCredential`, `AzureCliCredential`, `AzureDeveloperCliCredential`.
- Both are the versions used in the sample repo; they are the latest stable versions at time of writing.
- Link to `Azure.ResourceManager.AppService` on NuGet and the official Microsoft Learn API reference on first mention.

**Code examples:**

```xml
<!-- language: xml — scope: csproj PackageReference snippet -->
<PackageReference Include="Azure.Identity" Version="1.21.0" />
<PackageReference Include="Azure.ResourceManager.AppService" Version="1.4.1" />
```

Source: `IntegrationTests.csproj` (verified in repo).

**Supporting references:**
- `research.md` § *NuGet — Azure.ResourceManager.AppService v1.4.1*
- `research.md` § *Project file: IntegrationTests.csproj*

---

### Section 3 — The LogicAppWorkflowClient Class

**Learning objective:** Understand how `LogicAppWorkflowClient` is structured and why each design decision was made.

Recommended approach: present the complete class first (show working example), then explain each important part in sequence below it — in line with the "show working examples before diving into deeper explanation" guidance.

**Key points and sub-topics:**

#### 3a — Full class listing

Present `LogicAppWorkflowClient.cs` in its entirety as a single fenced C# code block so the reader can copy it immediately.

Source: `tests/IntegrationTests/Clients/LogicAppWorkflowClient.cs` (verified, full content in `research.md`).

#### 3b — Constructor parameters and default trigger name

- Six-parameter overload accepts `tenantId`, `subscriptionId`, `resourceGroupName`, `logicAppName`, `workflowName`, `triggerName`.
- Five-parameter convenience overload defaults `triggerName` to `"When_a_HTTP_request_is_received"`.
- Explain where this name comes from: the Logic Apps Standard designer labels the trigger "When a HTTP request is received"; ARM converts spaces to underscores in the resource name.
- Link to the Logic Apps HTTP endpoint docs on first mention of the trigger.

#### 3c — Retrieving the callback URL with the ARM SDK

- `WorkflowTriggerResource.CreateResourceIdentifier` takes five parameters: `subscriptionId`, `resourceGroupName`, `name` (Logic App site name), `workflowName`, `triggerName` — clarify the `name` parameter refers to the Logic App resource name, not the workflow.
- `armClient.GetWorkflowTriggerResource(workflowTriggerId)` gets a proxy object; the ARM call happens in the next step.
- `GetCallbackUrlAsync()` makes the actual ARM POST to the `listCallbackUrl` endpoint and returns the full URL string at `callbackUrl.Value.Value`.
- Link to `WorkflowTriggerResource` on Microsoft Learn on first mention.
- Note the Standard path is under `Microsoft.Web/sites` (not `Microsoft.Logic`); mention the distinction briefly so readers who have used Consumption Logic Apps are not confused.

#### 3d — Lazy initialisation: `Lazy<Task<HttpClient>>`

- Wrapping `CreateHttpClientAsync` in `Lazy<Task<HttpClient>>` defers the ARM API call until the first `PostAsync` call.
- Because a single `LogicAppWorkflowClient` instance is shared across tests, the ARM lookup happens only once per test class run.
- Explain why this matters: avoids unnecessary ARM calls when setting up the test class and keeps `ClassInitialize` fast.

#### 3e — Credential chain: `ChainedTokenCredential`

- `AzureCliCredential` (first) — used in local development; requires `az login`.
- `AzureDeveloperCliCredential` (fallback) — used in CI/CD pipelines that use `azd auth login`.
- `TenantId` must be set explicitly on `AzureDeveloperCliCredentialOptions`. In CI/CD, `azd auth login` with a service principal can default to the Microsoft Services tenant (`72f988bf-86f1-41af-91ab-2d7cd011db47`) rather than the target subscription's tenant. Passing `TenantId` forces the credential to the correct tenant.
- This behaviour is still present in Azure.Identity v1.21.0.

#### 3f — `PostAsync<T>` method

- Serialises `data` as JSON using `System.Text.Json`.
- Posts to `string.Empty` as the relative URI because the full callback URL (including SAS token) is already set as `BaseAddress` on the `HttpClient`.
- Explain why `string.Empty` is correct here.

#### 3g — `IntegrationTestHttpClient`

- Briefly note that `LogicAppWorkflowClient` creates an `IntegrationTestHttpClient` (an `HttpClient` subclass) rather than a plain `HttpClient`, passing `callbackUrl.Value.Value` as `BaseAddress`.
- `IntegrationTestHttpClient` wraps a `HttpMessageLoggingHandler` for request/response logging — useful in test output.
- This class is outside the scope of this post; mention it without a deep dive and link to its location in the repository.

#### 3h — Disposal pattern

- `Dispose` checks `_httpClientLazy.IsValueCreated` before accessing `.Value` to avoid triggering lazy initialisation during teardown.
- `httpClientTask.IsCompletedSuccessfully` guards against accessing `.Result` on a faulted or cancelled task.
- Keep this explanation brief; the pattern is clear from the code.

**Code examples:**

- Full `LogicAppWorkflowClient.cs` listing (C#) — from repo; content in `research.md`.
- No additional isolated snippets needed; the full class plus inline callouts covers all sub-topics.

**Supporting references:**
- `research.md` § *Primary source: LogicAppWorkflowClient.cs* (full source + design decision table)
- `research.md` § *Azure.ResourceManager.AppService — WorkflowTriggerResource* (SDK method signatures)
- `research.md` § *Azure.Identity — AzureDeveloperCliCredential and Options* (TenantId behaviour)
- `research.md` § *Logic Apps HTTP Endpoint (Trigger Name Verification)*
- `research.md` § *Supporting file: IntegrationTestHttpClient.cs*

---

### Section 4 — RBAC: Granting the Pipeline Identity Access

**Learning objective:** Know which Azure RBAC permission is required for `GetCallbackUrlAsync()` and how to assign it with the principle of least privilege.

**Key points:**
- The ARM operation that `GetCallbackUrlAsync()` wraps requires the action:
  `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action`
  — description on the RBAC permissions page: "Get Web Apps Hostruntime Workflow Trigger Uri."
- ⚠️ **Correction from brief**: the brief suspected `Microsoft.Web/sites/workflows/triggers/listCallbackUrl/action`, which does not exist; use the verified action above.
- Built-in role options (assign on the Logic App resource or its resource group):
  - **Logic Apps Standard Operator (Preview)** — minimum named role; note the preview caveat.
  - **Contributor** — also works but over-privileged for this single operation.
  - **Custom role** containing only the `listCallbackUrl` action — the least-privilege option.
- Recommend the Contributor role as the practical quick-start, call out Logic Apps Standard Operator as the more precise option, and mention the custom role as the least-privilege path — let the reader choose based on their security posture.
- Note all four Logic Apps Standard built-in roles are currently in Preview.
- No Bicep snippet — author confirmed infrastructure setup is out of scope for this post. If this changes, see Research Gaps.

**Code examples:** None required (role assignment is a portal/CLI step, not a code walkthrough).

**Supporting references:**
- `research.md` § *RBAC Permissions — Microsoft.Web*
- `research.md` § *Logic Apps Standard Built-in RBAC Roles*

---

### Section 5 — Using the Client in Integration Tests

**Learning objective:** See a concrete usage example and understand how to wire `LogicAppWorkflowClient` into an MSTest test class.

**Key points:**
- Create a single shared `LogicAppWorkflowClient` instance per test class using `[ClassInitialize]` and dispose it in `[ClassCleanup]`.
- Sharing the instance means the ARM callback-URL lookup runs only once, regardless of how many test methods exist.
- Configuration (`AzureTenantId`, `AzureSubscriptionId`, `AzureResourceGroup`, `AzureLogicAppName`) is loaded from `TestConfiguration` (reads environment variables / `.env` files via `dotenv.net`); this pattern keeps secrets out of code.
- `PostAsync` is called with an anonymous object; responses are asserted normally.
- The workflow name (`"call-protected-api-workflow"`) is passed as a constructor argument; the trigger name defaults to `"When_a_HTTP_request_is_received"`.

**Code examples:**

```csharp
// language: csharp — scope: condensed usage snippet from LogicAppTests.cs
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
    public async Task PostAsync_WithGetHttpMethod_Returns200Ok()
    {
        var requestData = new { httpMethod = "GET" };
        var response = await WorkflowClient!.PostAsync(requestData);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }
}
```

Source: `tests/IntegrationTests/LogicAppTests.cs` (condensed; verified in repo).

**Supporting references:**
- `research.md` § *Usage example: LogicAppTests.cs*

---

### Section 6 — Conclusion

**Learning objective:** Summarise what was built and why it is a better approach than hardcoding.

**Key points:**
- Recap: `LogicAppWorkflowClient` retrieves a fresh callback URL from ARM at test startup, so tests never break due to SAS rotation.
- The `Lazy<Task<HttpClient>>` + `ChainedTokenCredential` pattern works in both local dev and CI/CD without configuration changes.
- Point the reader to the full source in `ronaldbosma/call-apim-with-managed-identity`.
- Cross-reference the related posts:
  - "Call OAuth-Protected APIs with Managed Identity from Logic Apps" for context on what the workflow itself does.
  - "GitHub Actions Workflow for Azure Developer CLI (azd) Templates" for how the integration tests are run in the CI/CD pipeline.

**Code examples:** None.

**Supporting references:** Cross-references from `brief.md` § *Related Existing Posts*.

---

## Required Assets

| Asset | Purpose | Status |
|---|---|---|
| No images or diagrams | Post is a focused code walkthrough; no architecture diagrams are needed | — |
| Source files in repo | `LogicAppWorkflowClient.cs` and `LogicAppTests.cs` must be present in `ronaldbosma/call-apim-with-managed-identity` at publish time | Verified present on branch `main` |

---

## Open Questions

1. **Preferred title** — Author has not indicated a preference among the three candidates. Recommended: "Calling a Logic Apps Standard Workflow from C# Integration Tests". Confirm before finalising front matter.

2. **Target publish date** — Not stated. Required for front matter (`date`, `publishdate`).

3. **Tags** — Suggested: `[ "Azure", "Logic Apps", "C#", "Integration Testing", "Azure SDK" ]`. Confirm with author.

4. **Summary line** — Not drafted yet; needed for front matter. Suggest: "When integration-testing a Logic Apps Standard workflow you can't hardcode the HTTP trigger callback URL — it contains a time-limited SAS token. In this post I show how to use the Azure ResourceManager SDK for .NET to retrieve a fresh URL at test startup and invoke the workflow from C# integration tests."

5. **Series / standalone** — Research recommends standalone. Confirm with author before publication.

6. **Bicep role-assignment snippet** — Currently out of scope per brief and research. If the author decides to include one, the correct action (`microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action`) is verified; a Bicep snippet can be added to Section 4.

7. **`IntegrationTestHttpClient` depth** — Research recommends a brief mention + repo link only. Confirm with author.

8. **CI/CD auth mechanism** — The pipeline YAML was not fetched. The credential chain implies `azd auth login` in CI, consistent with the azd-templates post. If the actual pipeline uses a different mechanism (e.g. service principal with client secret, federated credentials), the credential chain explanation in Section 3e should be updated.

---

## Research Gaps

1. **Logic Apps Standard Operator (Preview) — exact action list not confirmed.** The securing-a-logic-app documentation lists the role exists but does not enumerate its individual actions. The recommendation to use this role as the minimum is an inference. If a more precise statement is needed, a custom role is the safest recommendation. No additional research action is strictly required unless the author wants a firm confirmation; in that case, the researcher should check the role definition in the Azure portal or via `az role definition list`.

2. **SAS token expiry duration** — The REST API docs do not document how long the SAS token remains valid. The claim "cannot be hardcoded" is correct and well-motivated, but if the author wants to state a concrete expiry period it must be sourced. **Do not invent a duration.** Leave this as an open caveat in the post unless the author can confirm from experience.

3. **Pipeline YAML for `call-apim-with-managed-identity`** — Not fetched. If the author wants a specific reference to how `azd auth login` is invoked in the pipeline, the researcher should fetch `https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/.azdo/pipelines/azure-dev.yml` (or the GitHub Actions equivalent).

---

## Author Notes

- **RBAC action correction**: The brief suspected `Microsoft.Web/sites/workflows/triggers/listCallbackUrl/action`. This action does not exist. The verified correct action is `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action`. Use only the verified one.
- **`WorkflowTriggerResource.CreateResourceIdentifier` parameter names**: The five parameters are `subscriptionId`, `resourceGroupName`, `name`, `workflowName`, `triggerName`. The parameter named `name` is the Logic App **site** name (the App Service resource), not the workflow name — clarify this for readers.
- **`callbackUrl.Value.Value`**: The double `.Value` is intentional — the outer `.Value` unwrites the `Response<WorkflowTriggerCallbackUrl>` wrapper; the inner `.Value` gets the URL string from `WorkflowTriggerCallbackUrl.Value`. Explain this briefly to prevent reader confusion.
- **Preview caveat**: All four Logic Apps Standard built-in RBAC roles are in Preview. Flag this when recommending Logic Apps Standard Operator.
- **`ObjectDisposedException.ThrowIf`**: Introduced in .NET 7; safe on `net10.0` but worth noting if readers ask about older frameworks.
- **No table of contents**: Per author guidance and post size; omit `### Table of Contents`.
- **Official docs links to include on first mention**:
  - `WorkflowTriggerResource`: https://learn.microsoft.com/en-us/dotnet/api/azure.resourcemanager.appservice.workflowtriggerresource?view=azure-dotnet
  - ARM REST API — Logic Apps Standard listCallbackUrl: https://learn.microsoft.com/en-us/rest/api/appservice/workflow-triggers/list-callback-url
  - `AzureDeveloperCliCredential`: https://learn.microsoft.com/en-us/dotnet/api/azure.identity.azuredeveloperclicredential?view=azure-dotnet
  - Logic Apps HTTP trigger (trigger name): https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-http-endpoint
  - Logic Apps Standard RBAC roles: https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app
- **Source repository**: All code references point to `ronaldbosma/call-apim-with-managed-identity`, branch `main`. Verify files are still present before publishing.
- **Version pinning**: Post should state `Azure.ResourceManager.AppService` 1.4.1 and `Azure.Identity` 1.21.0 explicitly, as these are the versions in the sample project.
- **Cross-references** (use internal relative links following existing post link patterns):
  - "Call OAuth-Protected APIs with Managed Identity from Logic Apps": `/blog/2025/09/24/call-oauth-protected-apis-with-managed-identity-from-logic-apps/`
  - "GitHub Actions Workflow for Azure Developer CLI (azd) Templates": `/blog/2026/03/02/github-actions-workflow-for-azd-templates/`

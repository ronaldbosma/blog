# Brief: Logic Apps Standard Workflow Client

## Topic

A C# helper class — `LogicAppWorkflowClient` — that uses the Azure Resource Manager SDK to
programmatically retrieve the callback URL of a Logic Apps Standard HTTP-triggered workflow and
invoke it. Presented in the context of integration testing, where hardcoding the SAS-bearing
callback URL is not desirable.

## Audience

.NET developers writing automated integration tests for Azure-hosted solutions that include Logic
Apps Standard workflows with HTTP triggers. Assumes familiarity with C#, Azure basics, and the
concept of integration testing. No prior knowledge of the Azure SDK for .NET or Logic Apps
internals required.

## Post Type

Short tutorial / code walkthrough — author has noted this will likely be a small post; a table of
contents is probably not needed.

## Candidate Title

- "Calling a Logic Apps Standard Workflow from C# Integration Tests"
- "A C# Client for Triggering Logic Apps Standard Workflows in Integration Tests"
- "Retrieving the Logic Apps Standard Callback URL Programmatically in C#"

[UNCLEAR: author has not stated a preferred title; all three above are candidates]

## Must Include

- Why the callback URL cannot simply be hardcoded (it contains a time-limited SAS token)
- How `WorkflowTriggerResource.GetCallbackUrlAsync()` retrieves the URL via the ARM API
- The `ChainedTokenCredential` pattern (`AzureCliCredential` + `AzureDeveloperCliCredential`) and
  why it supports both local development and CI/CD pipelines
- The `Lazy<Task<HttpClient>>` pattern and what it achieves (deferred, once-only initialisation)
- The `PostAsync<T>` method — JSON serialisation and the empty `requestUri` (callback URL already
  set as `BaseAddress`)
- `IDisposable` implementation
- NuGet package requirements (`Azure.Identity` 1.21.0, `Azure.ResourceManager.AppService` 1.4.1)
- The RBAC permission the pipeline service principal needs to call `GetCallbackUrlAsync()`
  [see Claims to Verify]
- Brief mention of `IntegrationTestHttpClient` (custom `HttpClient` subclass with HTTP message
  logging; defined in the same repo) as the underlying transport

## Sources

### URLs

- Main client class (raw):
  https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/Clients/LogicAppWorkflowClient.cs
- `IntegrationTestHttpClient` (raw):
  https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/Clients/IntegrationTestHttpClient.cs
- `IntegrationTests.csproj` (NuGet packages + target framework):
  https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/IntegrationTests.csproj
- Azure SDK `WorkflowTriggerResource` docs:
  [UNCLEAR: no official docs URL supplied; researcher should locate the
  `Azure.ResourceManager.AppService` reference page on learn.microsoft.com]
- `GetCallbackUrlAsync` ARM REST endpoint:
  [UNCLEAR: no URL supplied; researcher should find the REST API reference for
  `POST .../triggers/{triggerName}/listCallbackUrl`]

### GitHub References

- **Repo**: `ronaldbosma/call-apim-with-managed-identity` (branch `main`)
- **Primary source file**:
  `tests/IntegrationTests/Clients/LogicAppWorkflowClient.cs`
- **Supporting file**:
  `tests/IntegrationTests/Clients/IntegrationTestHttpClient.cs`
- **Project file** (package versions, target framework):
  `tests/IntegrationTests/IntegrationTests.csproj`
- **Usage example**:
  `tests/IntegrationTests/LogicAppTests.cs`
  https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/LogicAppTests.cs

### Other References

- None supplied in `input.md`

## Claims to Verify

1. **Default trigger name** — The default `triggerName` in the constructor is
   `"When_a_HTTP_request_is_received"`. Verify this matches the actual default trigger name used
   by the Logic Apps Standard designer for a new HTTP trigger; it may vary by connector version or
   locale.
2. **ARM SDK package** — `WorkflowTriggerResource.CreateResourceIdentifier` and
   `GetCallbackUrlAsync()` are in `Azure.ResourceManager.AppService` v1.4.1. Verify these types
   still exist in that package and have not moved (e.g. to a dedicated Logic Apps SDK).
3. **Required RBAC role** — The post states the pipeline "has enough permissions to retrieve the
   callback URL" but does not name the role. Verify the minimum Azure RBAC role or action required
   (`Microsoft.Web/sites/workflows/triggers/listCallbackUrl/action` is the suspected action; likely
   covered by `Contributor` or a custom role).
4. **Credential chain behaviour in CI/CD** — The note in the code says `AzureDeveloperCliCredential`
   may need an explicit `TenantId` to avoid picking up the Microsoft Services tenant. Verify this
   is still relevant for `Azure.Identity` v1.21.0 and document the correct workaround.

## Open Questions

1. **Correct usage example file** — Confirmed: `tests/IntegrationTests/LogicAppTests.cs` at
   https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/LogicAppTests.cs
2. **Scope / series membership** — Is this a standalone post or part of the existing
   `oauth-and-api-management` series (which already has a Logic Apps entry)? The topic is
   different (integration testing vs. OAuth), so standalone seems likely, but confirmation is
   needed.
3. **Target publish date** — Not stated.
4. **Should RBAC/Bicep setup be included?** — Author says "explain why it's useful and explain the
   code"; no mention of infrastructure setup. Confirm whether a Bicep snippet for assigning the
   required role is in scope.
5. **`IntegrationTestHttpClient` depth** — Should the post explain this helper class, or simply
   reference it as a dependency? It is a thin wrapper (`HttpClient` subclass with
   `HttpMessageLoggingHandler`).
6. **`AzureDeveloperCliCredential` vs. workload identity in CI/CD** — The code uses azd CLI
   credentials in CI; confirm whether the actual pipeline uses azd or a different auth mechanism
   (e.g. service principal with client secret, federated credentials). This affects how useful the
   credential chain explanation will be for readers.

## Related Existing Posts

- **"Call OAuth-Protected APIs with Managed Identity from Logic Apps"**
  (`/blog/2025/09/24/call-oauth-protected-apis-with-managed-identity-from-logic-apps/`)
  — covers Logic Apps Standard but focuses on calling OAuth-protected APIs from within a workflow,
  not on testing workflows from C# code. Overlap is minimal; that post has a short "Testing the
  Implementation" section worth reviewing to ensure the new post does not duplicate it and can
  cross-reference it.
- **"GitHub Actions Workflow for Azure Developer CLI (azd) Templates"**
  (`/blog/2026/03/02/github-actions-workflow-for-azd-templates/`)
  — describes a CI/CD workflow with a "Verify Deployment" step that runs integration tests against
  a deployed `call-apim-with-managed-identity` template. Thematic overlap on integration testing in
  pipelines; consider a cross-reference.

No existing post specifically covers Logic Apps Standard callback URL retrieval or the
`LogicAppWorkflowClient` pattern.

## Missing Information

- The correct "usage" file / code snippet showing `LogicAppWorkflowClient` being instantiated and
  called in a real or representative test (see Open Questions #1)
- Minimum required Azure RBAC role or permission for `GetCallbackUrlAsync()` (see Claims to
  Verify #3)
- Official Microsoft docs links for `WorkflowTriggerResource` and the underlying ARM REST call
- Whether a `LogicAppTests.cs` file exists or will be created in the repo before publication
- Post metadata: publish date, tags, series (if any), summary line

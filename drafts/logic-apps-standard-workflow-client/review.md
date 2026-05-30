# Review: logic-apps-standard-workflow-client

## Summary

The post is well-written, technically accurate in its core content and closely follows the plan. Two major findings were addressed before publication: an unsupported claim about RBAC minimum role and an imprecise claim about `AzureDeveloperCliCredential` tenant defaulting behaviour. All five required fixes listed below have been applied.

**Ready to Publish: YES** (after fixes applied)

---

## Issues Found and Fixed

### Major — RBAC minimum-role claim overstated
**Location:** `### RBAC: Granting the Pipeline Identity Access`, paragraph 2
**Problem:** Post said "is the minimum built-in role that covers this operation." Research says this is an unconfirmed inference.
**Fix applied:** Changed to "is most likely the minimum built-in role that covers this operation, though its exact action list hasn't been independently verified" and reframed the custom-role recommendation as "guaranteed least-privilege."

### Major — `AzureDeveloperCliCredential` Microsoft Services tenant claim imprecise
**Location:** `### The LogicAppWorkflowClient Class`, **Credential Chain** section
**Problem:** "in a multi-tenant CI/CD environment" was broader than the source supports. The specific scenario is a service principal authenticating via `azd auth login`.
**Fix applied:** Narrowed to "when your pipeline authenticates with a service principal via `azd auth login`, the credential can default to the service principal's home tenant."

### Minor — Missing language tag on RBAC action fenced block
**Fix applied:** Added ` ```text ` language tag.

### Minor — Bold paragraph sub-headings should be `####` headings
**Fix applied:** Converted all seven bold sub-headings inside `### The LogicAppWorkflowClient Class` to `####` headings with title case.

### Minor — `AzureCliCredential` not linked to documentation
**Fix applied:** Added link to `https://learn.microsoft.com/en-us/dotnet/api/azure.identity.azureclicredential?view=azure-dotnet` on first substantive mention.

---

## Verified Claims

| Claim | Status |
|---|---|
| Default trigger name `When_a_HTTP_request_is_received` | ✓ Confirmed |
| `WorkflowTriggerResource.CreateResourceIdentifier` 5-param signature | ✓ Confirmed |
| `callbackUrl.Value.Value` double-unwrap explanation | ✓ Confirmed |
| RBAC action `microsoft.web/sites/hostruntime/webhooks/api/workflows/triggers/listCallbackUrl/action` | ✓ Confirmed |
| Standard workflows under `Microsoft.Web/sites` not `Microsoft.Logic` | ✓ Confirmed |
| Package versions: Azure.ResourceManager.AppService 1.4.1, Azure.Identity 1.21.0 | ✓ Confirmed |
| Target framework `net10.0` | ✓ Confirmed |
| `Lazy<Task<HttpClient>>` pattern | ✓ Confirmed |
| `AzureDeveloperCliCredentialOptions.TenantId` exists in v1.21.0 | ✓ Confirmed |
| All four Logic Apps Standard built-in roles in Preview | ✓ Confirmed |
| Cross-references resolve to existing posts | ✓ Confirmed |

---

## Remaining Open Items (non-blocking)

- `draft` field absent from front matter — consistent with published posts in this repo (field is omitted at publication time). Add `draft: true` if authoring before publish date.
- `ObjectDisposedException.ThrowIf` requires .NET 7+ — not mentioned; informational only given `net10.0` target.
- `AzureCliCredential` also appears in NuGet Packages section (listed by name only); link added in Credential Chain section on first substantive mention.

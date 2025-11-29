---
title: "Generic Error Handling in API Management"
date: 2025-11-29T15:45:00+01:00
publishdate: 2025-11-29T15:45:00+01:00
lastmod: 2025-11-29T15:45:00+01:00
tags: [ "Azure", "API Management", "Azure Integration Services" ]
summary: "Learn how to implement centralized error handling in Azure API Management at the global scope, reducing duplicate logic and ensuring consistent error responses across all APIs while maintaining flexibility for custom scenarios."
draft: true
---

I've been working with Azure API Management for a while now, and I've seen (and built) solutions where every API, or worse, every operation, had its own error handling logic. Most of it was duplicated, and I've also seen a lot of inconsistencies. Some APIs return an error code without a body, while others provide some sort of problem details or follow the default schema that API Management uses for errors. Generic error handling prevents duplicate logic while improving consistency.

This solution isn't useful when API Management is used as a pure proxy where all requests and responses are passthrough. But it's valuable in scenarios where you have custom logic in API Management. For example:

- When clients connect to API Management via OAuth, but the backends API Management connects to have different auth implementations. Some might have basic authentication while others require an API Key or OAuth. When the backend returns a 401 Unauthorized or 403 Forbidden, it means the credentials that API Management is using to connect to the backend are invalid or don't have enough permission. In this case you don't want to return this status code to the client since their credentials were valid. A 500 Internal Server Error would be better.
- If you're doing custom transformations and the backend returns a 400 Bad Request, it doesn't always make sense to return that to the client. It could also be a bug in your transformation code and a 500 Internal Server Error makes more sense.

In this post, I'll show you how to implement generic error handling at the global scope in API Management and how to customize its behavior when needed.

### Table of Contents

- [Prerequisites](#prerequisites)
- [Sample Implementation](#sample-implementation)
- [Understanding API Management Scopes](#understanding-api-management-scopes)
- [Requirements](#requirements)
- [Global Error Handling Policy](#global-error-handling-policy)
- [Scenarios](#scenarios)
  - [Scenario 1: Default Behavior](#scenario-1-default-behavior)
  - [Scenario 2: Bypass Generic Error Handling](#scenario-2-bypass-generic-error-handling)
  - [Scenario 3: Custom Error Handling](#scenario-3-custom-error-handling)
  - [Scenario 4: Override Passthrough Error Codes](#scenario-4-override-passthrough-error-codes)
  - [Testing the Solution](#testing-the-solution)
- [Considerations](#considerations)
- [Conclusion](#conclusion)

### Prerequisites

To follow along with this post, you'll need an Azure API Management service instance. If you don't have one yet, you can use my [Azure Integration Services Quickstart](https://github.com/ronaldbosma/azure-integration-services-quickstart) template to deploy one quickly.

### Sample Implementation

I've created a [sample implementation](https://github.com/ronaldbosma/azure-apim-samples/tree/main/generic-error-handling) that includes:

- A backend API that simulates a backend and returns any HTTP status code (100-599) based on a path parameter
- An Error Handling API with four operations demonstrating different error handling scenarios
- Global error handling policy that provides the core logic

You can deploy this sample to your own API Management instance using Bicep and experiment with the different scenarios.

### Understanding API Management Scopes

Before we dive into the implementation, it's important to understand how [API Management Scopes](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-policies#scopes) work. Policies in API Management can be defined at different levels:

- **Global scope** - Applies to all APIs in the instance
- **Workspace scope** - Applies to all APIs in a workspace (for workspaces feature)
- **Product scope** - Applies to all APIs within a product
- **API scope** - Applies to all operations in an API
- **Operation scope** - Applies to a specific operation

Policies at lower scopes can inherit policies from parent scopes using the `<base />` element. This allows you to define common logic once at a higher scope and selectively override or extend it at lower scopes.

In this solution, we'll provide generic error handling at the global scope and use policies at the operation scope to influence its behavior if necessary.

### Requirements

The generic error handling solution follows these requirements:

1. **Default passthrough codes** - Status codes 404 (Not Found), 409 (Conflict), 413 (Payload Too Large) and 429 (Too Many Requests) are returned as-is, but with the response body cleared to prevent leaking backend error details.

2. **Error transformation** - All other error status codes (400 and above, except the passthrough codes) are converted to 500 Internal Server Error with the response body cleared.

3. **Success codes unchanged** - Success status codes (2xx and 3xx) are passed through without modification.

4. **Custom error handling** - APIs or operations can set the `errorHandled` context variable to `true` to indicate they've handled errors themselves, which skips the global error handling and returns responses as-is.

5. **Customizable passthrough codes** - APIs or operations can override which status codes should pass through by setting the `passthroughErrorStatusCodes` context variable to a comma-separated list of status codes.

### Global Error Handling Policy

Here's the core error handling logic that goes in the `<outbound>` section of the global policy:

```
<choose>
    <!-- 
        If an error occured and it has not been handled yet:
            - if status code should be passed through, then return status code as is
            - else return 500 Internal Server Error
    -->
    <when condition="@(
            context.Response.StatusCode >= 400 && 
            context.Variables.GetValueOrDefault<bool>("errorHandled", false) == false
    )">
        <choose>
            <!-- Set the passthrough error status codes to a default set if not already set-->
            <when condition="@(!context.Variables.ContainsKey("passthroughErrorStatusCodes"))">
                <set-variable name="passthroughErrorStatusCodes" value="404,409,413,429" />
            </when>
        </choose>

        <choose>
            <!-- If the error status code is in the passthrough list, clear the body and return the status code as is -->
            <when condition="@{
                string[] passthroughErrorStatusCodes = ((string)context.Variables["passthroughErrorStatusCodes"]).Split(',');
                return passthroughErrorStatusCodes.Contains(context.Response.StatusCode.ToString());
            }">
                <set-body />
            </when>
            <!-- Otherwise, return a 500 Internal Server Error -->
            <otherwise>
                <set-status code="500" reason="Internal Server Error" />
                <set-body />
            </otherwise>
        </choose>
    </when>
</choose>
```

Here's how this logic works:

1. **Check for errors** - The outer `<when>` condition checks if the response status code is 400 or higher (an error) and the `errorHandled` variable is not set to `true`.

2. **Set default passthrough codes** - If the `passthroughErrorStatusCodes` variable hasn't been set by a lower scope, it defaults to "404,409,413,429".

3. **Check if status code should pass through** - The inner `<when>` condition splits the passthrough codes into an array and checks if the current status code is in the list.

4. **Clear body for passthrough codes** - If the status code is in the passthrough list, only the response body is cleared. The status code remains unchanged.

5. **Convert to 500** - For all other error codes, the status is set to 500 Internal Server Error and the body is cleared.

In this example, we're clearing the response body for all error responses but in a real implementation, you might want to return a structured error response.

### Scenarios

Now let's look at different scenarios that demonstrate how to use the global error handling policy.

#### Scenario 1: Default Behavior

The simplest scenario is when an operation doesn't provide any custom error handling. It just inherits the global policy:

```
<outbound>
    <base />
</outbound>
```

With this configuration:

- Status codes 404, 409, 413 and 429 from the backend are returned as-is
- All other error codes (400, 401, 403, 500, etc.) are converted to 500
- Success codes (200, 201, 204, etc.) pass through unchanged

This provides a consistent error handling baseline across all APIs without requiring any additional configuration.

#### Scenario 2: Bypass Generic Error Handling

Sometimes you need complete control over error responses. You can bypass the global error handling by setting the `errorHandled` variable to `true`:

```
<outbound>
    <set-variable name="errorHandled" value="@(true)" />
    <base />
</outbound>
```

When `errorHandled` is `true`, all status codes (success and error) are returned exactly as the backend sent them. No body clearing, no status code transformation.

This is useful when an API or operation doesn't require any error handling and you want to preserve the backend's responses exactly, or when custom error handling is necessary. Which is demonstrated in the next scenario.

#### Scenario 3: Custom Error Handling

You can also implement custom error handling that works together with the global policy. Here's an example that transforms specific status codes:

```
<outbound>
    <choose>
        <when condition="@(context.Response.StatusCode == 201)">
            <set-status code="418" reason="I'm a teapot" />
        </when>
        <when condition="@(context.Response.StatusCode == 204)">
            <set-status code="418" reason="I'm a teapot" />
            <set-variable name="errorHandled" value="@(true)" />
        </when>
    </choose>
    <base />
</outbound>
```

This demonstrates two different patterns:

**Pattern 1: Transform then apply global logic**
- When the backend returns 201, it's changed to 418 (I'm a teapot)
- Since `errorHandled` is not set, the global policy sees the 418 error code
- The global policy converts it to 500 Internal Server Error
- Result: Client receives 500

**Pattern 2: Transform and bypass global logic**
- When the backend returns 204, it's changed to 418 (I'm a teapot)
- `errorHandled` is set to `true`, so the global policy is bypassed
- Result: Client receives 418 as-is

This pattern is for example useful when the backend returns a success code (like 200 OK) but the response body indicates a failure. You can transform it to an error code and let the global policy handle it consistently.

#### Scenario 4: Override Passthrough Error Codes

Sometimes you might want to change which error codes are passed through unchanged.
You can customize this by setting the `passthroughErrorStatusCodes` variable:

```
<outbound>
    <set-variable name="passthroughErrorStatusCodes" value="401,403,404,503" />
    <base />
</outbound>
```

With this configuration:

- Status codes 401, 403, 404 and 503 are returned as-is
- The default passthrough codes 409, 413 and 429 are now converted to 500 (since they're not in the custom list)
- All other error codes are still converted to 500

This is useful when you have specific error codes that have meaning to your clients and should be returned as-is. For example, you might want to return 401 Unauthorized or 403 Forbidden when the client's credentials are forwarded to the backend and are invalid, but convert other errors to 500.

### Testing the Solution

The sample implementation includes a .NET test solution that validates all scenarios. The tests call the Error Handling API with different status codes and verify the expected behavior. You can run these tests against your own API Management instance to verify the behavior. See the [test section](https://github.com/ronaldbosma/azure-apim-samples/blob/main/generic-error-handling/README.md) in the sample implementation for details.

### Considerations

While this solution provides a robust approach to generic error handling, there are a few things to keep in mind:

**Azure Policy Compliance**

The solution does not comply with the Azure policy [API Management policies should inherit parent scope policies using <base />](https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/%2Fproviders%2FMicrosoft.Authorization%2FpolicyDefinitions%2Fd5448c98-e503-4fdd-bcd2-784960c00d04) that ensures that every API Management policy includes the `<base />` tag at the beginning of each policy section - `<inbound>`, `<outbound>`, `<backend>` and `<on-error>` - to inherit policies from parent scopes.

In some scenarios shown above, we set variables before calling `<base />` in the `<outbound>` section. Omitting `<base />` at the beginning can lead to bypassing shared rules such as logging and other critical controls.

In my post [Validate API Management policies with PSRule](https://ronaldbosma.github.io/blog/2024/09/02/validate-api-management-policies-with-psrule/), I describe how you can validate your API Management policies with PSRule. You could create custom rules that verify that the `<base />` policy in the `<outbound>` section is only preceded by certain policies (like `set-variable`) to make sure important logic on a higher scope isn't bypassed.

**Migrating Existing Environments**

If you're implementing this solution in an existing environment with APIs that already have their own error handling, here's a migration approach:

1. **Add bypass logic** - Wrap the error handling in the global policy in a check so it's only executed if the variable `skipGenericErrorHandling` is not set to `true`:
   ```
   <when condition="@(context.Response.StatusCode >= 400 && 
                      !context.Variables.GetValueOrDefault<bool>("errorHandled", false) &&
                      !context.Variables.GetValueOrDefault<bool>("skipGenericErrorHandling", false))">
   ```

2. **Opt out existing APIs** - Set `skipGenericErrorHandling` to `true` in every existing API to make sure the generic error handling is skipped and current behavior is preserved.

3. **Migrate incrementally** - For each API:
   - Remove the `skipGenericErrorHandling` variable
   - Remove current error handling logic that duplicates the generic behavior
   - Implement custom error handling if needed using the patterns shown above
   - Test thoroughly

4. **Clean up** - Once all APIs are migrated, remove the `skipGenericErrorHandling` logic from the global scope.

This approach allows you to migrate APIs one at a time without disrupting existing functionality.

### Conclusion

Generic error handling in Azure API Management provides a centralized way to handle errors consistently across all your APIs. By implementing the logic at the global scope, you eliminate duplicate code and increase consistency.

The solution is flexible enough to allow customization when needed. You can bypass the global error handling logic entirely, transform specific status codes or customize which codes should pass through. This gives you the best of both worlds: consistent defaults with the ability to handle special cases.

[The sample implementation on GitHub](https://github.com/ronaldbosma/azure-apim-samples/tree/main/generic-error-handling) includes working examples of all scenarios, automated tests and Bicep templates for deployment. You can use it as a starting point for implementing generic error handling in your own API Management instance.

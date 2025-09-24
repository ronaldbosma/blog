---
title: "Call OAuth-Protected APIs with Managed Identity from Logic Apps"
date: 2025-09-20T15:30:00+02:00
publishdate: 2025-09-20T15:30:00+02:00
lastmod: 2025-09-20T15:30:00+02:00
tags: [ "Azure", "API Management", "Azure Integration Services", "Entra ID", "Logic Apps", "Managed Identity", "OAuth" ]
summary: "Configure Azure Logic Apps Standard workflows to call OAuth-protected APIs using managed identity. This post demonstrates how to set up HTTP action authentication settings, handle token caching automatically and test API calls with role-based access control."
draft: true
---

In my [previous post](/blog/2025/09/20/call-oauth-protected-apis-with-managed-identity-from-.net/), I showed how to call an OAuth-protected API from .NET using an Azure Function. In most projects that use Azure Integration Services, I also use Logic Apps Standard workflows. This post shows how to call OAuth-protected APIs with managed identity from Logic Apps Standard workflows.

This post is part of a series about OAuth and API Management:

- [Protect APIs in Azure API Management with OAuth](/blog/2025/09/16/protect-apis-in-azure-api-management-with-oauth/)
- Calling OAuth-Protected APIs with Managed Identity
  - [Part 1: In .NET (Azure Function)](/blog/2025/09/20/call-oauth-protected-apis-with-managed-identity-from-.net/)
  - **Part 2: In Logic Apps (Standard) - _this post_**
  - Part 3: In API Management - *coming soon*
- Calling OAuth-Protected Backends from API Management - *coming later*
  - Part 1: With Credential Manager
  - Part 2: With Client Secret
  - Part 3: With Client Certificate

When calling APIs that are protected with OAuth using Entra ID from Azure Logic Apps, using managed identities should always be your first choice when workflows run on Azure resources within the same Entra ID tenant. This eliminates secret management entirely and provides the highest security with the least operational overhead.

In this post, I'll show you how to implement OAuth authentication from a Logic Apps Standard workflow using the system-assigned managed identity.

### Table of Contents

- [Solution Overview](#solution-overview)
- [Workflow Implementation](#workflow-implementation)
  - [Workflow Structure](#workflow-structure)
  - [Configuring Managed Identity Authentication](#configuring-managed-identity-authentication)
- [Testing the Implementation](#testing-the-implementation)
- [Conclusion](#conclusion)

### Solution Overview

The solution includes the following components:

![Overview](../../../../../images/apim-oauth-series/call-oauth-protected-apis-with-managed-identity-from-logic-apps/diagrams-overview-workflow.png)

- **Azure Logic App (Standard)**: A workflow that calls the protected API using the Logic App's system-assigned managed identity
- **Azure API Management**: Service with OAuth-protected API
- **Entra ID App Registration**: Represents the protected APIs in API Management and defines available app roles
- **Supporting Resources**: Application Insights, Log Analytics workspace and Storage Account

While this example uses an API on API Management, the same approach applies when calling any other API protected with OAuth using Entra ID.

The Entra ID configuration follows the same pattern described in [Protect APIs in Azure API Management with OAuth](/blog/2025/09/16/protect-apis-in-azure-api-management-with-oauth/). The key difference is that we assign the `Sample.Read` and `Sample.Write` app roles to the Logic App's system-assigned managed identity instead of client app registrations.

I've created an Azure Developer CLI (`azd`) template called [Call API Management with Managed Identity](https://github.com/ronaldbosma/call-apim-with-managed-identity) that demonstrates three scenarios: .NET Azure Functions, Logic Apps and API Management calling protected APIs. If you want to deploy and try the solution, check out the [getting started section](https://github.com/ronaldbosma/call-apim-with-managed-identity#getting-started) for the prerequisites and deployment instructions. This post focuses on the Logic Apps implementation.

### Workflow Implementation

Azure Logic Apps Standard provides built-in support for managed identity authentication to APIs through the HTTP action. The implementation is straightforward - you configure the authentication settings directly in the action without writing custom code.

#### Workflow Structure

The workflow that's deployed in the template looks like:

![Workflow Overview](../../../../../images/apim-oauth-series/call-oauth-protected-apis-with-managed-identity-from-logic-apps/call-protected-api-workflow.png)

1. **When an HTTP request is received trigger**: Receives a JSON request specifying the HTTP method to use when calling the protected API. For example:
    ```json
    {
         "httpMethod": "GET"
    }
    ```
2. **HTTP action**: Calls the protected API on API Management with managed identity authentication. The `httpMethod` value in the request specifies the HTTP method that's used when calling the protected API. The HTTP action is wrapped in a scope action so we can return error details if an exception occurs.
3. **Response action**: Returns the API response with the JWT token details or detailed error information. This is for demo purposes, don't return this in a real world scenario.

#### Configuring Managed Identity Authentication

To enable managed identity authentication on the HTTP action, you need to configure the advanced authentication settings. For the official documentation, see [Authenticate access with managed identity](https://learn.microsoft.com/en-us/azure/logic-apps/authenticate-with-managed-identity?tabs=standard#authenticate-access-with-managed-identity).

> Note: The "Call an Azure API Management API" action in Logic Apps does not support configuring additional authentication such as managed identities. You must use the generic HTTP action instead.

Here's how to configure it:

1. **Enable authentication**: Click on the "Advanced parameters" dropdown in the HTTP action parameters tab to reveal additional parameters and select "Authentication":

   ![HTTP Action Advanced Parameters](../../../../../images/apim-oauth-series/call-oauth-protected-apis-with-managed-identity-from-logic-apps/http-action-advanced-parameters.png)

2. **Configure managed identity**: Set the authentication type to "Managed Identity", select the appropriate managed identity and specify the audience:

   ![HTTP Action Authentication Settings](../../../../../images/apim-oauth-series/call-oauth-protected-apis-with-managed-identity-from-logic-apps/http-action-authentication-settings.png)

   The audience must match the Application ID URI of the Entra ID app registration representing the protected API. For example, `api://apim-managedidentity-nwe-i2jdr`.

You can find the complete workflow definition in [workflow.json](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/src/logicApp/Workflows/call-protected-api-workflow/workflow.json). The audience is set through a [parameter](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/src/logicApp/Workflows/parameters.json) so the workflow can be deployed in different environments. It's configured through an environment variable in [logic-app.bicep](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/infra/modules/services/logic-app.bicep).

### Testing the Implementation

After deploying the solution, you can test the OAuth-protected API calls using different HTTP methods. Here's a sequence diagram showing a sample flow:

![Sequence Diagram](../../../../../images/apim-oauth-series/call-oauth-protected-apis-with-managed-identity-from-logic-apps/diagrams-workflow-to-apim.png)

The flow shows how the access token is retrieved during the initial GET request and then cached for subsequent requests. The DELETE request fails because the managed identity is not assigned the required `Sample.Delete` role.

You can test the implementation with the following requests using any HTTP client. For example, you can use the REST Client extension for VS Code. Replace `<your-call-protected-api-workflow-url>` with the actual URL of the `call-protected-api-workflow` workflow:

```
#=============================================================================
# Test requests for the Logic App workflow
#=============================================================================

# Replace <your-call-protected-api-workflow-url> with your actual URL of the 'call-protected-api-workflow' workflow
@callProtectedApiWorkflowUrl = <your-call-protected-api-workflow-url>

# Trigger workflow that will call GET the protected API
POST {{callProtectedApiWorkflowUrl}} HTTP/1.1
Content-Type: application/json

{
    "httpMethod": "GET"
}

###

# Trigger workflow that will call POST the protected API
POST {{callProtectedApiWorkflowUrl}} HTTP/1.1
Content-Type: application/json

{
    "httpMethod": "POST"
}

###

# Trigger workflow that will call DELETE the protected API (should return 401 Unauthorized because managed identity does not have the Sample.Delete permission)
POST {{callProtectedApiWorkflowUrl}} HTTP/1.1
Content-Type: application/json

{
    "httpMethod": "DELETE"
}
```

To get the Logic App workflow URL:
1. Navigate to your Logic App resource in the Azure portal
2. Open the `call-protected-api-workflow` workflow
3. Click on the "When an HTTP request is received" trigger (first step in the workflow)
4. Copy the value of the "HTTP URL" from the trigger details
5. Use this URL to replace `<your-call-protected-api-workflow-url>` in the test file

The expected results are:
- **GET request**: Should succeed (200 OK) - the protected API requires `Sample.Read` role
- **POST request**: Should succeed (200 OK) - the protected API requires `Sample.Write` role  
- **DELETE request**: Should fail (401 Unauthorized) - the protected API requires `Sample.Delete` role which is not assigned to the managed identity

The Logic Apps workflow automatically handles access token caching and renewal. If you execute the GET and POST requests multiple times, you'll notice that the `IssuedAt` value in the response doesn't change initially, showing that the platform caches tokens for improved performance.

### Conclusion

Azure Logic Apps Standard provides a clean and straightforward way to call OAuth-protected APIs using managed identity authentication. The key benefits of this approach include:

- **No secret management**: System-assigned managed identity eliminates the need to store and rotate client secrets
- **Built-in authentication**: The platform handles token acquisition, caching and renewal automatically  
- **Easy configuration**: Authentication is configured through the designer interface without custom code

This approach works with any OAuth-protected API that supports Entra ID authentication, not just API Management. Whether you're calling Microsoft Graph, custom APIs or third-party services that integrate with Entra ID, the same pattern applies.

The next post in this series will cover how to call OAuth-protected APIs from within API Management policies, completing the three main scenarios for Azure Integration Services.


---
title: "Call OAuth-Protected APIs with Managed Identity from .NET"
date: 2025-09-20T14:30:00+02:00
publishdate: 2025-09-20T14:30:00+02:00
lastmod: 2025-09-20T14:30:00+02:00
tags: [ ".NET", "Azure", "API Management", "Azure Functions", "Azure Integration Services", "Entra ID", "Managed Identity", "OAuth" ]
summary: "Learn how to call OAuth-protected APIs from .NET applications using Azure managed identity. This post shows how to implement secure API calls from Azure Functions without managing secrets, using the Azure Identity library and custom HTTP message handlers."
---

I've been working with OAuth-protected APIs in Azure API Management and wanted to show you how to call them securely from .NET applications. In my [previous post](/blog/2025/09/16/protect-apis-in-azure-api-management-with-oauth/), we covered how to protect APIs with OAuth and now it's time to show how to consume them.

This post is part of a series about OAuth and API Management:

- [Protect APIs in Azure API Management with OAuth](/blog/2025/09/16/protect-apis-in-azure-api-management-with-oauth/)
- Calling OAuth-Protected APIs with Managed Identity
  - **Part 1: In .NET (Azure Function) - _this post_**
  - Part 2: In Logic Apps - *coming soon*
  - Part 3: In API Management - *coming soon*
- Calling OAuth-Protected Backends from API Management - *coming later*
  - Part 1: With Credential Manager
  - Part 2: With Client Secret  
  - Part 3: With Client Certificate

When calling APIs that are protected with OAuth using Entra ID, using managed identities should always be your first choice when clients run on Azure resources within the same Entra ID tenant. This eliminates secret management entirely and provides the highest security with the least operational overhead.

In this post, I'll show you how to implement OAuth authentication from a .NET Azure Function using the system-assigned managed identity.

### Table of Contents

- [Solution Overview](#solution-overview)
- [Basic Implementation](#basic-implementation)
- [Refactored Implementation](#refactored-implementation)
  - [Configuration Management](#configuration-management)
  - [Authorization Handler](#authorization-handler)
  - [Azure Function Implementation](#azure-function-implementation)
  - [Service Registration](#service-registration)
- [Testing the Implementation](#testing-the-implementation)
- [Conclusion](#conclusion)

### Solution Overview

The solution includes the following components:

![Overview](../../../../../images/apim-oauth-series/call-oauth-protected-apis-with-managed-identity-from-dotnet/diagrams-overview-function.png)

- **Azure Function App**: A .NET Azure Function that calls the protected API using its system-assigned managed identity
- **Azure API Management**: Service with OAuth-protected API
- **Entra ID App Registration**: Represents the protected APIs in API Management and defines available app roles
- **Supporting Resources**: Application Insights, Log Analytics workspace and Storage Account

While this example uses an API on API Management, the same approach applies when calling any other API protected with OAuth using Entra ID.

The Entra ID configuration follows the same pattern described in [Protect APIs in Azure API Management with OAuth](https://ronaldbosma.github.io/blog/2025/09/16/protect-apis-in-azure-api-management-with-oauth/). The key difference is that we assign the `Sample.Read` and `Sample.Write` app roles to the Function App's system-assigned managed identity instead of client app registrations.

I've created an Azure Developer CLI (`azd`) template called [Call API Management with Managed Identity](https://github.com/ronaldbosma/call-apim-with-managed-identity) that demonstrates three scenarios: .NET Azure Functions, Logic Apps and API Management calling protected APIs. If you want to deploy and try the solution, check out the [getting started section](https://github.com/ronaldbosma/call-apim-with-managed-identity#getting-started) for the prerequisites and deployment instructions. This post focuses on the .NET implementation.

### Basic Implementation

To authenticate with managed identity from .NET, the easiest way is to use the [DefaultAzureCredential](https://learn.microsoft.com/en-us/dotnet/api/azure.identity.defaultazurecredential?view=azure-dotnet) class. This class automatically detects the available authentication method and uses the appropriate credential type, including managed identity when running in Azure. 

> In production, it's better to use something else. See [Usage guidance for DefaultAzureCredential](https://learn.microsoft.com/en-us/dotnet/azure/sdk/authentication/credential-chains?tabs=dac#usage-guidance-for-defaultazurecredential).
>
> If you want to execute the function locally, have a look at [Securing API to API calls in Azure with Entra and API Management](https://rios.engineer/securing-api-to-api-calls-in-azure-with-entra-and-api-management/) from Dan Rios. He explains what to configure in order to use the local users' Azure CLI credentials.

Let's start with a simple implementation that shows the core concepts. Here's an Azure Function that retrieves an access token and performs a GET request on a protected API:

```csharp
using Azure.Core;
using Azure.Identity;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using System.Net.Http.Headers;

namespace FunctionApp;

public class CallProtectedApiFunction
{
    [Function(nameof(CallProtectedApiFunction))]
    public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get")] HttpRequest originalRequest)
    {
        // Retrieve bearer token
        var credentials = new DefaultAzureCredential();
        var tokenResult = await credentials.GetTokenAsync(
            new TokenRequestContext(["<your-application-id-uri>"])
        );

        // Create HTTP client and set Authorization header
        using var httpClient = new HttpClient();
        httpClient.BaseAddress = new Uri("https://<your-api-management-service-name>.azure-api.net");
        httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", tokenResult.Token);

        // Call protected endpoint
        var result = await httpClient.GetAsync("/protected");
        result.EnsureSuccessStatusCode();

        return new OkResult();
    }
}
```

- `<your-application-id-uri>` should be replaced with the Application ID URI of the Entra ID app registration representing the protected API in API Management. For example, `api://apim-managedidentity-nwe-i2jdr`. In this case, the `./default` suffix is not required
- `<your-api-management-service-name>` should be replaced with the name of your API Management service

> Note that the Azure Function allows anonymous access (`AuthorizationLevel.Anonymous`) for the purpose of this demo. In a real-world scenario, use appropriate security measures to protect your function.

This implementation shows the essential steps:

1. **Create credentials**: `DefaultAzureCredential` automatically detects the managed identity when running in Azure
2. **Request token**: Use the Application ID URI as the scope to retrieve an access token
3. **Set authorization header**: Add the Bearer token to the HTTP request in the Authorization header
4. **Call the API**: Send the request to the protected endpoint

While this works, it has some limitations. You're creating a new `HttpClient` for each request and authentication logic is mixed with other logic which has to be repeated in every function that calls a protected API.


### Refactored Implementation

A better approach uses configuration management, dependency injection and custom HTTP message handlers. This separates concerns, makes your code more testable and eliminates hardcoded values.

#### Configuration Management

To make the implementation independent of the environment, we'll use the [Options pattern in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/options?view=aspnetcore-9.0) for configuration management.

First, create a configuration model to specify the API Management URL and the OAuth target resource:

```csharp
using System.ComponentModel.DataAnnotations;

public class ApiManagementOptions
{
    public const string SectionKey = "ApiManagement";

    [Required]
    public string GatewayUrl { get; set; } = string.Empty;

    [Required]
    public string OAuthTargetResource { get; set; } = string.Empty;
}
```

Register the options object in your dependency injection container:

```csharp
services.AddOptionsWithValidateOnStart<ApiManagementOptions>()
        .BindConfiguration(ApiManagementOptions.SectionKey)
        .ValidateDataAnnotations();
```

The configuration values are provided through application settings when deployed to Azure. In the sample azd template, the environment variables `ApiManagement__OAuthTargetResource` and `ApiManagement__GatewayUrl` are automatically configured during deployment. See [function-app.bicep](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/infra/modules/services/function-app.bicep) for the configuration.

#### Authorization Handler

Next, create a `DelegatingHandler` that manages OAuth token retrieval:

```csharp
using Azure.Core;
using Azure.Identity;
using Microsoft.Extensions.Options;
using System.Net.Http.Headers;

internal class AzureCredentialsAuthorizationHandler : DelegatingHandler
{
    private readonly ApiManagementOptions _apimOptions;

    public AzureCredentialsAuthorizationHandler(IOptions<ApiManagementOptions> apimOptions)
    {
        _apimOptions = apimOptions.Value;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, 
        CancellationToken cancellationToken)
    {
        var credentials = new DefaultAzureCredential();
        var tokenResult = await credentials.GetTokenAsync(
            new TokenRequestContext([_apimOptions.OAuthTargetResource]), 
            cancellationToken);

        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenResult.Token);

        return await base.SendAsync(request, cancellationToken);
    }
}
```

This handler automatically:
- Retrieves access tokens using the managed identity
- Adds the Bearer token to outgoing requests
- Benefits from automatic token caching provided by `DefaultAzureCredential`
- Uses configuration instead of hardcoded values

#### Azure Function Implementation

The Function implementation becomes much cleaner by using the [IHttpClientFactory](https://learn.microsoft.com/en-us/dotnet/architecture/microservices/implement-resilient-applications/use-httpclientfactory-to-implement-resilient-http-requests):

```csharp
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;

public class CallProtectedApiFunction
{
    private readonly IHttpClientFactory _httpClientFactory;

    public CallProtectedApiFunction(IHttpClientFactory httpClientFactory)
    {
        _httpClientFactory = httpClientFactory;
    }

    [Function(nameof(CallProtectedApiFunction))]
    public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Anonymous, "get")] HttpRequest originalRequest)
    {
        using var httpClient = _httpClientFactory.CreateClient("apim");
        var result = await httpClient.GetAsync("/protected");
        result.EnsureSuccessStatusCode();

        return new OkResult();
    }
}
```

This simplified implementation shows how the authentication logic is completely removed from the Function. The HTTP client factory provides a pre-configured client called "apim" that automatically handles OAuth tokens through the authorization handler.

> The final implementation of the [CallProtectedApiFunction](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/src/functionApp/FunctionApp/CallProtectedApiFunction.cs) function has additional logic to handle GET, POST and DELETE requests, and returns the used JWT token or detailed error information for demo purposes. You shouldn't do this in production, but it's useful for testing and debugging.

#### Service Registration

The dependency injection setup registers all required services:

```csharp
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

internal static class ServiceCollectionExtensions
{
    public static IServiceCollection RegisterDependencies(
        this IServiceCollection services, 
        IConfigurationManager configuration)
    {
        services.AddApplicationInsightsTelemetryWorkerService()
                .ConfigureFunctionsApplicationInsights();

        services.AddOptionsWithValidateOnStart<ApiManagementOptions>()
                .BindConfiguration(ApiManagementOptions.SectionKey)
                .ValidateDataAnnotations();

        services.AddScoped<AzureCredentialsAuthorizationHandler>();

        services.AddHttpClient("apim", (sp, client) =>
                {
                    var options = sp.GetRequiredService<IOptions<ApiManagementOptions>>().Value;
                    client.BaseAddress = new Uri(options.GatewayUrl);
                })
                .AddHttpMessageHandler<AzureCredentialsAuthorizationHandler>();

        return services;
    }
}
```

This extension method is called from the [Program.cs](https://github.com/ronaldbosma/call-apim-with-managed-identity/blob/main/src/functionApp/FunctionApp/Program.cs) file to configure all services during application startup.

Key configuration points:
- **Options validation**: Configuration is validated at startup using data annotations
- **Scoped handler**: The authorization handler is registered as scoped to align with HTTP client lifetime
- **Named HTTP client**: The "apim" client is pre-configured with the base address
- **Handler registration**: `AddHttpMessageHandler` adds the authorization handler to the HTTP client pipeline

### Testing the Implementation

After deploying the solution (from the azd template), you can test the OAuth-protected API calls using different HTTP methods. Here's a sequence diagram showing a sample flow:

![Sequence Diagram](../../../../../images/apim-oauth-series/call-oauth-protected-apis-with-managed-identity-from-dotnet/diagrams-function-to-apim.png)

The flow shows how the access token is retrieved during the initial GET request and then cached for subsequent requests. The DELETE request fails because the managed identity is not assigned the required `Sample.Delete` role.

You can test the implementation using any HTTP client. For example using the REST Client extension for VS Code. Replace `<your-function-app-name>` with your actual Function App hostname:

```
#=============================================================================
# Test requests for the Azure Function
#=============================================================================

# Replace <your-function-app-name> with your actual Function App hostname
@functionAppHostname = <your-function-app-name>.azurewebsites.net

# Call GET on Azure Function
GET https://{{functionAppHostname}}/api/CallProtectedApiFunction HTTP/1.1

###

# Call POST on Azure Function
POST https://{{functionAppHostname}}/api/CallProtectedApiFunction HTTP/1.1

###

# Call DELETE on Azure Function
DELETE https://{{functionAppHostname}}/api/CallProtectedApiFunction HTTP/1.1

###
```

- **GET and POST requests**: Return 200 OK because the Function's managed identity has `Sample.Read` and `Sample.Write` roles
- **DELETE request**: Returns 401 Unauthorized because the `Sample.Delete` role isn't assigned to the managed identity

If you execute multiple requests quickly, you'll notice that the `IssuedAt` value in the response doesn't change between requests. This demonstrates that `DefaultAzureCredential` automatically caches access tokens, improving performance by avoiding unnecessary token requests to Entra ID.

### Conclusion

Calling OAuth-protected APIs from .NET applications using managed identity provides a secure, maintainable approach that eliminates secret management overhead. Using one of the `TokenCredential` classes provided in the Azure Identity library for .NET makes it super easy to retrieve an access token for a managed identity. Combined with custom HTTP message handlers, this creates a clean solution that separates authentication concerns from business logic.

Key takeaways from this implementation:
- Use the Azure Identity library for managed identity authentication and automatic token caching
- Implement custom `DelegatingHandler` classes to centralize OAuth token management
- Leverage dependency injection and the options pattern for configuration management
- Take advantage of HTTP client factory for proper connection management

In the next posts in this series, we'll explore how to call OAuth-protected APIs from Logic Apps and from other API Management APIs using similar managed identity patterns.

You can find the complete working example in my [call-apim-with-managed-identity](https://github.com/ronaldbosma/call-apim-with-managed-identity) repository, which includes detailed deployment instructions and testing examples for multiple scenarios.

---
title: "Call OAuth-Protected Backends from API Management using Credential Manager"
date: 2025-10-03T11:00:00+02:00
publishdate: 2025-10-03T11:00:00+02:00
lastmod: 2025-10-03T11:00:00+02:00
tags: [ "Azure", "API Management", "Azure Integration Services", "Entra ID", "OAuth" ]
summary: "Learn how to use API Management's Credential Manager to call OAuth-protected backend APIs. This post demonstrates how to configure the Credential Manager using Bicep for secure API-to-API communication."
draft: true
---

In my [previous post](/blog/2025/09/29/call-oauth-protected-apis-with-managed-identity-from-api-management/) I showed how to call an OAuth-protected backend from API Management using its managed identity. While managed identity should be the preferred approach for calling OAuth-protected APIs, you can't always use managed identities.

In this post, I'll show you how to use API Management's Credential Manager to call OAuth-protected backend APIs when managed identity isn't an option. This approach provides Azure-managed token acquisition and caching while handling OAuth flows automatically.

The official documentation [About API credentials and credential manager](https://learn.microsoft.com/en-us/azure/api-management/credentials-overview) focuses on how to configure the Credential Manager from the Azure Portal. In this post I demonstrate how to configure this using Bicep. I'm using Entra ID with the client credentials grant flow in my example, but other IdPs and flows are supported.

### Table of Contents

- [Solution Overview](#solution-overview)
- [Implementation](#implementation)
  - [Credential Manager Configuration](#credential-manager-configuration)
  - [Policy Implementation](#policy-implementation)
- [Testing the Implementation](#testing-the-implementation)
- [Considerations](#considerations)
- [Conclusion](#conclusion)

### Solution Overview

The solution demonstrates API Management calling OAuth-protected backend APIs using the Credential Manager:

![Overview](../../../../../images/apim-oauth-series/call-oauth-protected-backends-from-api-management-using-credential-manager/diagrams-overview-credential-manager.png)

- **Azure API Management** service with two APIs:
  - **Protected Backend API**: A backend API that's protected with OAuth using Entra ID
  - **Unprotected API**: A public API that calls the protected backend using the Credential Manager
- **Entra ID App Registrations**: Separate app registrations for the backend API and the client, with proper role assignments
- **Azure Key Vault**: Stores the client secret securely
- **Supporting Resources**: Application Insights and Log Analytics workspace for monitoring

While this example uses an API on API Management as the protected backend, you can use the same approach to call any API protected with OAuth via Entra ID.

The Entra ID configuration follows the same pattern described in [Protect APIs in Azure API Management with OAuth](/blog/2025/09/16/protect-apis-in-azure-api-management-with-oauth/). The key difference is that we assign the `Sample.Read` and `Sample.Write` app roles to the client app registration instead of API Management's system-assigned managed identity.

I've created an Azure Developer CLI (`azd`) template called [Call API Management backend with OAuth](https://github.com/ronaldbosma/call-apim-backend-with-oauth) that demonstrates three scenarios: Credential Manager, send-request policy with client secret and send-request policy with client certificate. If you want to deploy and try the solution, check out the [getting started section](https://github.com/ronaldbosma/call-apim-backend-with-oauth#getting-started) for the prerequisites and deployment instructions. This post focuses on calling OAuth-protected backends using the Credential Manager.

We're using the BasicV2 tier because the Consumption tier doesn't support caching, which is important for token management.

### Implementation

The Credential Manager provides a managed solution for handling OAuth authentication in API Management. It consists of three major components: the credential provider, a client connection and an access policy. Let's look at how to configure each using Bicep.

#### Credential Manager Configuration

The Credential Manager configuration uses Bicep to create the necessary components. Here's the configuration from [credential-manager.bicep](https://github.com/ronaldbosma/call-apim-backend-with-oauth/blob/main/src/apis/unprotected-api/credential-manager.bicep):

```bicep
// Create a Credential Provider that will be used to retrieve the
// access token for the protected backend.
resource credentialProvider 'Microsoft.ApiManagement/service/authorizationProviders@2024-06-01-preview' = {
  parent: apiManagementService
  name: 'credential-provider'
  properties: {
    displayName: 'Credential Provider'
    identityProvider: 'aad'
    oauth2: {
      grantTypes: {
        clientCredentials: {
          resourceUri: oauthTargetResource
          tenantId: subscription().tenantId
        }
      }
    }
  }

  // Add a connection to the Credential Provider for our client
  resource clientConnection 'authorizations' = {
    name: 'client-connection'
    properties: {
      authorizationType: 'OAuth2'
      oauth2grantType: 'ClientCredentials'
      parameters: {
        clientId: clientId
        clientSecret: clientSecret
      }
    }

    // Give the system-assigned managed identity of API Management
    // permission to use the connection
    resource accessPolicies 'accessPolicies' = {
      name: 'client-connection-access-policy-apim-managed-identity'
      properties: {
        objectId: apiManagementService.identity.principalId
        tenantId: apiManagementService.identity.tenantId
      }
    }
  }
}
```

The configuration creates three components:

1. **Credential Provider**: The main component that defines how to connect to the OAuth provider
   - Uses `identityProvider: 'aad'` which matches 'Azure Active Directory v1' in the portal
   - Configures the client credentials grant flow
   - Sets the `resourceUri` to the Application ID URI of the backend's app registration

2. **Client Connection**: Links the provider to specific credentials
   - Contains the client ID and client secret for authentication
   - Note that the Bicep resource names have 'authorization' in their name because Credential Manager used to be called 'Authorizations'

3. **Access Policy**: Controls which APIs can use the authorization
   - Grants API Management's system-assigned managed identity permission to use the connection
   - When creating the client connection through the portal, this is automatically configured

The template automatically generates a client secret for the client's app registration and stores it in Key Vault. However, we can't reference a secret in Key Vault directly in the configuration. According to the [security considerations](https://learn.microsoft.com/en-us/azure/api-management/credentials-overview#security-considerations), the access token and client secrets are encrypted with envelope encryption and stored in an internal, multitenant storage with AES-128 encryption.

You can find the status of the connection by navigating to API Management in the Azure Portal, choosing Credential manager, opening the credential provider and then choosing connections:

![Client Connection Status](../../../../../images/apim-oauth-series/call-oauth-protected-backends-from-api-management-using-credential-manager/client-connection-status.png)

#### Policy Implementation

The unprotected API uses the Credential Manager to obtain tokens automatically. Here's the policy implementation from [credential-manager.xml](https://github.com/ronaldbosma/call-apim-backend-with-oauth/blob/main/src/apis/unprotected-api/credential-manager.xml):

```xml
<policies>
    <inbound>
        <base />
        
        <!-- 
            Get the access token from the Credential Provider. If this fails, an exception is raised.
        -->
        <get-authorization-context provider-id="credential-provider" authorization-id="client-connection" 
                                  context-variable-name="auth-context" identity-type="managed"
                                  ignore-error="false" />

        <set-header name="Authorization" exists-action="override">
            <value>@("Bearer " + ((Authorization)context.Variables.GetValueOrDefault("auth-context"))?.AccessToken)</value>
        </set-header>
    </inbound>

    <backend>
        <base />
    </backend>

    <outbound>
        <base />
    </outbound>

    <on-error>
        <base />
    </on-error>
</policies>
```

The policy does two main things:

1. **Token Retrieval**: Uses `get-authorization-context` to retrieve an access token from the Credential Manager
   - References the credential provider and client connection by their IDs
   - Uses `identity-type="managed"` to authenticate with API Management's system-assigned managed identity
   - Stores the authorization context in a variable for later use

2. **Authorization Header**: Extracts the access token from the authorization context and adds it to the Authorization header

The Credential Manager handles all the complexity of token acquisition, caching and refresh automatically. The policy implementation is much simpler compared to manual token handling approaches.

### Testing the Implementation

After deploying the solution, you can test the OAuth-protected backend calls. Here's a sequence diagram showing the complete flow:

![Sequence Diagram](../../../../../images/apim-oauth-series/call-oauth-protected-backends-from-api-management-using-credential-manager/diagrams-credential-manager.png)

The flow demonstrates how:
1. API Management receives a request on the unprotected API
2. The `get-authorization-context` policy retrieves an access token from the Credential Manager
3. The Credential Manager obtains the token from Entra ID if not cached
4. The request is forwarded to the protected backend with the token
5. The Credential Manager caches the token for subsequent requests

You can test the implementation using the following request. Replace `<your-api-management-service-name>` with the actual name of your API Management service:

```http
# Operation that will call the protected backend using the Credential Manager
GET https://<your-api-management-service-name>.azure-api.net/unprotected/credential-manager HTTP/1.1
```

The request should succeed with a 200 OK response, showing that the Credential Manager successfully obtained an access token and called the protected backend.

If you execute the request multiple times, you'll notice that the `IssuedAt` value in the response doesn't change initially, showing that the Credential Manager caches tokens for improved performance.

### Considerations

While the Credential Manager provides a convenient managed solution, there are several important considerations to keep in mind:

**Network Architecture Limitations**

The solution that handles token retrieval and renewal does not run inside your Azure API Management instance. According to the [FAQ](https://learn.microsoft.com/en-us/azure/api-management/credentials-overview#frequently-asked-questions-faq):

> "Is this feature supported using API Management running inside a VNet?  
> Yes, as long as outbound connectivity on port 443 is enabled to the AzureConnectors service tag."

The `AzureConnectors` service tag is used to make outbound calls to services like Azure Logic Apps and Power Platform possible.

**IP Whitelisting Challenges**

This network architecture has important implications for IP whitelisting. When the Identity Provider (IdP) you're retrieving the token from has implemented IP whitelisting, they either need to:
- Whitelist the `AzureConnectors` service tag for inbound calls if they're on Azure
- Whitelist [all IPs](https://www.azurespeed.com/Information/AzureIpRanges/AzureConnectors) that make up the `AzureConnectors` service tag

I would advise the latter approach as the service tag list can be updated over time.

I've encountered this issue on several occasions and in the end decided not to use the Credential Manager. Instead, I used a send-request policy inside my API to retrieve a token directly. I'll show how to do this in the next blog post.

**Availability Limitations**

At the time of writing this post, the Credential Manager is not available in the self-hosted gateway and several regions. See [Availability](https://learn.microsoft.com/en-us/azure/api-management/credentials-overview#availability) for the current status.

### Conclusion

API Management's Credential Manager provides a managed solution for calling OAuth-protected backend APIs with automatic token handling. The key benefits include:

- **Azure-managed solution**: The platform handles token acquisition, caching and renewal automatically
- **Simple policy configuration**: Authentication is configured through a single policy element
- **Bicep support**: The entire configuration can be deployed as infrastructure as code

However, the solution has network architecture limitations that can make it unsuitable for environments with strict IP whitelisting requirements. The token management service runs outside your API Management instance and requires connectivity to the AzureConnectors service tag.

When the Credential Manager doesn't meet your requirements due to network constraints or availability limitations, you can implement OAuth token handling directly in your policies using the send-request approach, which I'll demonstrate in upcoming posts.

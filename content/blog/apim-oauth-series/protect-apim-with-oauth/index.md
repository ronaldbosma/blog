---
title: "Protect APIs in Azure API Management with OAuth Using Bicep"
date: 2025-09-12T10:00:00+02:00
publishdate: 2025-09-12T10:00:00+02:00
lastmod: 2025-09-12T10:00:00+02:00
tags: [ "Azure", "API Management", "OAuth", "Bicep", "Entra ID", "Microsoft Graph" ]
summary: "Learn how to protect APIs in Azure API Management using OAuth 2.0 with Microsoft Entra ID, deployed entirely through Bicep including the Entra ID app registrations using the Microsoft Graph Bicep extension."
draft: true
---

I've been working on securing APIs in Azure API Management and wanted to show you how to deploy a complete OAuth-protected setup using Bicep. While Microsoft's documentation covers [how to protect an API in Azure API Management using OAuth 2.0](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-protect-backend-with-aad), it focuses on manual configuration through the Azure portal.

In this post, I'll show you how to deploy everything using Bicep, including the necessary Microsoft Entra ID app registrations. This approach gives you a fully automated, repeatable infrastructure-as-code solution for protecting your APIs with OAuth.

This is the first post in a series about OAuth and API Management where we'll explore different scenarios and implementation patterns.

### Table of Contents

- [Why Protect APIs with OAuth](#why-protect-apis-with-oauth)
- [Solution Overview](#solution-overview)
- [Microsoft Graph Bicep Extension and Entra ID Configuration](#microsoft-graph-bicep-extension-and-entra-id-configuration)
- [API Management Policy Configuration](#api-management-policy-configuration)
- [Testing the Protected API](#testing-the-protected-api)
- [Conclusion](#conclusion)

## Why Protect APIs with OAuth

API Management provides several security mechanisms, but OAuth 2.0 with Microsoft Entra ID offers robust protection for enterprise scenarios. Here's what you get:

- **Token-based authentication**: Clients authenticate with Entra ID and receive access tokens
- **Role-based authorization**: Fine-grained control over API operations based on application roles
- **Centralized identity management**: Integration with your organization's identity provider
- **Token validation**: API Management validates tokens without calling back to Entra ID for each request
- **Managed identity integration**: Azure resources that support managed identities can easily access APIs protected by OAuth 2.0 with Entra ID

The traditional approach requires manual configuration of app registrations in Entra ID, which can be error-prone and difficult to reproduce across environments. Using Bicep with the Microsoft Graph extension solves this by treating identity configuration as infrastructure-as-code.

## Solution Overview

The solution deploys the following architecture:

![Overview](../../../../../images/apim-oauth-series/protect-apim-with-oauth/diagrams-overview.png)

I've created an Azure Developer CLI (`azd`) template to deploy this solution: [Protect API Management with OAuth](https://github.com/ronaldbosma/protect-apim-with-oauth). If you want to use it, check out the [getting started section](https://github.com/ronaldbosma/protect-apim-with-oauth?tab=readme-ov-file#getting-started) for the prerequisites and deployment instructions.

The template creates:
- An API Management service with an OAuth-protected API
- Three Entra ID app registrations using the Microsoft Graph Bicep Extension:
  - One app registration representing the APIs in API Management
  - One client with 'read' and 'write' permissions  
  - One client with no API access (for testing authorization failures)

## Microsoft Graph Bicep Extension and Entra ID Configuration

The key to deploying Entra ID resources with Bicep is the [Microsoft Graph Bicep Extension](https://learn.microsoft.com/en-us/community/content/microsoft-graph-bicep-extension), which has recently been released as GA. This extension allows you to manage Microsoft Graph resources like app registrations directly from Bicep templates.

To enable the extension, you need to add it to your `bicepconfig.json` file:

```json
{
  "extensions": {
    "microsoftGraphV1": "br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:1.0.0"
  }
}
```

This configuration tells Bicep to load the Microsoft Graph extension, making the `Microsoft.Graph` resource types available in your templates.

The solution creates three app registrations with specific purposes.

### API Management App Registration

The `Microsoft.Graph/applications` resource creates an app registration in Entra ID that represents the API Management service and is configured with application roles. The corresponding `Microsoft.Graph/servicePrincipals` resource can be found under 'Enterprise Applications' in Entra ID:

```bicep
extension microsoftGraphV1

var name = 'appreg-oauth-uks-apim-ledm7'
var identifierUri = 'api://apim-oauth-uks-ledm7'

resource apimAppRegistration 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: name
  displayName: name
  identifierUris: [ identifierUri ]

  api: {
    requestedAccessTokenVersion: 2 // Issue OAuth v2.0 access tokens
  }

  appRoles: [
    {
      id: guid(tenantId, name, 'Sample.Read') // Generates a unique deterministic ID
      description: 'Sample read application role'
      displayName: 'Sample.Read'
      value: 'Sample.Read'
      allowedMemberTypes: [ 'Application' ]
      isEnabled: true
    }
    {
      id: guid(tenantId, name, 'Sample.Write')
      description: 'Sample write application role'
      displayName: 'Sample.Write'
      value: 'Sample.Write'
      allowedMemberTypes: [ 'Application' ]
      isEnabled: true
    }
    {
      id: guid(tenantId, name, 'Sample.Delete')
      description: 'Sample delete application role'
      displayName: 'Sample.Delete'
      value: 'Sample.Delete'
      allowedMemberTypes: [ 'Application' ]
      isEnabled: true
    }
  ]
}

resource apimServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: apimAppRegistration.appId
  appRoleAssignmentRequired: true // Clients must have an app role assigned
}
```

Key configuration points:
- The `identifierUris` property sets the Application ID URI (e.g., `api://apim-oauth-uks-ledm7`) and is used as the scope when retrieving an access token
- The `requestedAccessTokenVersion` is set to `2` for OAuth 2.0 tokens
- Three application roles are defined: `Sample.Read`, `Sample.Write`, and `Sample.Delete` for different API operations
- The `guid(tenantId, name, 'Sample.Read')` function generates a unique deterministic ID so the value is the same for every deployment
- The `appRoleAssignmentRequired` property ensures only clients with assigned roles can get tokens

**Naming tip**: Don't use the exact name of your API Management service for the app registration. When you enable the system-assigned managed identity on a resource like API Management, a service principal with the same name is created. Using the same name for the app registration would result in two service principals with the same name, which can cause issues when you're trying to assign permissions.

### Client App Registrations

Client applications are configured to authenticate using the client credentials flow. Here's an example showing both a valid client and an invalid client:

```bicep
// Valid client with permissions
resource validClientAppRegistration 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'appreg-oauth-uks-validclient-ledm7'
  displayName: 'appreg-oauth-uks-validclient-ledm7'
}

resource validClientServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: validClientAppRegistration.appId
}

// Invalid client without permissions
resource invalidClientAppRegistration 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: 'appreg-oauth-uks-invalidclient-ledm7'
  displayName: 'appreg-oauth-uks-invalidclient-ledm7'
}

resource invalidClientServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: invalidClientAppRegistration.appId
}
```

Assigning roles can be done using the `Microsoft.Graph/appRoleAssignedTo` resource. Here's how to assign the `Sample.Read` and `Sample.Write` roles to the valid client:

```bicep
func getAppRoleIdByValue(appRoles array, value string) string =>
  first(filter(appRoles, (role) => role.value == value)).id

resource assignSampleReadToValidClient 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  resourceId: apimServicePrincipal.id
  appRoleId: getAppRoleIdByValue(apimAppRegistration.appRoles, 'Sample.Read')
  principalId: validClientServicePrincipal.id
}

resource assignSampleWriteToValidClient 'Microsoft.Graph/appRoleAssignedTo@v1.0' = {
  resourceId: apimServicePrincipal.id
  appRoleId: getAppRoleIdByValue(apimAppRegistration.appRoles, 'Sample.Write')
  principalId: validClientServicePrincipal.id
}
```

Note that assigning roles immediately after creating client app registrations might fail because the service principal might not be provisioned yet. In the template, I've worked around this by assigning the roles after APIM is deployed because that takes some time. In the future, I'm hoping to use the [waitUntil decorator](https://github.com/Azure/bicep/issues/1013) instead.

In the actual template ([apim-app-registration.bicep](https://github.com/ronaldbosma/protect-apim-with-oauth/blob/main/infra/modules/entra-id/apim-app-registration.bicep) and [assign-app-roles.bicep](https://github.com/ronaldbosma/protect-apim-with-oauth/blob/main/infra/modules/entra-id/assign-app-roles.bicep)), I've optimized the Bicep code by configuring the roles in a variable and using a for loop.

## API Management Policy Configuration

The API is protected using an API Management policy that validates OAuth tokens and enforces role-based access. Here's a simplified example showing the core validation logic:

```xml
<policies>
    <inbound>
        <base />

        <!-- Validate the JWT token -->
        <validate-azure-ad-token tenant-id="{{tenant-id}}">
            <audiences>
                <audience>{{oauth-audience}}</audience>
            </audiences>
            <required-claims>
                <claim name="roles" match="any">
                    <value>Sample.Read</value>
                </claim>
            </required-claims>
        </validate-azure-ad-token>
    </inbound>
</policies>
```

The [validate-azure-ad-token](https://learn.microsoft.com/en-us/azure/api-management/validate-azure-ad-token-policy) policy uses two named values to verify token authenticity: `tenant-id` contains your Entra ID tenant ID to ensure the token was issued by the correct identity provider, and `oauth-audience` contains the 'Application (client) ID' of the API Management app registration to verify the token was retrieved for the expected resource. This combination ensures that only tokens issued by your tenant for the correct API Management app registration are accepted, along with validating that the token contains the required role.

In production scenarios, I usually configure the `validate-azure-ad-token` policy at the global scope to enforce OAuth authentication for all APIs in the API Management instance. This provides consistent security across your entire API surface without having to configure it individually for each API.

You can find the full policy example with role determination based on HTTP methods in the [project repository](https://github.com/ronaldbosma/protect-apim-with-oauth/blob/main/infra/modules/application/protected-api.xml).

As an alternative to the `validate-azure-ad-token` policy, you can use the [validate-jwt](https://learn.microsoft.com/en-us/azure/api-management/validate-jwt-policy) policy, which supports other identity providers that implement OpenID Connect:

```xml
<validate-jwt header-name="Authorization">
    <openid-config url="https://login.microsoftonline.com/{{tenant-id}}/v2.0/.well-known/openid-configuration" />
    <audiences>
        <audience>{{oauth-audience}}</audience>
    </audiences>
    <required-claims>
        <claim name="roles" match="any">
            <value>Sample.Read</value>
        </claim>
    </required-claims>
</validate-jwt>
```

## Testing the Protected API

After deployment, you can test the OAuth-protected API using the OAuth 2.0 client credentials flow. The following sequence diagram shows the authentication and authorization flow:

![Sequence Diagram](../../../../../images/apim-oauth-series/protect-apim-with-oauth/diagrams-sequence-diagram.png)

For a detailed explanation on how to test the API with the VS Code REST Client extension, see the ['Test the protected API' section](https://github.com/ronaldbosma/protect-apim-with-oauth/blob/main/demos/demo.md#test-the-protected-api) in the template's demo guide.

Here are the basic HTTP requests you'll use:

1. **Get an access token** from Entra ID:

```
# Get a token from Entra ID
POST https://login.microsoftonline.com/{{tenantId}}/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

client_id={{clientId}}&client_secret={{clientSecret}}&grant_type=client_credentials&scope={{clientScope}}
```

2. **Call the protected API** with different HTTP methods:

```
# Call GET on Protected API with token
GET https://{{apimHostname}}/protected
Authorization: Bearer {{getToken.response.body.access_token}}

# Call POST on Protected API with token
POST https://{{apimHostname}}/protected
Authorization: Bearer {{getToken.response.body.access_token}}

# Call DELETE on Protected API with token (should fail without Sample.Delete role)
DELETE https://{{apimHostname}}/protected
Authorization: Bearer {{getToken.response.body.access_token}}
```

The API will return a 200 OK response if the token is valid and the client has the required role, or a 401 Unauthorized response if authorization fails.

You can inspect the access token at [jwt.ms](https://jwt.ms/) to see the claims, including the `roles` claim that contains the assigned application roles.

## Conclusion

Deploying OAuth-protected APIs in Azure API Management using Bicep provides several benefits:

- **Infrastructure as code**: Complete environment reproducibility including identity configuration
- **Automated deployment**: Single command deployment of both Azure resources and Entra ID configuration  
- **Role-based security**: Fine-grained access control using application roles
- **Enterprise integration**: Native integration with Microsoft Entra ID

This approach eliminates manual configuration steps and provides a solid foundation for securing APIs in enterprise environments. In upcoming posts in this series, we'll explore additional OAuth scenarios and advanced configuration patterns.

You can find the complete working example in my [protect-apim-with-oauth](https://github.com/ronaldbosma/protect-apim-with-oauth) repository, which includes detailed deployment instructions and testing examples.

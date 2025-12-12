---
title: "Catch-All API in Azure API Management: Forward Any Request"
date: 2025-12-12T14:30:00+01:00
publishdate: 2025-12-12T14:30:00+01:00
lastmod: 2025-12-12T14:30:00+01:00
tags: [ "Azure", "API Management", "Bicep", "Azure Integration Services" ]
summary: "Sometimes you just want to forward any request to a backend from API Management without defining a detailed API contract. In this post I show how to create a simple Catch-All API that supports multiple HTTP methods and matches any path using `/{*path}`."
draft: true
---

I've been working with Azure API Management on projects where most APIs have a clear contract defined via OpenAPI. That works well for consumer clarity and the Developer Portal. But in some scenarios, you simply need to forward requests to a backend regardless of the path or query parameters.

A common case is when API Management sits behind an Application Gateway and only a subset of APIs are internet-facing. Internal APIs might be reachable only from the APIM VNet. In dev and test, I deploy a Catch-All API that routes traffic to those internal APIs so we can easily exercise and validate them.

To follow along with this post, you'll need an Azure API Management service instance. If you don't have one yet, you can use my Azure Integration Services Quickstart template to deploy one quickly: https://github.com/ronaldbosma/azure-integration-services-quickstart.

### Table of Contents

- [Why a Catch-All API](#why-a-catch-all-api)
- [Designing the Operation](#designing-the-operation)
- [Deploy with Bicep](#deploy-with-bicep)
- [Testing](#testing)
- [Downsides and Considerations](#downsides-and-considerations)
- [Conclusion](#conclusion)

### Why a Catch-All API

The goal is straightforward: accept requests for a base path, regardless of nested path segments and query parameters, and forward them to a backend service. Instead of uploading or authoring a rich OpenAPI specification, we define minimal operations that cover the HTTP methods we care about and use a catch-all URL template.

Here's a screenshot of a deployed example in API Management that forwards to an echo backend:

![Catch-All API in APIM](../../../../../images/catch-all-api-in-apim-forward-any-request/catch-all-api.png)

### Designing the Operation

An operation in API Management must specify an HTTP method and a URL template. The method cannot be a wildcard. For each HTTP method you want to support, add a separate operation that uses the template `/{*path}`.

- `/{*path}` captures any number of path segments into a template parameter named `path`
- Query parameters are passed through as-is to the backend
- Logging, tracing and metrics are grouped per operation (per method)

This design gives you flexibility to call any path under the API while keeping per-verb separation for diagnostics.

### Deploy with Bicep

You can deploy a working sample with the Bicep file in my repo: [catch-all-api.bicep](https://github.com/ronaldbosma/azure-apim-samples/blob/main/catch-all-api/catch-all-api.bicep).

At a high level, the Bicep template does the following:

- Creates an API named Catch-All with base path `catch-all`
- Points `serviceUrl` to an echo backend (`https://echo.playground.azure-api.net/api`)
- Defines a list of HTTP methods to support (e.g. GET, POST, PUT, PATCH, DELETE)
- For each method, adds an operation with `method` set explicitly and `urlTemplate` as `/{*path}`
- Declares a required `templateParameters` entry named `path` so the wildcard works

A condensed version of the operations loop looks like this:

```bicep
var httpMethodsToCatch = [
	'GET'
	'POST'
	'PUT'
	'PATCH'
	'DELETE'
]

resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
	name: 'catch-all-api'
	parent: apiManagementService
	properties: {
		displayName: 'Catch-All API'
		path: 'catch-all'
		protocols: ['https']
		serviceUrl: 'https://echo.playground.azure-api.net/api'
		subscriptionRequired: false
		type: 'http'
	}
}

resource operations 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = [for method in httpMethodsToCatch: {
	name: method
	parent: api
	properties: {
		displayName: method
		method: method
		urlTemplate: '/{*path}'
		templateParameters: [
			{
				name: 'path'
				type: 'string'
				required: true
			}
		]
	}
}]
```

See the full template for parameterization and complete resource definitions.

### Testing

You can try the API quickly using requests from the sample repo: [tests.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/catch-all-api/tests.http).

Replace the base URL variable with your APIM hostname and send GET, POST, PUT and DELETE requests to arbitrary paths (e.g. `/resource?param=foo`). The backend echo service will show you the forwarded path, method and payload.

### Downsides and Considerations

- No clear API contract for consumers; the Developer Portal experience is minimal
- Request logging is tied to the per-method operation (GET/POST/etc.), not specific operation IDs
- Backend must gracefully handle arbitrary paths and queries
- Consider global policies carefully; they will apply to all catch-all routes
- Align with your security posture; broad routing can expose unintended behavior if misconfigured

Note: I actually deployed the API with `*` as the http method, using Bicep. The API was created successfully and the operation was displayed in the Azure Portal without an HTTP method. When I viewed the OpenAPI spec, it showed as a GET. However, the operation didn't work at all and I got back a 404 Operation Not Found. Only after explicitly setting the HTTP method to e.g. a `GET` I got a valid response.

### Conclusion

A Catch-All API in Azure API Management is a pragmatic tool for testing and routing scenarios, especially when APIM sits behind App Gateway and internal APIs are private. By defining per-verb operations with the `/{*path}` template and deploying via Bicep, you get simple, repeatable infrastructure that forwards any path to a chosen backend.

For more details, explore:

- API Management APIs and operations: https://learn.microsoft.com/azure/api-management/api-management-apis
- URL templates and operations: https://learn.microsoft.com/azure/api-management/api-management-howto-create-api#operations-and-url-templates
- Bicep reference for APIM `service/apis`: https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis
- Developer Portal overview: https://learn.microsoft.com/azure/api-management/api-management-howto-developer-portal

---
title: "Catch-All API in Azure API Management: Forward Any Request"
date: 2025-12-12T14:30:00+01:00
publishdate: 2025-12-12T14:30:00+01:00
lastmod: 2025-12-12T14:30:00+01:00
tags: [ "Azure", "API Management", "Bicep", "Azure Integration Services" ]
summary: "Sometimes you just want to forward any request to a backend from API Management without defining a detailed API contract. In this post I show how to create a simple Catch-All API that supports multiple HTTP methods and matches any path using `/{*path}`."
draft: true
---

Usually when exposing APIs via Azure API Management, you define a clear contract using OpenAPI specifications. This ensures that consumers know exactly what endpoints are available, what parameters to use and what responses to expect. However, there are scenarios where you might want to forward any request to a backend service without defining a detailed API contract.

For this scenario, you can create what I like to call a 'Catch-All API'. It allows you to accept requests for any path and method, and simply forward them to a specified backend service. 

A scenario where I've used this approach is when API Management was deployed inside a virtual network behind an Application Gateway and only a subset of APIs were exposed to the internet, while others were only reachable from the internal network. To be able to directly test these APIs, we deployed a version of the Catch-All API in our dev and test environments that routes traffic to those internal APIs so we can easily validate them.

In this blog post, I'll walk you through how to set up a Catch-All API in Azure API Management using Bicep for deployment. To follow along with this post, you'll need an Azure API Management service instance. If you don't have one yet, you can use my Azure Integration Services Quickstart template to deploy one quickly: https://github.com/ronaldbosma/azure-integration-services-quickstart.

The goal is straightforward: accept requests for a base path, regardless of nested path segments and query parameters, and forward them to a backend service. Instead of uploading or authoring a rich OpenAPI specification, we define minimal operations that cover the HTTP methods we care about and use a catch-all URL template.

Here's a screenshot of a deployed example in API Management that forwards to an echo backend:

![Catch-All API in APIM](../../../../../images/catch-all-api-in-apim-forward-any-request/catch-all-api.png)

As you can see, it has operations for GET, POST, PUT, PATCH and DELETE methods, all using the same URL template `/{*path}`. This URL template captures any number of path segments into a template parameter named `path`. Query parameters are passed through as-is to the backend.

You can deploy a working sample with the Bicep file in my repo: [catch-all-api.bicep](https://github.com/ronaldbosma/azure-apim-samples/blob/main/catch-all-api/catch-all-api.bicep). A condensed version of the operations loop looks like this:

```bicep
var httpMethodsToCatch string[] = [ 
	'GET'
	'POST'
	'PUT'
	'PATCH'
	'DELETE'
]

resource catchAllApi 'Microsoft.ApiManagement/service/apis@2024-10-01-preview' = {
  name: 'catch-all-api'
  parent: apiManagementService
  properties: {
    displayName: 'Catch-All API'
    path: 'catch-all'
    type: 'http'
    serviceUrl: 'https://echo.playground.azure-api.net/api'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }

  // Add a 'catch-all' operation for each specified method
  resource operations 'operations' = [for method in httpMethodsToCatch: {
    name: method
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
}
```

At a high level, the Bicep template does the following:

- Creates an API named Catch-All with base path `catch-all`
- Points `serviceUrl` to an echo backend (`https://echo.playground.azure-api.net/api`)
- Defines a list of HTTP methods to support (e.g. GET, POST, PUT, PATCH, DELETE)
- For each method, adds an operation with `method` set explicitly and `urlTemplate` as `/{*path}`

> Note: You need to explicitly create an operation for each HTTP method you want to support. A wildcard like `*` doesn't work. I actually deployed the API with `*` as the http method. The API was created successfully and the operation was displayed in the Azure Portal without an HTTP method. When I viewed the OpenAPI spec, it showed as a GET. However, the operation didn't work at all and I got back a 404 Operation Not Found. Only after explicitly setting the HTTP method to e.g. a `GET` I got a valid response.

You can try-out the API using requests from the sample repo: [tests.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/catch-all-api/tests.http). Replace the base URL variable with your APIM hostname and send GET, POST, PUT and DELETE requests to arbitrary paths (e.g. `/resource?param=foo`). The backend echo service will show you the forwarded path, method and payload.

Allthough this API setup is quite flexible, there are some important considerations to keep in mind:
- No clear API contract for consumers; the Developer Portal experience is minimal
- Request logging is tied to the per-method operation (GET/POST/etc.), not specific operation IDs
- Backend must gracefully handle arbitrary paths and queries
- Consider global policies carefully; they will apply to all catch-all routes
- Align with your security posture; broad routing can expose unintended behavior if misconfigured

A Catch-All API in Azure API Management is a pragmatic tool for testing and routing scenarios, especially when APIM sits behind App Gateway and internal APIs are private. By defining per-verb operations with the `/{*path}` template and deploying via Bicep, you get simple, repeatable infrastructure that forwards any path to a chosen backend.
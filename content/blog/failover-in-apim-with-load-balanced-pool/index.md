---
title: "Implement Failover in API Management with a Load-balanced Pool"
date: 2026-03-06T14:00:00+01:00
publishdate: 2026-03-06T14:00:00+01:00
lastmod: 2026-03-06T14:00:00+01:00
tags: [ "Azure", "API Management", "Azure Functions", "Bicep", "Resilience" ]
summary: "In this post, I'll show you how to implement regional failover in Azure API Management using priority-based load-balanced pools, backend circuit breakers and retry policies. The setup sends traffic to the local backend by default and automatically fails over to the secondary backend when the primary backend becomes unavailable."
draft: true
---

I've been working with Azure API Management on integrations where high availability across regions is a requirement. A colleague recently asked if there was a clean failover approach for a setup with API Management in two regions and a Function App backend in each region.

The requirement was simple:

- Requests should go to the Function App in the same region as the API Management instance
- If that Function App is down, traffic should automatically fail over to the Function App in the other region

In this post, I'll show you how to implement that scenario using [load-balanced pools in API Management](https://learn.microsoft.com/en-us/azure/api-management/backends?tabs=portal#load-balanced-pool), [backend circuit breakers](https://learn.microsoft.com/en-us/azure/api-management/backends?tabs=portal#circuit-breaker) and the [retry policy](https://learn.microsoft.com/en-us/azure/api-management/retry-policy).

### Table of Contents

- [Scenario Overview](#scenario-overview)
- [Why Load-balanced Pools Are a Good Fit](#why-load-balanced-pools-are-a-good-fit)
- [Create Backends with Circuit Breakers](#create-backends-with-circuit-breakers)
- [Create a Priority-based Load-balanced Pool](#create-a-priority-based-load-balanced-pool)
- [Configure the API to Use the Pool](#configure-the-api-to-use-the-pool)
- [Add Retry to Trigger Fast Failover](#add-retry-to-trigger-fast-failover)
- [Try It Out](#try-it-out)
- [Conclusion](#conclusion)

### Scenario Overview

The following diagram shows the target architecture:

![APIM failover overview](../../../../../../images/failover-in-apim-with-load-balanced-pool/apim-failover-overview.png)

API Management is deployed in two regions. Each region has its own Function App backend.

When a request arrives at API Management in region A, it should call the Function App in region A. But if that backend is unavailable, API Management should fail over to the backend in region B.

One possible approach is custom policy logic that checks responses and manually calls the secondary backend using `send-request`. That works, but it can add a lot of policy complexity.

Load-balanced pools are a cleaner solution for this scenario.

### Why Load-balanced Pools Are a Good Fit

API Management supports three balancing modes in a load-balanced pool:

- **Round-robin**: Distributes requests evenly across backends
- **Weighted**: Distributes requests based on backend weights
- **Priority-based**: Uses higher-priority backend groups first, then lower-priority groups when higher groups are unavailable

For failover, the priority-based option is exactly what we need.

From the API Management documentation: lower-priority backends are used only when higher-priority backends are considered unavailable because their circuit breaker rules are tripped.

So the core idea is:

- Define two backends (one per region)
- Add circuit breaker rules to each backend
- Put both in a load-balanced pool with regional priority order

### Create Backends with Circuit Breakers

Let's start by creating an API Management backend for a Function App, including a circuit breaker. This uses the [Microsoft.ApiManagement/service/backends](https://learn.microsoft.com/en-us/azure/templates/microsoft.apimanagement/service/backends?pivots=deployment-language-bicep) resource:

```bicep
resource functionAppBackend 'Microsoft.ApiManagement/service/backends@2025-03-01-preview' = {
	parent: apiManagementService
	name: functionAppName
	properties: {
		description: 'The backend for the primary region'
		url: 'https://${functionApp.properties.defaultHostName}'
		protocol: 'http'
		credentials: {
			header: {
				'x-functions-key': [
					listKeys('${functionApp.id}/host/default', functionApp.apiVersion).functionKeys.default
				]
			}
		}
		circuitBreaker: {
			rules: [
				{
					name: 'rule'
					tripDuration: 'PT30S'
					acceptRetryAfter: true
					failureCondition: {
						count: 3
						errorReasons: [
							'BackendConnectionFailure'
						]
						interval: 'PT15S'
						statusCodeRanges: [
							{
								min: 502 // Bad Gateway
								max: 504 // Gateway Timeout
							}
						]
					}
				}
			]
		}
	}
}
```

This backend configuration does the following:

1. Registers the Function App URL as an API Management backend
2. Adds the Function host key in the `x-functions-key` header
3. Configures a circuit breaker to detect backend issues

The circuit breaker rule means that if API Management sees three failures within 15 seconds (either `BackendConnectionFailure` or response codes in the 502-504 range), it opens the circuit for 30 seconds.

While the circuit is open, API Management treats this backend as unavailable for pool routing decisions.

### Create a Priority-based Load-balanced Pool

Next, create a load-balanced pool that references both regional backends:

```bicep
resource loadBalancedPool 'Microsoft.ApiManagement/service/backends@2025-03-01-preview' = {
	name: 'load-balanced-pool'
	parent: apiManagementService
	properties: {
		description: 'Load balancer for multiple regions'
		type: 'Pool'
		pool: {
			services: [
				{
					id: currentRegionBackendId
					priority: 1
				}
				{
					id: otherRegionBackendId
					priority: 2
				}
			]
		}
	}
}
```

This snippet is interesting because it uses the same `service/backends` resource type as a normal backend, but sets `type: 'Pool'`.

In region A:

- Backend for Function App in region A gets priority `1`
- Backend for Function App in region B gets priority `2`

In region B, you reverse that setup.

With that in place, API Management uses the local backend first. If the local backend circuit breaker is open, the next request goes to the next priority group, which is the backend in the other region.

### Configure the API to Use the Pool

You can configure the pool in the `inbound` section with [`set-backend-service`](https://learn.microsoft.com/en-us/azure/api-management/set-backend-service-policy), just like a regular backend:

```xml
<inbound>
		<base />
		<set-backend-service backend-id="load-balanced-pool" />
		<rewrite-uri template="api/ProcessRequestFunction" />
</inbound>
```

This policy does three things:

1. Inherits base policies with `<base />`
2. Routes the operation to the `load-balanced-pool` backend
3. Rewrites the incoming URI to the Function route path

From this point on, backend selection is handled by the pool configuration and circuit breaker state.

### Add Retry to Trigger Fast Failover

A load-balanced pool does not retry within the same client request by itself.

That means if the selected backend returns a `503`, that `503` is returned to the client unless you add retry logic.

Without retry, you would need multiple client calls to trip the circuit breaker. In this case, after three failing calls within 15 seconds, the fourth client call would reach the secondary region.

To make failover happen within one request, add the `retry` policy in the `backend` section:

```xml
<backend>
		<retry condition="@(context.Response.StatusCode >= 500)"
					 count="3" interval="1" first-fast-retry="true">
				<forward-request buffer-request-body="true" />
		</retry>
</backend>
```

Here's how this works:

1. `forward-request` sends the request to the pool backend
2. If the response status code is 500 or higher, API Management retries
3. After repeated failures, the primary backend circuit breaker opens
4. A subsequent retry attempt in the same flow is routed to the secondary backend

Set `buffer-request-body="true"` when retrying `forward-request`. Without request buffering, retries of requests with a body can fail with a content length mismatch. See this [Stack Overflow explanation](https://stackoverflow.com/questions/54648853/retry-request-ends-with-content-length-mismatch) for details.

### Try It Out

I've created a working sample here:

- [failover-with-load-balanced-pool sample](https://github.com/ronaldbosma/azure-apim-samples/tree/main/failover-with-load-balanced-pool)

For prerequisites and deployment instructions, see the sample [README](https://raw.githubusercontent.com/ronaldbosma/azure-apim-samples/refs/heads/main/failover-with-load-balanced-pool/README.md).

These files are useful to inspect:

- [api.bicep](https://github.com/ronaldbosma/azure-apim-samples/blob/main/failover-with-load-balanced-pool/infra/resilient-api/api.bicep): Deploys the API with the load-balanced pool and backend wiring
- [backend.bicep](https://github.com/ronaldbosma/azure-apim-samples/blob/main/failover-with-load-balanced-pool/infra/resilient-api/backend.bicep): Configures per-backend circuit breaker behavior
- [ProcessRequestFunction.cs](https://github.com/ronaldbosma/azure-apim-samples/blob/main/failover-with-load-balanced-pool/src/ProcessRequestFunction.cs): Backend Function that returns status codes based on input
- [tests.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/failover-with-load-balanced-pool/tests.http): Ready-to-run HTTP test requests

Use this request against one API Management instance:

```http
POST https://apim-primary-sdc-orfff.azure-api.net/resilient-api/
Content-Type: application/json

[
		{
				"functionApp": "func-primary-sdc-orfff",
				"respondsWithResultCode": 503
		},
		{
				"functionApp": "func-secondary-nwe-g5bv4",
				"respondsWithResultCode": 200
		}
]
```

This payload tells each Function App how to respond.

In this example:

- Primary Function App returns `503`
- Secondary Function App returns `200`

With retry enabled, API Management will retry, trip the primary backend circuit breaker and then route to the secondary backend.

Example response:

```http
HTTP/1.1 200 OK
Content-Type: application/json
X-Attempt-Count: 4

{
	"functionAppName": "func-secondary-nwe-g5bv4",
	"region": "Norway East"
}
```

`X-Attempt-Count` shows how many backend attempts were made:

- `1` when the local backend succeeds immediately
- `4` when the first backend fails three times, then the fourth attempt is sent to the secondary backend
- `1` for repeated failing requests made within 30 seconds, because the primary circuit is still open and API Management directly selects the secondary backend

The sequence below shows both cases: failover after circuit-breaker trip and direct routing while the circuit remains open.

![APIM failover sequence diagram](../../../../../../images/failover-in-apim-with-load-balanced-pool/apim-failover-sequence-diagram.png)

### Conclusion

Priority-based load-balanced pools are a clean way to implement regional failover in API Management. You can keep policy logic simple while still getting robust failover behavior.

The combination used in this post is:

- Backend circuit breakers to detect unhealthy backends
- Priority-based pools to prefer local region and fail over to secondary region
- Retry policy to make failover happen within a single client request

That setup gives clients a much smoother experience during regional backend failures, while still keeping the configuration easy to reason about.

---
title: "Rate Limiting in Azure API Management"
date: 2026-01-06T12:00:00+01:00
publishdate: 2026-01-06T12:00:00+01:00
lastmod: 2026-01-06T12:00:00+01:00
tags: [ "Azure", "API Management", "Rate Limiting", "Throttling" ]
summary: "Learn how to use Azure API Management's rate-limit and rate-limit-by-key policies to protect backends from overwhelming traffic and fairly distribute capacity among clients. Includes practical examples, monitoring guidance, and key considerations for different scenarios."
draft: true
---

I've been working with Azure API Management on projects where protecting backend services from excessive traffic is critical. Rate limiting helps prevent backends from being overwhelmed while also ensuring fair distribution of capacity among clients.

In this post, I'll show you how the different rate limit policies work in API Management. I won't go into which specific limits to use, because that depends on your situation. Instead, I'll focus on how to configure the `rate-limit` and `rate-limit-by-key` policies, explain their behavior across different scopes and share some tips I've learned along the way.

I've created a [sample on GitHub](https://github.com/ronaldbosma/azure-apim-samples/tree/main/rate-limiting) that demonstrates these policies in action. It includes APIs configured with both policies, policy fragments, product-level limits and a tests.http file to try out different scenarios.

### Table of Contents

- [Rate Limit Per Client](#rate-limit-per-client)
  - [Nested Rate Limits on Products](#nested-rate-limits-on-products)
- [Rate Limit Per Key](#rate-limit-per-key)
- [Response Handling](#response-handling)
- [Monitoring with Kusto](#monitoring-with-kusto)
- [Key Considerations](#key-considerations)
  - [Policy Fragments Share Counters](#policy-fragments-share-counters)
  - [V2 Tier Token Bucket Algorithm](#v2-tier-token-bucket-algorithm)
  - [Dynamic Rate Limiting](#dynamic-rate-limiting)
  - [Alternative and Additional Measures](#alternative-and-additional-measures)
  - [Distributed Architecture Accuracy](#distributed-architecture-accuracy)
- [Sample](#sample)
- [Conclusion](#conclusion)

### Rate Limit Per Client

The [rate-limit](https://learn.microsoft.com/en-us/azure/api-management/rate-limit-policy) policy should be used for limits per client. It tracks the number of calls per subscription within the scope where it's defined.

If you define the policy at the API scope, calls to all operations for the same subscription are counted together. If you define it at the operation scope, only calls to that specific operation are counted for the subscription. The rate limit applies to calls made both with and without a subscription. For example, if you set a limit of 10 calls per minute, 10 calls can be made in a minute even without a subscription key.

Here's a basic example at the API scope:

```
<rate-limit calls="10" renewal-period="30">
```

This limits each subscription to 10 calls every 30 seconds for the API.

When rate limiting is defined on multiple levels (for example, at both the API and operation scope), the first limit to reach 0 will cause an error. This means the most restrictive limit applies.

#### Policy Fragments Share Counters

When I first started using the `rate-limit` policy in policy fragments, I expected the fragment to track limits per scope where it was included. That's not how it works.

When `rate-limit` is used in a policy fragment, the fragment itself becomes the scope. If you use the policy fragment in multiple APIs and/or operations, they all share the same rate limit counter. This is almost certainly not what you want.

For example, if you have a fragment with a 10 calls per minute limit and you include it in three different APIs, all three APIs together share those 10 calls per minute, not 10 calls per API.

#### Scope Constraints

The `rate-limit` policy has some important constraints:

- Policy expressions are not allowed in the `calls` and `renewal-period` attributes
- The policy is not allowed on the global and workspace scopes (see [policy usage documentation](https://learn.microsoft.com/en-us/azure/api-management/rate-limit-policy#usage))
- When defined at the product scope, you can specify nested limits for specific APIs and operations (see next section)

#### Nested Rate Limits on Products

When specifying a rate limit on the product scope, it's possible to specify more restrictive rate limits on specific APIs and operations within that product. This can be useful when certain operations require tighter control.

Here's an example:

```
<rate-limit calls="15" renewal-period="30">
    <api id="my-api" calls="10" renewal-period="30">
        <operation id="operation-1" calls="5" renewal-period="30" />
        <operation id="operation-2" calls="5" renewal-period="30" />
        <operation id="operation-3" calls="5" renewal-period="30" />
    </api>
</rate-limit>
```

A few things to note about this approach:

- You cannot use policy expressions in the `id` attributes
- The API and operation must already exist when applying this policy
- You need to explicitly specify all operations that should have custom limits. If you add a new operation to the API later, you might forget to update the rate limit configuration

The `total-calls-header-name` header (if specified) returns the number of calls from the parent `rate-limit` element. A lower number specified in the `api` or `operation` element is not taken into account. However, the `remaining-calls-header-name` header does give back a correct number of remaining calls for the specific API or operation.

You can use the same nested approach for operations on the API scope:

```
<rate-limit calls="10" renewal-period="30">
    <operation id="operation-1" calls="5" renewal-period="30" />
    <operation id="operation-2" calls="5" renewal-period="30" />
    <operation id="operation-3" calls="5" renewal-period="30" />
</rate-limit>
```

This has the same downside that you need to specify all operations explicitly. To make rate limiting more dynamic, the `rate-limit-by-key` policy can be used, which we'll see in the next section.

### Rate Limit Per Key

The [rate-limit-by-key](https://learn.microsoft.com/en-us/azure/api-management/rate-limit-by-key-policy) policy sets a rate limit for a specific key. This policy tracks limits for a specified key, and if you use it in multiple APIs and/or operations with the same key, they all share the same rate limit counter.

I use this policy to set total limits per API or operation, regardless of the client. It's also useful for creating dynamic rate limiting based on custom identifiers.

#### Setting Limits Per API or Operation

When setting a rate limit on an API, you can use the API ID as the key with a policy expression:

```
<rate-limit-by-key calls="20" renewal-period="30" counter-key="@(context.Api.Id)" />
```

When defining a rate limit for a specific operation, use the combination of API and operation ID as the key:

```
<rate-limit-by-key calls="10" renewal-period="30" counter-key="@($"{context.Api.Id};{context.Operation.Id}")" />
```

The delimiter `;` is safe to use because it's not allowed in API names.

**DON'T** use only the operation ID for the key. Operations with the same ID in different APIs will share the rate limit, which is almost never what you want:

```
<!-- DON'T DO THIS -->
<rate-limit-by-key calls="5" renewal-period="30" counter-key="@(context.Operation.Id)" />
```

#### Dynamic Keys Based on Client Identity

By including the `context.Subscription.Id` in the key, you can define a rate limit per subscription similar to what `rate-limit` does:

```
<rate-limit-by-key calls="15" renewal-period="30" counter-key="@($"{context.Api.Id};{context.Subscription.Id}")" />
```

You can also include other identifiers that identify a client, such as values from a JWT token or custom headers.

#### Global Scope

Unlike the `rate-limit` policy, the `rate-limit-by-key` policy is allowed on the global level, which can be useful for setting cross-cutting rate limits.

#### Additional Attributes

The `rate-limit-by-key` policy has two additional attributes that are not available in the `rate-limit` policy:

- `increment-condition`: A Boolean expression specifying if the request should be counted towards the rate limit (true). Policy expressions are allowed but will postpone evaluation and counter increment actions to end of outbound pipeline
- `increment-count`: The number by which the counter is increased per request. Policy expressions are allowed but will postpone evaluation and counter increment to end of outbound pipeline

These attributes provide more control over how requests are counted. For example, you can use `increment-condition` to only count requests that meet certain criteria, or use `increment-count` to give different weights to different types of requests.

### Response Handling

When a rate limit is hit, API Management returns a `429 Too Many Requests` status code with the following default response body:

```json
{
  "statusCode": 429,
  "message": "Rate limit is exceeded. Try again in 5 seconds."
}
```

By default, no headers are returned for successful requests. Once the rate limit is hit, the `Retry-After` header is returned, which specifies after how many seconds the client can retry.

#### Custom Header Names

Both the `rate-limit` and `rate-limit-by-key` policies support custom header names:

- The `retry-after-header-name` attribute can be used to change the name of the retry header
- The `total-calls-header-name` attribute sets a header to return the total calls allowed. This header is returned on both successful requests and when the rate limit is hit
- The `remaining-calls-header-name` attribute sets a header to return the remaining number of calls. This is only returned on requests where the rate limit is not hit

Here's an example with custom headers:

```
<rate-limit calls="15" renewal-period="30" 
            retry-after-header-name="Retry-After-On-API" 
            remaining-calls-header-name="Remaining-Calls-On-API" 
            total-calls-header-name="Total-Calls-On-API" />
```

### Monitoring with Kusto

To understand how your APIs are being used and whether you need to adjust rate limits, you can query Application Insights data. The following Kusto query retrieves the maximum number of requests logged in a specified time frame per API operation:

```kusto
let timeWindow=90d;
let groupResultsByXTime=1m;
let numberOfTopMaxRequestsToSelect=15;

let requestsPerOperation=requests
| where timestamp >= ago(timeWindow)
| where customDimensions["Service Type"] == "API Management"
| extend api = tostring(customDimensions["API Name"])
| extend operation = tostring(customDimensions["Operation Name"])
| summarize numberOfRequests = count() by bin(timestamp, groupResultsByXTime), api, operation;

requestsPerOperation
| summarize topMaxRequests = array_slice(array_sort_desc(make_list(numberOfRequests)), 0, numberOfTopMaxRequestsToSelect), 
            maxRequest = max(numberOfRequests) by api, operation
| project api, operation, maxRequest, topMaxRequests
| sort by api asc, operation asc
```

This query:
- Groups requests by 1-minute intervals (configurable via `groupResultsByXTime`)
- Calculates the maximum number of requests in any single interval
- Returns a list of the top 15 maximum request counts
- Helps you identify peak usage patterns and set appropriate rate limits

### Key Considerations

#### Policy Fragments Share Counters

As mentioned earlier, when `rate-limit` is used in a policy fragment, the fragment becomes the scope and counters are shared across all APIs and operations that use it. This behavior caught me by surprise because I expected the policy to track limits per scope where the fragment was included.

If you want to use rate limiting in a reusable way across multiple APIs or operations, use the `rate-limit-by-key` policy with a dynamic key based on `context.Api.Id` or a combination of `context.Api.Id` and `context.Operation.Id`.

#### V2 Tier Token Bucket Algorithm

The v2 tiers use a token bucket algorithm for rate limiting, which differs from the sliding window algorithm in classic tiers. 

When you configure the `rate-limit-by-key` policy in the v2 tiers at more than one scope using the same `counter-key` value, ensure that the `renewal-period` and `calls` values are consistent in all instances. Inconsistent values can cause unpredictable behavior.

#### Dynamic Rate Limiting

The `rate-limit-by-key` policy supports policy expressions in the `calls` and `renewal-period` attributes, which allows for dynamic rate limiting. You can use this to adjust limits based on subscription tier, JWT token claims, or other runtime values.

For example:

```
<rate-limit-by-key 
    calls="@(context.Subscription.Name.Contains("premium") ? 100 : 50)" 
    renewal-period="60" 
    counter-key="@(context.Subscription.Id)" />
```

#### Alternative and Additional Measures

In addition to configuring rate limits on APIs and operations, you can use other approaches to protect your backends:

- The [circuit breaker](https://learn.microsoft.com/en-us/azure/api-management/backends?tabs=portal#circuit-breaker) property on an API Management backend prevents overwhelming the backend service when under high load
- The [limit-concurrency](https://learn.microsoft.com/en-us/azure/api-management/limit-concurrency-policy) policy limits the number of concurrent requests
- Application Gateway or similar products with DDoS (Distributed Denial-of-Service) protection
- Response caching to reduce backend load (consider whether caching should occur before or after rate limit checks)

Create an alert that triggers when a 429 status code is returned to detect when rate limits are hit and help you understand if adjustments are needed.

#### Distributed Architecture Accuracy

Because of the distributed nature of API Management's throttling architecture, rate limiting is never completely accurate. The difference between the configured number of allowed requests and the actual number varies depending on request volume and rate, backend latency and other factors.

Keep this in mind when setting rate limits. You might see slightly more requests than configured, especially under high load.

### Sample

I've created a [sample on GitHub](https://github.com/ronaldbosma/azure-apim-samples/tree/main/rate-limiting) that demonstrates the rate limiting policies in action. The sample includes:

- Two 'rate-limit' APIs that use the `rate-limit` policy to limit calls on the API and operation scope
- Two 'rate-limit-by-key' APIs that use the `rate-limit-by-key` policy to limit calls on the API and operation scope
- A 'rate-limit via fragment' API that uses a policy fragment containing the `rate-limit` policy to demonstrate the shared counter behavior
- Two subscriptions with access to all APIs
- A product with access to the 'rate-limit' APIs that uses the `rate-limit` policy to limit calls on the product scope. Two subscriptions are subscribed to this product

See the [readme](https://github.com/ronaldbosma/azure-apim-samples/blob/main/rate-limiting/README.md) for instructions on how to deploy it. A [tests.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/rate-limiting/tests.http) file with test requests is included to try out different scenarios and see how the policies behave under various conditions.

### Conclusion

Azure API Management provides flexible rate limiting options through the `rate-limit` and `rate-limit-by-key` policies. Use `rate-limit` for straightforward per-subscription limits at the API or operation scope. Use `rate-limit-by-key` when you need dynamic keys, global limits, or rate limiting based on custom identifiers.

Rate limiting protects your backend services from being overwhelmed and ensures fair distribution of capacity among clients. Combined with monitoring and alerting, these policies help you maintain a reliable and responsive API platform.

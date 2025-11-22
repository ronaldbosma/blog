---
title: "Sanitizing Response Headers in API Management"
date: 2025-11-22T10:30:00+01:00
publishdate: 2025-11-22T10:30:00+01:00
lastmod: 2025-11-22T10:30:00+01:00
tags: [ "Azure", "API Management", "Azure Integration Services", "Security" ]
summary: "By default, Azure API Management returns all headers from the backend to the client, which may include sensitive information. This post demonstrates three approaches to sanitizing response headers: explicit removal, allowlist-based filtering and blocklist-based filtering."
draft: true
---

I've been working with Azure API Management where the backend services return headers with sensitive information that shouldn't be exposed to clients. By default, API Management forwards all headers from the backend to the client, which can inadvertently leak information about your infrastructure.

The [HTTP Security Response Headers Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html) from OWASP provides excellent guidance on which headers to remove or set to non-informative values. Common examples include `Server`, `X-Powered-By`, `X-AspNet-Version` and `X-AspNetMvc-Version`.

In this post, I'll demonstrate three approaches to sanitizing response headers in API Management: explicit removal, allowlist-based filtering and blocklist-based filtering. I've created a sample implementation that you can find in the [azure-apim-samples/sanitize-response-headers](https://github.com/ronaldbosma/azure-apim-samples/tree/main/sanitize-response-headers) repository.

### Table of Contents

- [Prerequisites](#prerequisites)
- [Solution 1: Explicitly Remove Headers](#solution-1-explicitly-remove-headers)
- [Solution 2: Sanitize Headers Based on Allowlist](#solution-2-sanitize-headers-based-on-allowlist)
- [Solution 3: Sanitize Headers Based on Blocklist](#solution-3-sanitize-headers-based-on-blocklist)
- [Testing the Solutions](#testing-the-solutions)
- [Comparison and Considerations](#comparison-and-considerations)
- [Conclusion](#conclusion)

### Prerequisites

To follow along with this post, you'll need an Azure API Management service instance. If you don't have one yet, you can use my [Azure Integration Services Quickstart](https://github.com/ronaldbosma/azure-integration-services-quickstart) template to deploy one quickly.

The sample implementation includes two components:

- **Backend API** - A simple API that simulates a backend service returning headers. It accepts two query parameters (`numberOfSafeHeadersToReturn` and `numberOfUnsafeHeadersToReturn`) to control how many safe and unsafe headers are returned.
- **Sanitizing API** - An API that applies different sanitization policies to demonstrate the three approaches.

For demonstration purposes, the sample applies the sanitization policies at the operation scope. However, in a real-world scenario, I'd recommend applying these policies at the global scope so they protect all APIs in your API Management instance.

You can test the implementations using the requests in [tests.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/sanitize-response-headers/tests.http).

### Solution 1: Explicitly Remove Headers

The most straightforward approach is to explicitly remove specific headers using the `set-header` policy with `exists-action="delete"`:

```xml
<set-header name="Server" exists-action="delete" />
<set-header name="X-Powered-By" exists-action="delete" />
<set-header name="X-AspNet-Version" exists-action="delete" />
<set-header name="X-AspNetMvc-Version" exists-action="delete" />
<set-header name="Unsafe-Header-1" exists-action="delete" />
<set-header name="Unsafe-Header-2" exists-action="delete" />
<set-header name="Unsafe-Header-3" exists-action="delete" />
```

This approach is clear and easy to understand. Each header you want to remove is explicitly listed.

However, it has some significant drawbacks. Every header must be manually configured, which means high maintenance overhead. You might miss headers in your analysis, and if your backend starts returning new sensitive headers, they'll slip through until you update the policy. Additionally, you can't use wildcards to remove headers matching a pattern. For example, if a system returns multiple headers starting with `X-AspNet-`, you'd need to list each one individually.

Here's what the response looks like before sanitization:

```http
HTTP/1.1 200 OK
Content-Length: 0
Connection: close
Date: Sat, 22 Nov 2025 09:24:17 GMT
Cache-Control: private
Safe-Header-1: Safe-Header-1
Safe-Header-2: Safe-Header-2
Safe-Header-3: Safe-Header-3
Unsafe-Header-1: Unsafe-Header-1
Unsafe-Header-2: Unsafe-Header-2
Unsafe-Header-3: Unsafe-Header-3
Request-Context: appId=cid-v1:34bdc010-6c3a-4508-9b73-672241fea0b2
```

And after applying the explicit removal policy:

```http
HTTP/1.1 200 OK
Content-Length: 0
Connection: close
Date: Sat, 22 Nov 2025 09:24:43 GMT
Cache-Control: private
Safe-Header-1: Safe-Header-1
Safe-Header-2: Safe-Header-2
Safe-Header-3: Safe-Header-3
Request-Context: appId=cid-v1:34bdc010-6c3a-4508-9b73-672241fea0b2
```

As you can see, the three unsafe headers have been removed.

### Solution 2: Sanitize Headers Based on Allowlist

An allowlist approach defines which headers are safe to return and removes everything else. This ensures you have complete control over what the client receives.

The complete implementation can be found in [sanitize-with-allowlist.xml](https://github.com/ronaldbosma/azure-apim-samples/blob/main/sanitize-response-headers/sanitizing-api/sanitize-with-allowlist.xml). Here's how it works:

First, we define the allowlist of safe headers. We can't use arrays or sets as variable types in API Management policies, so we use a comma-separated string:

```xml
<set-variable name="allowedHeaders" value="@{
    var headers = new[] { 
        "cache-control", "connection", "content-disposition", "content-encoding", 
        "content-length", "content-type", "date", "etag", "expires", 
        "last-modified", "request-context", "vary"
    };
    return string.Join(",", headers);
}" />
```

**Warning**: Be careful not to remove the `Content-Length` header from the allowlist. Attempting to delete this header will result in the exception: "Expression value is invalid. Header name is invalid or restricted from modification."

Next, we identify which headers need to be removed by comparing the response headers against our allowlist:

```xml
<set-variable name="headersToRemove" value="@{
    var allowedHeaders = ((string)context.Variables["allowedHeaders"])
        .Split(',')
        .Select(h => h.Trim().ToLower())
        .ToHashSet();
    
    var headersToRemove = context.Response.Headers
        .Where(h => !allowedHeaders.Contains(h.Key.ToLower()) && 
                    !h.Key.StartsWith("Safe-", StringComparison.OrdinalIgnoreCase))
        .Select(h => h.Key);
    
    return string.Join(",", headersToRemove);
}" />
```

This logic also allows headers starting with `Safe-` for demonstration purposes.

Now comes the interesting part. We can't manipulate the `context.Response.Headers` collection directly because it's read-only. We need to use the `set-header` policy to remove each header. To iterate through the headers, we use a `retry` policy as a workaround for looping:

```xml
<set-variable name="headersToRemoveCount" value="@(((string)context.Variables["headersToRemove"]).Split(',', StringSplitOptions.RemoveEmptyEntries).Length)" />
<retry condition="@(((int)context.Variables["headersToRemoveCount"]) > 0)" count="50" interval="0">
    <set-variable name="headerToRemove" value="@(((string)context.Variables["headersToRemove"]).Split(',', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault())" />
    <set-header name="@((string)context.Variables["headerToRemove"])" exists-action="delete" />
    <set-variable name="headersToRemove" value="@{
        var headers = ((string)context.Variables["headersToRemove"])
            .Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Skip(1);
        return string.Join(",", headers);
    }" />
    <set-variable name="headersToRemoveCount" value="@(((int)context.Variables["headersToRemoveCount"]) - 1)" />
</retry>
```

The `retry` policy executes at least once and has a maximum count of 50. This means we can remove up to 51 headers (the initial execution plus 50 retries) with this approach.

To demonstrate this limitation, if you configure the backend to return 52 unsafe headers, you'll see that one header remains:

```http
HTTP/1.1 200 OK
Content-Length: 0
Connection: close
Date: Sat, 22 Nov 2025 09:25:06 GMT
Cache-Control: private
Safe-Header-1: Safe-Header-1
Safe-Header-2: Safe-Header-2
Safe-Header-3: Safe-Header-3
Unsafe-Header-52: Unsafe-Header-52
Request-Context: appId=cid-v1:34bdc010-6c3a-4508-9b73-672241fea0b2
```

The `Unsafe-Header-52` remains because we've hit the retry limit.

This solution is inspired by an answer on [this Microsoft Q&A thread](https://learn.microsoft.com/en-us/answers/questions/1334169/how-to-(dynamically)-remove-all-unwanted-backend-r).

**Tip**: If you have critical headers that must always be removed (like `Server` or `X-Powered-By`), add explicit `set-header` policies before the dynamic removal logic. This ensures they're removed even if you hit the retry limit.

One of the biggest challenges with the allowlist approach is determining which headers to include. I've included common safe headers in the sample, but there are many more used across the internet, and most could be considered safe. Removing headers that clients or intermediaries expect might impact functionality in unforeseen ways. For this reason, using a blocklist might be a better approach.

### Solution 3: Sanitize Headers Based on Blocklist

The blocklist approach reverses the logic. Instead of defining what's allowed, we define what should be removed and let everything else through.

The complete implementation can be found in [sanitize-with-blocklist.xml](https://github.com/ronaldbosma/azure-apim-samples/blob/main/sanitize-response-headers/sanitizing-api/sanitize-with-blocklist.xml). Here's the key part of the policy:

```xml
<set-variable name="headersToRemove" value="@{
    var blockedHeaders = new[] { 
        "Server", "X-Powered-By", "X-AspNet-Version", "X-AspNetMvc-Version" 
    };
    
    var headersToRemove = context.Response.Headers
        .Where(h => blockedHeaders.Contains(h.Key, StringComparer.OrdinalIgnoreCase) ||
                    h.Key.StartsWith("Unsafe-", StringComparison.OrdinalIgnoreCase))
        .Select(h => h.Key);
    
    return string.Join(",", headersToRemove);
}" />
```

This logic identifies headers that match the OWASP recommendations (like `Server` and `X-Powered-By`) and headers starting with `Unsafe-` for demonstration purposes. The removal logic using the `retry` policy is the same as in the allowlist approach.

The blocklist approach is more flexible because you only need to maintain a list of known problematic headers. However, this means an unsafe header you haven't identified yet could slip through and be returned to clients.

If you're concerned about this risk, consider creating automated tests that verify your APIs only return expected headers. If an unexpected header appears, the test fails and you can review whether it should be added to the blocklist or allowed.

### Testing the Solutions

You can test all three solutions using the [tests.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/sanitize-response-headers/tests.http) file in the sample repository. It includes four test scenarios:

1. **Direct Backend Call** - Calls the backend API directly to see all headers it returns
2. **No Sanitization** - Calls through API Management without any sanitization policy
3. **Allowlist Sanitization** - Tests the allowlist-based filtering
4. **Blocklist Sanitization** - Tests the blocklist-based filtering

The test file uses variables to configure the base URL and the number of safe and unsafe headers the backend should return, making it easy to experiment with different scenarios.

### Comparison and Considerations

Each approach has its trade-offs:

**Explicit Removal** is the clearest approach. You can see exactly which headers are being removed. However, it requires the highest maintenance effort. Every new header must be added manually, and you can't use wildcards or patterns.

**Allowlist** gives you guaranteed control over what headers are returned. You know exactly what the client receives. But this comes with the risk of removing headers that clients or intermediaries need, potentially breaking functionality in unexpected ways.

**Blocklist** is the most flexible approach. You maintain a list of known problematic headers and let everything else through. The downside is that new sensitive headers might be exposed until you add them to the blocklist.

What risk you're willing to accept depends on your security requirements and risk tolerance. For most scenarios, I'd recommend the blocklist approach combined with comprehensive testing to catch unexpected headers.

Remember that in production, you'd typically apply these policies at the global scope rather than the operation scope. This ensures consistent header sanitization across all APIs in your API Management instance without having to configure each operation individually.

Also keep in mind the technical limitations: the retry workaround can handle up to 51 headers (initial execution plus 50 retries), and certain headers like `Content-Length` are restricted from modification by the platform.

### Conclusion

Sanitizing response headers is an important security practice that prevents leaking sensitive information about your backend infrastructure. Azure API Management provides the flexibility to implement this in different ways depending on your needs.

For most scenarios, I'd recommend the blocklist approach. It balances security and maintainability well, especially when combined with automated testing to catch any headers you might have missed. The allowlist approach provides stronger guarantees but requires more careful consideration of which headers to include.

You can find the complete sample implementation with all three approaches in the [azure-apim-samples/sanitize-response-headers](https://github.com/ronaldbosma/azure-apim-samples/tree/main/sanitize-response-headers) repository. The sample includes a working backend API, the sanitization policies and test requests you can use to try it out yourself.

Just remember the practical limitations: the retry-based approach can handle up to 51 headers, and be careful not to remove restricted headers like `Content-Length` to avoid runtime errors.

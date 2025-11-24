---
title: "Sanitizing Response Headers in API Management"
date: 2025-11-24T09:30:00+01:00
publishdate: 2025-11-24T09:30:00+01:00
lastmod: 2025-11-24T09:30:00+01:00
tags: [ "Azure", "API Management", "Azure Integration Services", "Security" ]
summary: "By default, Azure API Management returns all headers from the backend to the client, which may include sensitive information. This post demonstrates three approaches to sanitizing response headers: explicit removal, allowlist-based filtering and blocklist-based filtering."
---

What happens when your backend services return headers with sensitive information? By default, API Management forwards all headers from the backend to the client, which can inadvertently leak information about your infrastructure.

In this post, I'll demonstrate three approaches to sanitizing response headers in API Management: explicit removal, allowlist-based filtering and blocklist-based filtering.

### Table of Contents

- [Prerequisites](#prerequisites)
- [Solutions](#solutions)
  - [Solution 1: Explicitly Remove Headers](#solution-1-explicitly-remove-headers)
  - [Solution 2: Sanitize Headers Based on Allowlist](#solution-2-sanitize-headers-based-on-allowlist)
  - [Solution 3: Sanitize Headers Based on Blocklist](#solution-3-sanitize-headers-based-on-blocklist)
- [Testing the Solutions](#testing-the-solutions)
- [Comparison](#comparison)
- [Conclusion](#conclusion)

### Prerequisites

To follow along with this post, you'll need an Azure API Management service instance. If you don't have one yet, you can use my [Azure Integration Services Quickstart](https://github.com/ronaldbosma/azure-integration-services-quickstart) template to deploy one quickly.

I've created a [sample implementation](https://github.com/ronaldbosma/azure-apim-samples/tree/main/sanitize-response-headers) that includes two components:

- **Backend API** - A simple API that simulates a backend service returning headers. It accepts two query parameters (`numberOfSafeHeadersToReturn` and `numberOfUnsafeHeadersToReturn`) to control how many 'safe' and 'unsafe' headers are returned.
- **Sanitizing API** - An API that applies different sanitization policies to demonstrate the three approaches.

For demonstration purposes, the sample applies the sanitization policies at the operation scope. However, in a real-world scenario, I'd recommend applying these policies at the global scope so they protect all APIs in your API Management instance.

You can test the implementations using the requests in [tests.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/sanitize-response-headers/tests.http).

### Solutions

The [HTTP Security Response Headers Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html) from OWASP provides guidance on which headers to remove or set to non-informative values. Common examples include `Server`, `X-Powered-By`, `X-AspNet-Version` and `X-AspNetMvc-Version`.

Let's explore three different approaches to removing these headers from your API responses.

#### Solution 1: Explicitly Remove Headers

The most straightforward approach is to explicitly remove specific headers using the `set-header` policy with `exists-action="delete"`:

```
<set-header name="Server" exists-action="delete" />
<set-header name="X-Powered-By" exists-action="delete" />
<set-header name="X-AspNet-Version" exists-action="delete" />
<set-header name="X-AspNetMvc-Version" exists-action="delete" />
<set-header name="Unsafe-Header-1" exists-action="delete" />
<set-header name="Unsafe-Header-2" exists-action="delete" />
<set-header name="Unsafe-Header-3" exists-action="delete" />
```

This approach is clear and easy to understand. Each header you want to remove is explicitly listed.

Here's what a response looks like without sanitization:

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


This approach has some drawbacks though. Every header must be manually configured, which means high maintenance overhead. You might miss headers in your analysis and if your backend starts returning new sensitive headers, they'll slip through until you update the policy. 

Additionally, you can't use wildcards to remove headers matching a pattern. For example, if a system returns multiple headers starting with `Unsafe-`, you'd need to list each one individually. The following two approaches can dynamically remove headers based on patterns.

#### Solution 2: Sanitize Headers Based on Allowlist

An allowlist approach defines which headers are safe to return and removes everything else. This ensures you have complete control over what the client receives.

The complete implementation can be found in [sanitize-with-allowlist.xml](https://github.com/ronaldbosma/azure-apim-samples/blob/main/sanitize-response-headers/sanitizing-api/sanitize-with-allowlist.xml). Here's how it works:

First, we define the allowlist of safe headers and identify which response headers need to be removed in a single policy expression:

```
<set-variable name="responseHeadersToRemove" value="@{
    HashSet<string> allowlist = new HashSet<string>(StringComparer.InvariantCultureIgnoreCase) {
        "Cache-Control", "Connection", "Content-disposition", "Content-encoding",
        "Content-length", "Content-security-policy", "Content-type", "Date",
        "ETag", "Expires", "Last-Modified", "Link", "Memento-Datetime",
        "Ocp-Apim-Trace-Location", "P3P", "Pragma", "Referrer-Policy",
        "Request-Context", "Retry-After", "Set-Cookie", "Strict-Transport-Security",
        "Transfer-Encoding", "Vary", "WWW-Authenticate", "X-Content-Type-Options",
        "x-ms-request-id"
    };
    
    // Headers that are not in the allowlist and do not start with 'Safe-' should be removed
    var headersToRemove = context.Response.Headers.Keys.Where(key => {
        return !allowlist.Contains(key) && 
               !key.StartsWith("Safe-", StringComparison.InvariantCultureIgnoreCase);
    });

    return string.Join(",", headersToRemove);
}" />
```

The allowlist includes common safe headers like `Cache-Control`, `Content-Type`, `Content-Length` and others, based on the [OWASP HTTP Security Response Headers Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html) and [Microsoft documentation](https://learn.microsoft.com/en-us/azure/azure-app-configuration/rest-api-headers). Headers starting with `Safe-` are also allowed for demonstration purposes. All other headers will be marked for removal.

Note that we're using `string.Join` to store the headers as a comma-separated string. This isn't ideal, but we can't store a `string[]` in a variable. See the [set-variable policy documentation](https://learn.microsoft.com/en-us/azure/api-management/set-variable-policy#allowed-types) for the allowed types.

**Warning**: Be careful not to remove the `Content-Length` header from the allowlist. Attempting to delete this header in API Management will result in the exception: "Expression value is invalid. Header name is invalid or restricted from modification."

Now comes the interesting part. We can't manipulate the `context.Response.Headers` collection directly because it's read-only. We need to use the `set-header` policy to remove each header.

```
<choose>
    <when condition="@(!string.IsNullOrWhiteSpace((string)context.Variables["responseHeadersToRemove"]))">
        <set-variable name="indexOfHeaderToRemove" value="@(0)" />
        <set-variable name="numberOfHeadersToRemove" value="@{
            string responseHeadersToRemove = (string)context.Variables["responseHeadersToRemove"];
            return responseHeadersToRemove.Split(',').Length;
        }" />

        <retry condition="@((int)context.Variables["indexOfHeaderToRemove"] < (int)context.Variables["numberOfHeadersToRemove"])" 
               count="50" interval="0">
            <set-header name="@{
                string[] headersToRemoveArray = ((string)context.Variables["responseHeadersToRemove"]).Split(',');
                int index = (int)context.Variables["indexOfHeaderToRemove"];
                return headersToRemoveArray[index];
            }" exists-action="delete" />

            <set-variable name="indexOfHeaderToRemove" value="@((int)context.Variables["indexOfHeaderToRemove"] + 1)" />
        </retry>
    </when>
</choose>
```

Here's how this logic works:
1. The `choose` policy checks if there are any headers to remove. This prevents exceptions when the list is empty.
1. We initialize a counter starting at 0 to track which header we're removing.
1. We calculate the number of headers to remove by splitting the comma-separated list.
1. We loop through the headers to remove using the `retry` policy:
   - We split the header list, retrieve the header name at the current index and remove it.
   - We increment the counter for the next iteration.

We're using the `retry` policy as a workaround for a while loop, which doesn't exist in API Management policies. The `count="50"` means it can retry up to 50 times (plus the initial execution = 51 total). 50 is the maximum value allowed for the count attribute, see the [retry policy documentation](https://learn.microsoft.com/en-us/azure/api-management/retry-policy). Using the `retry` policy this way is inspired by an answer on [this Microsoft Q&A thread](https://learn.microsoft.com/en-us/answers/questions/1334169/how-to-(dynamically)-remove-all-unwanted-backend-r).

Because we only have 50 retries, this approach can only handle removing up to 51 headers (initial execution plus 50 retries). If there are more headers to remove, the remaining headers will not be deleted. To demonstrate this limitation, if you specify that the backend returns 52 unsafe headers, you'll see that one unsafe header remains:

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

You can work around this limitation by using nested `retry` policies, but this adds complexity and can possibly impact performance. For most scenarios, removing a maximum of 51 headers should probably be sufficient.

**Tip**: If you have critical headers that must always be removed (like `Server` or `X-Powered-By`), add explicit `set-header` policies before the dynamic removal logic. This ensures they're removed even if you hit the retry limit.

One of the biggest challenges with the allowlist approach is determining which headers to allow. I've included some common safe headers in the sample, but there are many more used across the internet, and most could be considered safe. Removing headers that clients or intermediaries expect might impact functionality in unforeseen ways. For this reason, using a blocklist might be a better approach.

#### Solution 3: Sanitize Headers Based on Blocklist

With a blocklist, instead of defining what's allowed, we define what should be removed and let everything else through.

The complete implementation can be found in [sanitize-with-blocklist.xml](https://github.com/ronaldbosma/azure-apim-samples/blob/main/sanitize-response-headers/sanitizing-api/sanitize-with-blocklist.xml). Here's the key part of the policy:

```
<set-variable name="responseHeadersToRemove" value="@{
    HashSet<string> blocklist = new HashSet<string>(StringComparer.InvariantCultureIgnoreCase) {
        "Server", "X-Powered-By",
        "X-AspNet-Version", "X-AspNetMvc-Version"
    };

    // Headers in the blocklist or that start with 'Unsafe-' should be removed
    var headersToRemove = context.Response.Headers.Keys.Where(key => {
        return blocklist.Contains(key) || 
               key.StartsWith("Unsafe-", StringComparison.InvariantCultureIgnoreCase);
    });
    
    return string.Join(",", headersToRemove);
}" />
```

This logic identifies headers that match the OWASP recommendations (like `Server` and `X-Powered-By`) and headers starting with `Unsafe-` for demonstration purposes. The removal logic using the `retry` policy is the same as in the allowlist approach.

The blocklist approach is more flexible because you only need to maintain a list of known problematic headers. However, this means an unsafe header you haven't identified yet could slip through and be returned to clients.

If you're concerned about this risk, consider creating automated tests that verify your APIs only return expected headers. If an unexpected header appears, the test fails and you can review whether it should be added to the blocklist or allowed.

### Testing the Solutions

You can test all three solutions using the [tests.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/sanitize-response-headers/tests.http) file in the sample repository. It includes five test scenarios:

1. **Direct Backend Call** - Calls the backend API directly to see all headers it returns
1. **No Sanitization** - Calls backend through API Management without any sanitization policy
1. **Explicit Removal Sanitization** - Tests the explicit removal approach
1. **Allowlist Sanitization** - Tests the allowlist-based filtering
1. **Blocklist Sanitization** - Tests the blocklist-based filtering

The test file uses variables to configure the base URL and the number of safe and unsafe headers the backend should return, making it easy to experiment with different scenarios.

### Comparison

Each approach has its trade-offs:

**Explicit Removal** is the clearest approach. You can see exactly which headers are being removed. However, it requires the highest maintenance effort. Every new header must be added manually and you can't use wildcards or patterns.

**Allowlist** gives you guaranteed control over what headers are returned. You know exactly what the client receives. But this comes with the risk of removing headers that clients or intermediaries need, potentially breaking functionality in unexpected ways.

**Blocklist** is the most flexible approach. You maintain a list of known problematic headers and let everything else through. The downside is that new sensitive headers might be exposed until you add them to the blocklist.

What risk you're willing to accept depends on your security requirements and risk tolerance. For most scenarios, I'd recommend the blocklist approach combined with comprehensive testing to catch unexpected headers.

### Conclusion

Sanitizing response headers is an important security practice that prevents leaking sensitive information about your backend infrastructure. Azure API Management provides the flexibility to implement this in different ways depending on your needs.

For most scenarios, I'd recommend the blocklist approach. It balances security and maintainability well, especially when combined with automated testing to catch any headers you might have missed. The allowlist approach provides stronger guarantees but requires more careful consideration of which headers to include.

As mentioned earlier, the sample applies policies at the operation scope to demonstrate the different approaches. In production I'd recommend applying your sanitization logic at the global (API-wide) outbound scope so every API and operation is covered automatically and you avoid gaps when new operations are added.

You can find the complete sample implementation with all three approaches [here](https://github.com/ronaldbosma/azure-apim-samples/tree/main/sanitize-response-headers). The sample includes a working backend API, the sanitization policies and test requests you can use to try it out yourself.

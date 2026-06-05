---
title: "Validate client certificates in API Management when it's behind an Application Gateway"
date: 2024-02-19T19:00:00+01:00
publishdate: 2024-02-19T19:00:00+01:00
lastmod: 2026-06-05T12:00:00+02:00
tags: [ "Azure", "API Management", "Application Gateway", "Azure Integration Services", "Bicep", "Client Certificates", "Infra as Code", "mTLS", "Security" ]
series: [ "client-certificates-and-mtls-in-api-management" ]
summary: "It's not uncommon for Azure API Management to be deployed in a Virtual Network, only allowing external access via for example an Application Gateway. In this second post on working with client certificates in API Management, we'll explore how to enable mTLS on an Azure Application Gateway and forward requests with client certificates to API Management for further validation. This approach can also be used with other types of backends, such as an ASP.NET Web API."
---

This post is the second in a series on working with client certificates in Azure API Management. Throughout the series, I'll cover both the validation of client certificates in API Management and how to connect to backends with mTLS (mutual TLS) using client certificates.

While Azure's official documentation provides excellent guidance on setting up client certificates via the Azure Portal, this series takes it a step further. We'll dive into using Bicep to automate the process.

Topics covered in this series:

1. [Validate client certificates in API Management](/blog/2024/02/02/validate-client-certificates-in-api-management/)
1. Validate client certificates in API Management when it's behind an Application Gateway _**(current)**_
1. [Securing backend connections with mTLS in API Management](/blog/2024/05/24/securing-backend-connections-with-mtls-in-api-management/)

In this second post, we expand on the solution introduced in [the previous post](/blog/2024/02/02/validate-client-certificates-in-api-management/), but this time an Application Gateway is positioned in front of API Management instead of calling it directly. Using an Application Gateway (or similar resource) this ways is a common approach because it can provide load balancing capabilities and enhanced control over inbound and outbound traffic. Additionally, the Web Application Firewall (WAF) provides improved security by protecting against common web-based attacks and vulnerabilities, such as SQL injection and cross-site scripting (XSS).

### Table of Contents

- [Solution Overview](#solution-overview)
- [Add HTTPS listener to Application Gateway](#add-https-listener-to-application-gateway)
- [Add mTLS listener to Application Gateway](#add-mtls-listener-to-application-gateway)
- [Forward client certificate to API Management](#forward-client-certificate-to-api-management)
- [Validate client certificate in API Management](#validate-client-certificate-in-api-management)
- [Plugging the security hole](#plugging-the-security-hole)
- [Conclusion](#conclusion)

### Solution Overview

I've created an Azure Developer CLI (`azd`) template called [mTLS with Azure API Management and Application Gateway](https://github.com/ronaldbosma/mtls-with-apim-and-agw) that demonstrates three scenarios: validate client certificates when calling API Management directly, when API Management is behind an Application Gateway and how to secure connections from API Management to backend systems using mTLS. See the following diagram for an overview of the solution.

![Solution Overview](../../../../../images/apim-client-certificate-series/solution-overview.png)

> Note that API Management is deployed in External mode in this template to support scenario 1 where direct access from the internet is necessary. When fronting API Management by an Application Gateway, you would normally deploy it inside the Virtual Network in internal mode.

This blog post focusses on scenario 2: validating client certificates when API Management is behind an Application Gateway. In this scenario, a client calls API Management via an Application Gateway using mTLS. The Application Gateway terminates the mTLS session, validates the client certificate and forwards the client certificate to API Management in a request header. API Management then validates the forwarded certificate.

![Flow](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/flow.png)

The template includes self-signed certificates, but you can also use client certificates from a public CA.
Using [Generate and export certificates for point-to-site using PowerShell](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-certificates-point-to-site) as a guide, I've created the following tree of certificates.

![Self-signed certificates](../../../../../images/apim-client-certificate-series/self-signed-certificates.png)

- **APIM Sample Root CA**: is the root CA for this sample
  - **APIM Sample DEV Intermediate CA**: is intermediate CA for a 'dev' environment
    - **Valid Client**: is registered in API Management as a valid client
    - **Unregistered Client**: is NOT registered in API Management and should be blocked when explicitly checking client certificates
    - **Unprotected API**: is used when the Unprotected API calls the Protected API using mTLS _(used in [Securing backend connections with mTLS in API Management](/blog/2024/05/24/securing-backend-connections-with-mtls-in-api-management/))_
    - **Expired Client**: is an expired certificate for testing purposes
    - **Not Yet Valid Client**: is a certificate that is valid in the future and used for testing purposes
  - **APIM Sample TST Intermediate CA**: is intermediate CA for a 'test' environment
    - **Untrusted Client**: can be used to test what happens when certificates from an untrusted intermediate CA are used

You can find more details about the certificates [here](https://github.com/ronaldbosma/mtls-with-apim-and-agw/blob/main/self-signed-certificates/README.md).

If you want to deploy and try the solution, check out the [getting started section](https://github.com/ronaldbosma/mtls-with-apim-and-agw#getting-started) for the prerequisites and deployment instructions. When selecting the API Management SKU, keep the following in mind:
- Use a v2 tier like BasicV2 if you want a quick deployment and don't need to validate the certificate chain of client certificates.
- Use a non-v2 tier like Developer if you need certificate chain validation. The deployment will take longer though.

To try out the implementation, follow the instructions in [this demo](https://github.com/ronaldbosma/mtls-with-apim-and-agw/blob/main/demos/demo-scenario2.md).


---
title: "Securing backend connections with mTLS in API Management"
date: 2024-05-19T00:00:00+01:00
publishdate: 2024-05-19T00:00:00+01:00
lastmod: 2024-05-19T00:00:00+01:00
tags: [ "Azure", "API Management", "Bicep", "Client Certificates", "Infra as Code", "mTLS", "Security" ]
draft: true
---

This is the third post in a series on working with client certificates in Azure API Management. Throughout the series, I’ll cover both the validation of client certificates in API Management and how to connect to backends with mTLS (mutual TLS) using client certificates.

While Azure’s official documentation provides excellent guidance on setting up client certificates via the Azure Portal, this series takes it a step further. We’ll dive into utilizing Bicep and other essential tools, like the Azure CLI, to automate the entire deployment process.

Topics covered in this series:

1. [Validate client certificates in API Management](/blog/2024/02/02/validate-client-certificates-in-api-management/)
1. [Validate client certificates in API Management when its behind an Application Gateway](/blog/2024/02/19/validate-client-certificates-in-api-management-when-its-behind-an-application-gateway/)
1. Securing backend connections with mTLS in API Management _**(current)**_
1. Deploying certificates into Key Vault _(coming soon)_

### Intro

In the previous posts, we covered how to validate client certificates in Azure API Management. In this post, we’ll focus on securing backend connections with mTLS in API Management. We'll deploy two API Management instances. The first will serve as the backend and will require a client certificate for authentication. The second will act as the client and will connect to the backend using mTLS. The client certificate will be stored in Key Vault.

This post provides a step by step guide. If you're interested in the end result, you can find it [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/03-securing-backend-connections-with-mtls-in-apim). If you want to know how to configure all of this through the Azure Portal, have a look at [Secure backend services using client certificate authentication in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-mutual-certificates).

### Prerequisites

The first section will cover the prerequisites for this post. You'll need:
1. A backend that requires mTLS for authentication. We'll use a Consumption tier API Management instance. The `enableClientCertificate` property needs to be set to `true` in order for mTLS to be enabled.
1. Another Consumption tier API Management instance that will act as the client and connect to the backend using a client certificate.
1. A Key Vault to store the client certificate. The API Management client instance needs access to the Key Vault using the 'Key Vaults Secrets' role.
1. Access to the Key Vault yourself to create a certificate in the Key Vault. The 'Key Vault Administrator' role will suffice.

You can create these resources manually, but I've created a Bicep template that will deploy all of them. You can find the Bicep template [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/03-securing-backend-connections-with-mtls-in-apim/prerequisites/prerequisites.bicep).

You can use the accompanying [deploy-prerequisites.ps1](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/03-securing-backend-connections-with-mtls-in-apim/prerequisites/deploy-prerequisites.ps1) PowerShell script to deploy the prerequisites. It uses the Azure CLI to:

1. Create the resource group if it doesn't exist.
1. Get your user id to grant you access to Key Vault. It uses the `az ad signed-in-user show` command. _(If this fails, use the `KeyVaultAdministratorId` parameter to specify your id manually.)_
1. Deploy the Bicep template.

Here's an example of how to run the script:

```powershell
./deploy-prerequisites.ps1 `
    -ResourceGroupName "<your-resource-group>" `
    -ApiManagementServiceClientName "<your-apim-client-instance>" `
    -ApiManagementServiceBackendName "<your-apim-backend-instance>" `
    -KeyVaultName "<your-key-vault>"
```

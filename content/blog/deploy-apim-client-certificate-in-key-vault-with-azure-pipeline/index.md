---
title: "Deploy API Management Client Certificate in Key Vault with Azure Pipeline"
date: 2023-07-08T00:00:00+02:00
publishdate: 2023-07-08T00:00:00+02:00
lastmod: 2023-07-08T00:00:00+02:00
tags: [ "Azure", "Azure CLI", "Azure DevOps", "Azure Pipeline", "API Management", "Bicep", "Continuous Integration", "Infra as Code", "Key Vault" ]
---

Azure API Management is a powerful service that enables you to expose, secure, and manage APIs. In some scenarios, you may need to connect to a backend system that is secured with mutual Transport Layer Security (mTLS). This blog post will guide you through the process of creating an Azure Pipeline that imports a client certificate into Azure Key Vault and use it with Azure API Management.

On [Secure backend services using client certificate authentication in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-mutual-certificates) Microsoft already gives a good explanation on how to configure mTLS in Azure API Management. In this blog post, we'll focus on how to automate the process using an Azure Pipeline.

### Prerequisites

For this solution to work, you'll need an Azure API Management instance and a Key Vault. The can give the API Management instance access to the Key Vault by enable RBAC Authorization and assigning the API Management identity the 'Key Vault Secrets User' role. See [Secure backend services using client certificate authentication in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-mutual-certificates) for a detailed explanation.

I've created a Bicep script that creates the required resources and a PowerShell script to run it. You can find them [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/deploy-apim-client-certificate-in-key-vault-with-azure-pipeline/prerequisites/README.md).

### Azure Pipeline

#### Import Client Certificate

The first step is to import the client certificate into Key Vault. Since I use Bicep to create most of my Azure resources, I wanted to import the client certificate using Bicep. Unfortunately, Bicep only supports adding secrets and keys, not certificates. We can however use the Azure CLI or PowerShell as described on [Tutorial: Import a certificate in Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/certificates/tutorial-import-certificate?tabs=azure-cli).

Here's and example of how to import a certificate using the Azure CLI:

```powershell
az keyvault certificate import `
    --file '<certificate-file>' `
    --name '<certificate-name>' `
    --vault-name '<key-vault-name>'  `
    --password '<certificate-password>'
```


---
title: "Validate client certificates in Azure API Management"
date: 2023-10-27T00:00:00+02:00
publishdate: 2023-10-27T00:00:00+02:00
lastmod: 2023-10-27T00:00:00+02:00
tags: [ "Azure", "API Management", "Bicep", "Client Certificates", "Infra as Code", "Security" ]
draft: true
---

This blog post is the start of a series on how to work with client certificates in Azure API Management. In the series, I'll cover both the validation of client certificates in API Management and how to connect to backends using client certificates. 

While Azure's official documentation provides excellent guidance on setting up client certificates via the Azure Portal, this series takes it a step further. We'll dive into utilizing Bicep for Infrastructure as Code (IaC) and other essential tools to automate the entire deployment process.

Topics covered in this series:

- Validate client certificates in Azure API Management
- Using mTLS with an Azure Application Gateway and API Management
- Connection to backends using client certificates
- Deploying client certificates in Key Vault with Azure Pipeline 1/2
- Deploying client certificates in Key Vault with Azure Pipeline 2/2


### Self-signed certificates

First things first. We need some certificates. Using [Generate and export certificates for point-to-site using PowerShell](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-certificates-point-to-site) as a guide, I created the following three of certificates.

![Self-signed certificates](../../../../static/images/apim-client-certificate-series/self-signed-certificates.png)

As you can see, we have one root CA certificate. Underneath it are two intermediate CA certificates that represent a development and test environment. Finally, we have two client certificates per environment.

I've created the script [generate-client-certificates.ps](https://github.com/ronaldbosma/blog-code-examples/blob/master/apim-client-certificate-series/00-self-signed-certificates/generate-client-certificates.ps1) to generate this certificate tree using PowerShell. It also exports all certificates in base64 encoded X.509 (.cer) files and additionally exports the client certificates with their private keys in PFX (.pfx) files. The results can be found in [this](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/00-self-signed-certificates/certificates) folder.

### Deploy API Management

Next, we need an API Management instance. We'll be deploying everything using Bicep and the Azure CLI. The following script contains the bare minimum to create an API Management instance using Bicep. Save it in a file called `main.bicep`.

```bicep
//=============================================================================
// Parameters
//=============================================================================

@description('The name of the API Management Service that will be created')
param apiManagementServiceName string

@description('Location to use for all resources')
param location string = resourceGroup().location

@description('The email address of the owner of the API Management service')
param publisherEmail string

@description('The name of the owner of the API Management service')
param publisherName string

//=============================================================================
// Resources
//=============================================================================

// API Management
resource apiManagementService 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: apiManagementServiceName
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}
```

As you can see, we're creating a Developer tier API Management instance. Normally for demos, I'd use the Consumption tier because it's cheap and rolled out quickly. However, the Consumption tier does not support CA certificates, which we'll need later on.

Use the following command to deploy the API Management instance. Replace the placeholders with your values. Note that this will take a while to complete (about ~30 minutes).

```powershell
az deployment group create `
    --name "deploy-$(Get-Date -Format "yyyyMMdd-HHmmss")" `
    --resource-group '<your-resource-group>' `
    --template-file './main.bicep' `
    --parameters apiManagementServiceName='<your-api-management-instance-name>' `
                 publisherEmail='<your-email>' `
                 publisherName='<your-name>' `
    --verbose
```


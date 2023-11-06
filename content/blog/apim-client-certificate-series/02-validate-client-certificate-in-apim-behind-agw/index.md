---
title: "Validate client certificates in API Management when its behind an Application Gateway"
date: 2023-11-06T00:00:00+02:00
publishdate: 2023-11-06T00:00:00+02:00
lastmod: 2023-11-06T00:00:00+02:00
tags: [ "Azure", "API Management", "Bicep", "Client Certificates", "Infra as Code", "Security" ]
draft: true
---

This blog post is the second in a series on how to work with client certificates in Azure API Management. In the series, I'll cover both the validation of client certificates in API Management and how to connect to backends using client certificates. 

While Azure's official documentation provides excellent guidance on setting up client certificates via the Azure Portal, this series takes it a step further. We'll dive into utilizing Bicep and other essential tools, like the Azure CLI, to automate the entire deployment process.

Topics covered in this series:

1. Validate client certificates in API Management
1. Validate client certificates in API Management when its behind an Application Gateway _**(current)**_
1. Connection to backends using client certificates _(coming soon)_
1. Deploying client certificates in Key Vault with Azure Pipeline 1/2 _(coming soon)_
1. Deploying client certificates in Key Vault with Azure Pipeline 2/2 _(coming soon)_

### Prerequisites

Use the result of the previous post as a starting point. You can find the code [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/01-validate-client-certificate-in-apim) and the self-signed certificates [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/00-self-signed-certificates).

#### Virtual Network

First off, we'll need a virtual network. Open the `main.bicep` from the previous post and add the following bicep:

```bicep
// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-validate-client-certificate'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-app-gateway'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        name: 'snet-api-management'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }

  resource agwSubnet 'subnets' existing = {
    name: 'snet-app-gateway'
  }

  resource apimSubnet 'subnets' existing = {
    name: 'snet-api-management'
  }
}
```

This snippet will create a basis virtual network with two subnets. One for the Application Gateway and one for API Management. It will also create a reference to the created subnets, so we can use their id's later on.

This is enough for purposes of this demo, but in a real-world scenario you probably want to add more security measures.

#### Deploy API Management in virtual network

Step two is to deploy API Management inside the virtual network. Locate the `apiManagementService` resources and add the following code to the properties section:

```bicep
virtualNetworkType: 'Internal'
virtualNetworkConfiguration: {
    subnetResourceId: virtualNetwork::apimSubnet.id
}
```

This will deploy API Management inside the virtual network and connect it to the subnet we created earlier. The `Internal` network type will make sure that API Management is not exposed to the internet.

Deploying a new or existing API Management instance inside a virtual network takes about 45 minutes. So it's best to start the deployment now before proceeding. You can use the following Azure CLI command (same as previous post). Replace the `<placeholders>` with your values.

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


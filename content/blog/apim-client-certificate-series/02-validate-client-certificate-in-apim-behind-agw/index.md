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

### Intro

In this second post we build upon the solution of the previous post. We'll deploy API Management behind an Application Gateway and configure the Application Gateway to validate client certificates. We'll also configure the Application Gateway to forward the client certificate to API Management for further validation.

This post provides a step by step guide. If you're interested in the end result, you can find it [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw). _(Note that the deployment will take up to 45 minutes, because API Management will be deployed inside a virtual network.)_

### Table of Contents

- [Prerequisites](#prerequisites)
  - [Virtual Network](#virtual-network)
  - [Deploy API Management in virtual network](#deploy-api-management-in-virtual-network)
  - [Public IP address](#public-ip-address)
  - [Deploy Application Gateway](#deploy-application-gateway)


### Prerequisites

This first section will cover the prerequisites for this post. Use the result of the previous post as a starting point. You can find the code [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/01-validate-client-certificate-in-apim) and the self-signed certificates [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/00-self-signed-certificates).

#### Virtual Network

First off, we'll need a virtual network for the Application Gateway. Open the `main.bicep` from the previous post and add the following bicep:

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

This Bicep will create a basic virtual network with two subnets. One for the Application Gateway and one for API Management. It will also create a reference to the created subnets, so we can use their IDs later on.

This configuration is enough for the demo, but in a real-world scenario you probably want to add more security measures.

#### Deploy API Management in virtual network

Step two is to deploy API Management inside the virtual network. Locate the `apiManagementService` resource and add the following code to the properties section:

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

#### Public IP address

For the Application Gateway we'll need a public IP address. Add the following bicep to the `main.bicep` file:

```bicep
// Public IP address
resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-validate-client-certificate'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}
```

#### Deploy Application Gateway

Now we can deploy the Application Gateway. We'll start with an https listener before implementing mTLS. Add the following bicep to the `main.bicep` file:

```bicep
var applicationGatewayName = 'agw-validate-client-certificate'

// Application Gateway
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-05-01' = {
  name: applicationGatewayName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    enableHttp2: false
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 2
    }

    gatewayIPConfigurations: [
      {
        name: 'agw-subnet-ip-config'
        properties: {
          subnet: {
            id: virtualNetwork::agwSubnet.id
          }
        }
      }
    ]
  }
}
```

##### Frontend

```bicep
frontendIPConfigurations: [
  {
    name: 'agw-public-frontend-ip'
    properties: {
      publicIPAddress: {
        id: publicIPAddress.id
      }
    }
  }
]

frontendPorts: [
  {
    name: 'port-https'
    properties: {
      port: 443
    }
  }
]

sslCertificates: [
  {
    name: 'agw-ssl-certificate'
    properties: {
      data: loadFileAsBase64('./ssl-cert.apim-sample.dev.pfx')
      password: 'P@ssw0rd'
    }
  }
]

httpListeners: [
  {
    name: 'https-listener'
    properties: {
      protocol: 'Https'
      hostName: 'apim-sample.dev'
      frontendIPConfiguration: {
        id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'agw-public-frontend-ip')
      }
      frontendPort: {
        id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'port-https')
      }
      sslCertificate: {
        id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', applicationGatewayName, 'agw-ssl-certificate')
      }
    }
  }
]
```

##### SSL Certificate

```powershell
# Settings
$dnsName = '<your-dns-name>' # e.g. 'apim-sample.dev
$plainTextPassword = '<your-password>'

# Create self-signed certificate
$params = @{
    DnsName = $dnsName
    CertStoreLocation = 'Cert:\CurrentUser\My'
}
$sslCertificate = New-SelfSignedCertificate @params

# Export the certificate with private key as .pfx file
$certificatePassword = ConvertTo-SecureString -String $plainTextPassword -Force -AsPlainText
$currentScriptPath = $MyInvocation.MyCommand.Path | Split-Path -Parent
Export-PfxCertificate -Cert $sslCertificate -FilePath "$currentScriptPath/ssl-cert.apim-sample.dev.pfx" -Password $certificatePassword
```

##### Backend

```bicep
backendAddressPools: [
  {
    name: 'apim-gateway-backend-pool'
    properties: {
      backendAddresses: [
        {
            fqdn: '${apiManagementServiceName}.azure-api.net'
        }
      ]
    }
  }
]

backendHttpSettingsCollection: [
  {
    name: 'apim-gateway-backend-settings'
    properties: {
      port: 443
      protocol: 'Https'
      cookieBasedAffinity: 'Disabled'
      pickHostNameFromBackendAddress: true
      requestTimeout: 20
    }
  }
]
```

##### Request routing rule

```bicep
requestRoutingRules: [
  {
    name: 'apim-https-routing-rule'
    properties: {
      priority: 10
      ruleType: 'Basic'
      httpListener: {
        id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'https-listener')
      }
      backendAddressPool: {
        id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, 'apim-gateway-backend-pool')
      }
      backendHttpSettings: {
        id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'apim-gateway-backend-settings')
      }
    }
  }
]
```
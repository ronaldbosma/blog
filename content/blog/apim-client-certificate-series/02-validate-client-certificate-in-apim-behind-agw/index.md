---
title: "Validate client certificates in API Management when its behind an Application Gateway"
date: 2024-02-02T12:00:00+01:00
publishdate: 2024-02-02T12:00:00+01:00
lastmod: 2024-02-02T12:00:00+01:00
tags: [ "Azure", "API Management", "Application Gateway", "Bicep", "Client Certificates", "Infra as Code", "mTLS", "Security" ]
draft: true
---

This post is the second in a series on how to work with client certificates in Azure API Management. In the series, I'll cover both the validation of client certificates in API Management and how to connect to backends with mTLS (mutual TLS) using client certificates.

While Azure's official documentation provides excellent guidance on setting up client certificates via the Azure Portal, this series takes it a step further. We'll dive into utilizing Bicep and other essential tools, like the Azure CLI, to automate the entire deployment process.

Topics covered in this series:

1. [Validate client certificates in API Management](/blog/2024/02/02/validate-client-certificates-in-api-management/)
1. Validate client certificates in API Management when its behind an Application Gateway _**(current)**_
1. Connect to backends using client certificates _(coming soon)_

### Intro

In this second post we build upon the solution of [the previous post](/blog/2024/02/02/validate-client-certificates-in-api-management/). We'll deploy API Management inside a virtual network behind an application gateway and configure the application gateway to validate client certificates. We'll also configure the application gateway to forward the client certificate to API Management for further validation.

This post provides a step-by-step guide. If you're interested in the end result, you can find it [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw). _(Note that the deployment will take up to 45 minutes, because API Management will be deployed inside a virtual network.)_

The application gateway configuration outlined in this post can also be used in other situations. For example, when you have ASP.NET APIs hosted in App Services.


> Mention TLS termination. Thats why we can't reuse the first post. Add image with certificate flow. See [Overview of TLS termination and end to end TLS with Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/ssl-overview)


### Table of Contents

- [Prerequisites](#prerequisites)
  - [Deploy API Management in virtual network](#deploy-api-management-in-virtual-network)
  - [Deploy Application Gateway with TLS listener](#deploy-application-gateway-with-tls-listener)
  - [Test Deployment](#test-deployment)
- [Add mTLS listener to Application Gateway](#add-mtls-listener-to-application-gateway)
- [Forward client certificate to API Management](#forward-client-certificate-to-api-management)

### Prerequisites

This first section will cover the prerequisites for this post. Use the result of the previous post as a starting point. You can find the code [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/01-validate-client-certificate-in-apim) and the self-signed certificates [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/00-self-signed-certificates).

#### Deploy API Management in virtual network

We're going to deploy API Management inside a virtual network with the `internal` mode enabled, restricting access from external clients. To enable external access, we'll route traffic through an application gateway.

[Multiple compute platforms](https://learn.microsoft.com/en-us/azure/api-management/compute-infrastructure) are available for API Management. Since we're opting for the Developer tier, we have the choice between versions `stv1` and `stv2`. However, `stv1` will be retired in August 2024. Hence, for the purposes of this blog post, we'll be using `stv2`. This does mean configuring additional resources for API Management to work inside the virtual network. See [the documentation](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet?tabs=stv2#prerequisites) for a comparison between the prerequisites for `stv1` and `stv2`.


> TODO: add a network image somewhere here...


##### Network Security Group

One of the first prerequisites is an NSG (Network Security Group) to allow inbound connectivity to API Management. The necessary rules that we'll be configuring can be found [here](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet?tabs=stv2#configure-nsg-rules).

Open the `main.bicep` from the previous post and add the following Bicep:

```bicep
// Network Security Group for API Management subnet
resource apimNSG 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-apim-validate-client-certificate'
  location: location
  properties: {
    securityRules: [
      {
        name: 'management-endpoint-for-azure-portal-and-powershell'
        properties: {
          access: 'Allow'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          direction: 'Inbound'
          protocol: 'TCP'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
          priority: 110
        }
      }
      {
        name: 'azure-infrastructure-load-balancer'
        properties: {
          access: 'Allow'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          direction: 'Inbound'
          protocol: 'TCP'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
          priority: 120
        }
      }
      {
        name: 'dependency-on-azure-storage'
        properties: {
          access: 'Allow'
          sourcePortRange: '*'
          destinationPortRange: '443'
          direction: 'Outbound'
          protocol: 'TCP'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          priority: 140
        }
      }
      {
        name: 'access-to-azure-sql-endpoints'
        properties: {
          access: 'Allow'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          direction: 'Outbound'
          protocol: 'TCP'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          priority: 150
        }
      }
      {
        name: 'access-to-azure-key-vault'
        properties: {
          access: 'Allow'
          sourcePortRange: '*'
          destinationPortRange: '443'
          direction: 'Outbound'
          protocol: 'TCP'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureKeyVault'
          priority: 160
        }
      }
      {
        name: 'publish-diagnostics-logs-and-metrics-resource-health-and-application-insights'
        properties: {
          access: 'Allow'
          sourcePortRange: '*'
          destinationPortRange: '443'
          direction: 'Outbound'
          protocol: 'TCP'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'AzureMonitor'
          priority: 170
        }
      }
    ]
  }
}
```

##### Virtual Network

Next, we'll need a virtual network for the application gateway and API management. Add the following Bicep to the `main.bicep` file:

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
          networkSecurityGroup: {
            id: apimNSG.id
          }
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

This Bicep code will create a virtual network with two subnets: one for the application gateway and another for API Management. The latter is configured with the NSG. The code will also create a reference to the created subnets, so we can use their IDs later on.

This configuration is enough for this demo, but in a real-world scenario you probably want to add more security measures.

##### Public IP address for API Management

To deploy API Management in a virtual network, it also requires a public IP address. The public IP address is only used for management operations, because we're going to deploy API Management in `internal` mode. Add the following Bicep to the `main.bicep` file:

```bicep
// API Management Public IP address
resource apimPublicIPAddress 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-apim-validate-client-certificate'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      // The label you choose to use does not matter but a label is required if this resource will be assigned to an API Management service.
      domainNameLabel: apiManagementServiceName
    }
  }
}
```

##### Add API Management to virtual network

We can now deploy API Management inside the virtual network. Locate the `apiManagementService` resource and add the following code to the properties section:

```bicep
virtualNetworkType: 'Internal'
virtualNetworkConfiguration: {
    subnetResourceId: virtualNetwork::apimSubnet.id
}
publicIpAddressId: apimPublicIPAddress.id
```

This will deploy API Management inside the virtual network and connect it to the subnet we created earlier. The `Internal` network type will make sure that API Management is not exposed outside the virtual network. It also configures the public IP address created in the previous step.

##### Deploy changes

Deploying a new or existing API Management instance inside a virtual network can take up to **45 minutes**. So it's best to start the deployment now before proceeding. You can use the following Azure CLI command (same as previous post). Replace the `<placeholders>` with your values.

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

#### Deploy Application Gateway with TLS listener

Now we can configure the application gateway. We'll start with TLS (a.k.a. SSL) before implementing mTLS.

##### Public IP address

First, we'll need a public IP address for the application gateway. Add the following Bicep to the `main.bicep` file:

```bicep
// Public IP address
resource agwPublicIPAddress 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-agw-validate-client-certificate'
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

##### Application Gateway

To create a basic application gateway, add the following Bicep to the `main.bicep` file:

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

As you can see, the application gateway is deployed in its designated subnet.

This will deploy an application gateway, but it won't do anything yet. We'll need to add several components to allow HTTPS traffic to the application gateway and route it to API Management. See the image below for a visual representation of the components that we'll be adding to the application gateway:

![](../../../../static/images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-listener.png)
![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-listener.png)

The configuration consists of three parts:
1. The frontend (at the top) for incoming traffic defines the IP address, specifies the protocol and port to use, and specifies the SSL certificate to use.
2. The backend (bottom part) for outing traffic outlines where requests should be forwarded to, specifying the protocol and port to use, timeouts, etc.
3. The routing rule in the middle connects the frontend and backend configurations.

See [Application gateway components](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-components) for more information about the different components.

##### Frontend

Lets start with the frontend. Add the following Bicep code to the `properties` section of the application gateway:

```bicep
frontendIPConfigurations: [
  {
    name: 'agw-public-frontend-ip'
    properties: {
      publicIPAddress: {
        id: agwPublicIPAddress.id
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

As you can see, the frontend IP configuration is linked to the previously added public IP address. We'll be accepting traffic on the standard HTTPS port `443`, so we also configure an SSL certificate. The HTTP listener connects these parts together.

> In a real world scenario, we would add the SSL certificate to Key Vault and link to it from the `sslCertificates` configuration. For demo purposes, we'll upload it directly to the application gateway. In the next post of this series, we'll explore how to upload a PFX certificate to Key Vault and use it.


##### SSL Certificate

For this demo, I'm using a self-signed certificate. To create the SSL certificate, run the following PowerShell script in the same directory as your `main.bicep` file.

```powershell
# Settings
$dnsName = 'apim-sample.dev'
$plainTextPassword = 'P@ssw0rd'

# Create self-signed certificate
$params = @{
    DnsName = $dnsName
    CertStoreLocation = 'Cert:\CurrentUser\My'
}
$sslCertificate = New-SelfSignedCertificate @params

# Export the certificate with private key as .pfx file
$certificatePassword = ConvertTo-SecureString -String $plainTextPassword -Force -AsPlainText
Export-PfxCertificate -Cert $sslCertificate -FilePath "./ssl-cert.apim-sample.dev.pfx" -Password $certificatePassword
```

If you've modified the certificate password, file path, or filename, be sure to update the Bicep code accordingly. See [the documentation](https://learn.microsoft.com/en-us/powershell/module/pki/new-selfsignedcertificate?view=windowsserver2022-ps) for more information about the `New-SelfSignedCertificate` commandlet.

##### Backend

Next, we'll configure the backend. Add the following Bicep code to the `properties` section of the application gateway:

```bicep
backendAddressPools: [
  {
    name: 'apim-gateway-backend-pool'
    properties: {
      backendAddresses: [
        {
            ipAddress: apiManagementService.properties.privateIPAddresses[0]
        }
      ]
    }
  }
]

probes: [
  {
    name: 'apim-gateway-probe'
    properties: {
      pickHostNameFromBackendHttpSettings: true
      interval: 30
      timeout: 30
      path: '/status-0123456789abcdef'
      protocol: 'Https'
      unhealthyThreshold: 3
      match: {
        statusCodes: [
          '200-399'
        ]
      }
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
      hostName: '${apiManagementServiceName}.azure-api.net'
      requestTimeout: 20
      probe: {
        id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'apim-gateway-probe')
      }
    }
  }
]
```

The backend pool routes requests to backend servers. I've opted to use the private IP address of the API Management instance. More options can be found [here](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-components#backend-pools).

The probe is used by the application gateway to monitor the health of all resources in a backend pool. In this case, we're using the `/status-0123456789abcdef` path, which is the default health endpoint provided by API Management.

The backend HTTP settings section, among other things, defines the port and protocol to use, the backend hostname and the associated health probe. 

It's important to note that the backend will use an SSL connection to communicate with API Management. However, it's currently not possible to use mTLS between the application gateway and a backend. Please refer to [the FAQ](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-faq#is-mutual-authentication-available-between-application-gateway-and-its-backend-pools) for more details.

##### Request routing rule

The final step is to connect the frontend and backend. For this, we can use a request routing rule. Add the following Bicep code to the `properties` section of the application gateway:

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

##### Deploy

Deploy the application gateway using the Azure CLI command you've used before. The deployment will take about 5-7 minutes to complete.


#### Test Deployment

The application gateway can be reached on `https://apim-sample.dev`. However, because we've used a self-signed certificate and `apim-sample.dev` is not a registered domain, you'll have to update your hosts file to be able to reach the application gateway.

Locate the public IP address resource of the application gateway (`pip-agw-validate-client-certificate`) in the Azure Portal, open it and copy the IP address. Open your hosts file (`C:\Windows\System32\drivers\etc\hosts` on Windows, `/private/etc/hosts` on Mac or `/etc/hosts` on Linux) and add the following line, replacing `<your-public-ip-address>` with the IP address you copied.

```
<your-public-ip-address> apim-sample.dev
```

Now you can test if everything is configured correctly. Save the following snippet in a new `.http` file and open it in Visual Studio Code with the [REST Client extension](https://marketplace.visualstudio.com/items?itemName=humao.rest-client). Click the `Send Request` link to send the request.

```
### Test that API Management can be reached (/status-0123456789abcdef is a default endpoint you can use)

GET https://apim-sample.dev/status-0123456789abcdef
```

This request will call the `/status-0123456789abcdef` endpoint, which is a default endpoint you can use to test if API Management is reachable. If everything is configured correctly, you should get a `200 OK` response.


### Add mTLS listener to Application Gateway

Now that we've validated that everything works correctly, we can add mTLS support. Before we proceed, it's good to understand how the application gateway performs client certificate validation. The application gateway does **not** have the capability to 'whitelist' individual client certificates. However, it can verify whether a client certificate was issued by a trusted certificate authority (CA).

In our example, we only want to allow client certificates issued by `APIM Sample DEV Intermediate CA`. The figure below highlights which certificates we need to upload to the application gateway for this to work.

![](../../../../static/images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-agw-certificate-validation.png)
![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-agw-certificate-validation.png)

When using a well-known certificate authority, it's important to note the following, as mentioned on [Overview of mutual authentication with Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/mutual-authentication-overview#certificates-supported-for-mutual-authentication):

> "When issuing client certificates from well established certificate authorities, consider working with the certificate authority to see if an intermediate certificate can be issued for your organization to prevent inadvertent cross-organizational client certificate authentication."


To add mTLS support, we can reuse some of the components that we've configured for the TLS listener, such as the SSL certificate and backend configuration. The figure below highlights the new components we'll need to add.

![](../../../../static/images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-and-mtls-listener-1.png)
![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-and-mtls-listener-1.png)

As you can see, we'll add a second listener that accepts traffic on port `53029`. We'll also need to configure an SSL profile with trusted certificates to validate the client certificate and add a rule to route traffic to the API Management backend.

Please note that in this scenario, we allow both TLS and mTLS traffic to the application gateway. This can be useful when you support multiple authentication methods. While some clients may support mTLS and use a client certificate for authentication, others may only support TLS and authenticate with a bearer token.

#### Prepare certificate chain

Because we're only allowing client certificates issued by a specific self-signed intermediate CA, we'll need to upload the complete certificate chain. The chain should be in a single `.cer` file and include all intermediate CAs and the root CA.

You can use the sample [dev-intermediate-ca-with-root-ca.cer](https://github.com/ronaldbosma/blog-code-examples/blob/master/apim-client-certificate-series/00-self-signed-certificates/certificates/dev-intermediate-ca-with-root-ca.cer) or create your own. If you choose the latter, take the public part of all certificates in the chain and combine them in a single `.cer` file. The result should resemble the example below.

```
-----BEGIN CERTIFICATE-----
MIIDOjCCAiKgAwIBAgIQZk5nkg3ljYVOM77uz5hVODANBgkqhkiG9w0BAQsFADAeMRwwGgYDVQQD
DBNBUElNIFNhbXBsZSBSb290IENBMCAXDTI0MDIwMjA4Mzk0M1oYDzIwNzQwMjAyMDg0OTQzWjAq
............................... TRUNCATED ..................................
o6jtMJfs6GPOtG4nPSWkVt5rBwJ4d0DyXtEWeD+/I480AlzHcc5ouD9qIvxOEp8g7mqNiOgeTu3S
SDaqFo055aIYM5iChX9twG3FSUc03YtgfuwlkeXEA+Q=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDCjCCAfKgAwIBAgIQTnzUTsk8yb1GxOisPnNyQjANBgkqhkiG9w0BAQsFADAeMRwwGgYDVQQD
DBNBUElNIFNhbXBsZSBSb290IENBMCAXDTI0MDIwMjA4Mzk0MloYDzIwNzQwMjAyMDg0OTQyWjAe
............................... TRUNCATED ..................................
3IDy7OcjtfLZkCstp18fS7yzk/+LmUOk2wUHJKl2PwfninaUA0m+k58fMZXYFZ80p/MFX8BpBLdQ
tPq4cH7fgj/8rE8pMN4cCv/3SfpaDwgPdfHEOL5C+A7eVgY8jtp79JQ=
-----END CERTIFICATE-----
```

#### SSL Profile with Trusted Certificate

Now we can configure the SSL profile and upload the trusted certificates. Add the following Bicep to the `properties` section of the `applicationGateway` resource. Replace `<path-to-certificates>` with the path to your `.cer` file.

```bicep
trustedClientCertificates: [
  {
    name: 'intermediate-ca-with-root-ca'
    properties: {
      data: loadTextContent('<path-to-certificates>/dev-intermediate-ca-with-root-ca.cer')
    }
  }
]

sslProfiles: [
  {
    name: 'mtls-ssl-profile'
    properties: {
      clientAuthConfiguration: {
        // By setting verifyClientCertIssuerDN to true the intermediate CA is also checked, not just the Root CA.
        // See https://learn.microsoft.com/en-us/azure/application-gateway/mutual-authentication-overview?tabs=powershell#verify-client-certificate-dn
        verifyClientCertIssuerDN: true
      }
      trustedClientCertificates: [
        {
          id: resourceId('Microsoft.Network/applicationGateways/trustedClientCertificates', applicationGatewayName, 'intermediate-ca-with-root-ca')
        }
      ]
    }
  }
]
```

Please note that the `verifyClientCertIssuerDN` property is set to `true`. By default, only the root CA certificate is checked. In our example, this means that a client certificate issued by `APIM Sample TST Intermediate CA` for the test environment would be accepted, even though we've uploaded the other intermediate certificate `APIM Sample DEV Intermediate CA` of the dev environment. By setting `verifyClientCertIssuerDN` to `true`, the intermediate certificate will also be checked and only certificates created by `APIM Sample DEV Intermediate CA` are accepted. You can find more details [here](https://learn.microsoft.com/en-us/azure/application-gateway/mutual-authentication-overview#verify-client-certificate-dn).


#### mTLS Port

Next, we'll need to configure a port. Because `443` is already in use, we'll configure port `53029`. Add the following to the `frontendPorts` array:

```bicep
{
  name: 'port-mtls'
  properties: {
    port: 53029
  }
}
```

In this demo we haven't configured any NSG rules for the application gateway subnet. If you have a stricter configuration, you might also need to allow inbound traffic on port `53029`.

#### mTLS Listener

The final step for the frontend configuration is to set up the listener itself. Add the following to the `httpListeners` array:

```bicep
{
  name: 'mtls-listener'
  properties: {
    protocol: 'Https'
    hostName: 'apim-sample.dev'
    frontendIPConfiguration: {
      id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'agw-public-frontend-ip')
    }
    frontendPort: {
      id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'port-mtls')
    }
    sslCertificate: {
      id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', applicationGatewayName, 'agw-ssl-certificate')
    }
    sslProfile: {
      id: resourceId('Microsoft.Network/applicationGateways/sslProfiles', applicationGatewayName, 'mtls-ssl-profile')
    }
  }
}
```

As you can see, we're reusing the frontend IP configuration and SSL certificate. The frontend port and SSL profile differ from the TLS listener.

#### Routing Rule

Finally, we need to connect the mTLS listener to the already existing backend. Add the following Bicep to the `requestRoutingRules` array:

```bicep
{
  name: 'apim-mtls-routing-rule'
  properties: {
    priority: 30
    ruleType: 'Basic'
    httpListener: {
      id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'mtls-listener')
    }
    backendAddressPool: {
      id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, 'apim-gateway-backend-pool')
    }
    backendHttpSettings: {
      id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'apim-gateway-backend-settings')
    }
  }
}
```

This is all that's required for mTLS support. Now, deploy the changes using the Azure CLI command you've used before.


#### Test mTLS

Add the following snippet to your `.http` file. Try sending the requests.

```
### Test that API Management can be reached

GET https://apim-sample.dev:53029/status-0123456789abcdef


### Validates client certificate using validate-client-certificate policy

GET https://apim-sample.dev:53029/client-cert/validate-using-policy


### Validates client certificate using the context.Request.Certificate property

GET https://apim-sample.dev:53029/client-cert/validate-using-context
```

All request will fail with a response similar to the one below, as we haven't configured the REST Client extension to send a client certificate yet.

```
HTTP/1.1 400 Bad Request
Server: Microsoft-Azure-Application-Gateway/v2

<html>
<head><title>400 No required SSL certificate was sent</title></head>
<body>
<center><h1>400 Bad Request</h1></center>
<center>No required SSL certificate was sent</center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
</html>
```

To use a client certificate, we'll need to update the user settings in Visual Studio Code. (See the [GitHub documentation](https://github.com/Huachao/vscode-restclient#ssl-client-certificates) for more details.)

- Open the  Command Palette (`Ctrl+Shift+P`) and choose `Preferences: Open User Settings (JSON)`.
- Add the following configuration to the settings file.  
  _(If you've followed along with the previous post, the `rest-client.certificates` section should already exist.)_

  ```json
  "rest-client.certificates": {
    "apim-sample.dev:53029": {
      "pfx": "<path-to-certificates>/dev-client-01.pfx",
      "passphrase": "P@ssw0rd"
    }
  }
  ```
  
- Don't forget to change the passphrase if you're using your own certificates.
- Save the changes.

Now, if you send a request to `https://apim-sample.dev:53029/status-0123456789abcdef`, it should succeed. However, if you use a client certificate from another intermediate CA, such as `tst-client-01.pfx`, a `400 Bad Request` is returned as expected.

The requests to `/client-cert/validate-using-policy` and `/client-cert/validate-using-context` continue to fail, despite providing a valid client certificate. Both endpoints return a `401` with the message `Client certificate missing`. The reason for the error is that the client certificate is not sent to API Management due to the application gateway terminating the TLS session. This means that we can't use the `validate-client-certificate` policy or the `context.Request.Certificate` property. The next section will explain how to forward the certificate to API Management.


### Forward client certificate to API Management

We can forward the provided client certificate to API Management in a header. Using a rewrite rule, we can access the client certificate with the `client_certificate` server variable and place it in the header. See [Rewrite HTTP headers and URL with Application Gateway - Mutual authentication server variables](https://learn.microsoft.com/en-us/azure/application-gateway/rewrite-http-headers-url#mutual-authentication-server-variables) for more information on the available server variables.

We'll use `X-ARR-ClientCert` as the header name. This is a common name that is also used in similar scenarios. For example, Azure App Services uses this header to pass a client certificate to an app like an ASP.NET Web API. _(See [Configure TLS mutual authentication for Azure App Service - Access client certificate](https://learn.microsoft.com/en-us/azure/app-service/app-service-web-configure-tls-mutual-auth?tabs=azurecli#access-client-certificate) for more details if you're interested in this scenario._)

The figure below shows the rewrite rule to add. As you can see, it will be linked to the routing rule of the mTLS listener.

![](../../../../static/images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-and-mtls-listener-2.png)
![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-and-mtls-listener-2.png)

To configure the rewrite rule, add the following Bicep to the `properties` section of the `applicationGateway` resource:

```bicep
rewriteRuleSets: [
  {
    name: 'mtls-rewrite-rules'
    properties: {
      rewriteRules: [
        {
          ruleSequence: 100
          conditions: []
          name: 'Add Client certificate to HTTP header'
          actionSet: {
            requestHeaderConfigurations: [
              {
                headerName: 'X-ARR-ClientCert'
                headerValue: '{var_client_certificate}'
              }
            ]
            responseHeaderConfigurations: []
          }
        }
      ]
    }
  }
]
```

To link the rewrite rule to the routing rule, locate the `apim-mtls-routing-rule` routing rule and add a reference to the new `mtls-rewrite-rules` rewrite rule set using the following Bicep:

```bicep
rewriteRuleSet: {
  id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', applicationGatewayName, 'mtls-rewrite-rules')
}
```

To test if the client certificate is forwarded to API Management, we'll add a new operation. First, create a file called `validate-from-agw.operation.cshtml` and add the following policies. This will return a `200 OK` with the passed client certificate in the response body. If no client certificate is forwarded, the text `No client certificate passed` is be returned.

```xml
<policies>
    <inbound>
        <base />
        <return-response>
            <set-status code="200" />
            <set-body>@(context.Request.Headers.GetValueOrDefault("X-ARR-ClientCert", "No client certificate passed"))</set-body>
        </return-response>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

Add the following Bicep so the new operation is deployed within the `clientCertApi` API.

```bicep
// Operation to validate client certificate received from Application Gateway
resource validateFromAppGateway 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = {
  name: 'validate-from-agw'
  parent: clientCertApi
  properties: {
    displayName: 'Validate (from AGW)'
    description: 'Validates client certificate received from Application Gateway'
    method: 'GET'
    urlTemplate: '/validate-from-agw'
  }

  resource policies 'policies' = {
    name: 'policy'
    properties: {
      format: 'rawxml'
      value: loadTextContent('./validate-from-agw.operation.cshtml') 
    }
  }
}
```

Deploy the changes. After the deployment, use the following request to test the new operation. 

```
### mTLS (should return the X-ARR-ClientCert header value and certificate details)

GET https://apim-sample.dev:53029/client-cert/validate-from-agw
```

The result should be a `200 OK`, with the response body resembling the following snippet:

```
HTTP/1.1 200 OK

-----BEGIN%20CERTIFICATE-----%0AMIIDRTCCAi..... TRUNCATED .....6Zdlr9V53Q%3D%3D%0A-----END%20CERTIFICATE-----%0A
```

The response body contains the value of the `X-ARR-ClientCert` header. The value is the `Base-64 encoded X.509 (.CER)` representation of the client certificate. This is the public part of the client certificate without the private key. Special characters, like the white spaces, are URL encoded.


### Other

If you deploy this solution to an Azure subscription with limited credits, take note that both the virtual network and application gateway are not cheap. It's best to remove everything after you're done. If you want to keep the solution around a little longer, you can stop the application gateway. This will stop the billing.

To stop the application gateway, use the following Azure CLI command:

```powershell
az network application-gateway stop --name 'agw-validate-client-certificate' --resource-group '<your-resource-group>'
```

And you can start it again with the following Azure CLI command:

```powershell
az network application-gateway start --name 'agw-validate-client-certificate' --resource-group '<your-resource-group>'
```
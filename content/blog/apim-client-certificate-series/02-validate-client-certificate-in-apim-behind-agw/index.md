---
title: "Validate client certificates in API Management when it's behind an Application Gateway"
date: 2024-02-19T19:00:00+01:00
publishdate: 2024-02-19T19:00:00+01:00
lastmod: 2024-11-13T17:45:00+01:00
tags: [ "Azure", "API Management", "Application Gateway", "Azure Integration Services", "Bicep", "Client Certificates", "Infra as Code", "mTLS", "Security" ]
series: [ "client-certificates-and-mtls-in-api-management" ]
summary: "In this second post, we expand on the solution from the previous post. We'll deploy API Management inside a virtual network, positioning it behind an application gateway. We'll configure the application gateway with an mTLS listener to validate client certificates and forward them to API Management for further processing. This approach can also be used with other types of backends, such as an ASP.NET Web API."
---

This post is the second in a series on working with client certificates in Azure API Management. Throughout the series, I'll cover both the validation of client certificates in API Management and how to connect to backends with mTLS (mutual TLS) using client certificates.

While Azure's official documentation provides excellent guidance on setting up client certificates via the Azure Portal, this series takes it a step further. We'll dive into utilizing Bicep and other essential tools, like the Azure CLI, to automate the entire deployment process.

Topics covered in this series:

1. [Validate client certificates in API Management](/blog/2024/02/02/validate-client-certificates-in-api-management/)
1. Validate client certificates in API Management when it's behind an Application Gateway _**(current)**_
1. [Securing backend connections with mTLS in API Management](/blog/2024/05/24/securing-backend-connections-with-mtls-in-api-management/)

### Intro

In this second post, we expand on the solution introduced in [the previous post](/blog/2024/02/02/validate-client-certificates-in-api-management/). We'll deploy API Management inside a virtual network, positioning it behind an application gateway. Utilizing an application gateway (or similar resource) in this manner is a common approach because it can provide load balancing capabilities and enhanced control over inbound and outbound traffic. Additionally, the Web Application Firewall (WAF) provides improved security by protecting against common web-based attacks and vulnerabilities, such as SQL injection and cross-site scripting (XSS).

We'll configure the application gateway with an mTLS listener to validate client certificates and forward them to API Management for further processing. You can find an example of the communication flow in the figure below:

![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-overview.png)

Note that the application gateway terminates the TLS session, as described [here](https://learn.microsoft.com/en-us/azure/application-gateway/ssl-overview). This results in the client certificate not being sent to API Management, which means we can't rely on the options provided in the previous post to validate the client certificate. 


This post provides a solution in the form of a step-by-step guide, once again using Bicep to deploy all components to Azure. If you're interested in the final result, you can find it [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw). _(Please note that the deployment process may take up to 30-45 minutes to complete.)_

The application gateway configuration outlined in this post can also be applied to other scenarios, such as ASP.NET APIs hosted in App Services.


### Table of Contents

- [Prerequisites](#prerequisites)
  - [Deploy API Management in virtual network](#deploy-api-management-in-virtual-network)
  - [Deploy Application Gateway with HTTPS listener](#deploy-application-gateway-with-https-listener)
  - [Test Deployment](#test-deployment)
- [Add mTLS listener to Application Gateway](#add-mtls-listener-to-application-gateway)
- [Forward client certificate to API Management](#forward-client-certificate-to-api-management)
- [Validate client certificate in API Management](#validate-client-certificate-in-api-management)
- [Plugging the security hole](#plugging-the-security-hole)
- [Conclusion](#conclusion)

### Prerequisites

This first section will cover the prerequisites for this post. Use the result of the previous post as a starting point. You can find the code [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/01-validate-client-certificate-in-apim) and the self-signed certificates [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/00-self-signed-certificates).

We're going to deploy API Management inside a virtual network with the `internal` mode enabled, restricting access from external clients. To enable external access, we'll route traffic through an application gateway. We'll configure two external endpoints: one for normal TLS and one for mTLS. You can find a visualization of the setup in the figure below.

![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-network.png)

#### Deploy API Management in virtual network

We'll start by deploying API Management inside a virtual network. Because API Management offers [multiple compute platforms](https://learn.microsoft.com/en-us/azure/api-management/compute-infrastructure), we need to decide which one to use. We're using the Developer tier, so we have the choice between versions `stv1` and `stv2`. However, `stv1` will be retired in August 2024. So, for the purposes of this blog post, we'll be using `stv2`. This does mean configuring additional resources for API Management to work inside the virtual network. See [the documentation](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet?tabs=stv2#prerequisites) for a comparison between the prerequisites for `stv1` and `stv2`.


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

Next, we'll need a virtual network for the application gateway and API Management. Add the following Bicep to the `main.bicep` file:

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

This Bicep code will create a virtual network with two subnets: one for the application gateway and another for API Management. The latter is configured with the NSG. Additionally, the code will create a reference to the created subnets, allowing us to use their IDs later on.

This configuration is sufficient for this demo, but in a real-world scenario, you would likely want to implement additional security measures.

##### Public IP address for API Management

To deploy API Management in a virtual network, a public IP address is required. This public IP address is only used for management operations, as API Management will be deployed in `internal` mode. Add the following Bicep code to the `main.bicep` file:

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

We can now deploy API Management inside the virtual network. Locate the `apiManagementService` resource and add the following Bicep to the `properties` section:

```bicep
virtualNetworkType: 'Internal'
virtualNetworkConfiguration: {
    subnetResourceId: virtualNetwork::apimSubnet.id
}
publicIpAddressId: apimPublicIPAddress.id
```

This will deploy API Management inside the virtual network and connect it to the subnet we created earlier. The `Internal` network type will make sure that API Management is not exposed outside the virtual network. It also configures the public IP address created in the previous step.

##### Deploy changes

Deploying a new or existing API Management instance inside a virtual network can take up to **25-45 minutes**. So it's best to start the deployment now before proceeding. You can use the following Azure CLI command (same as previous post). Replace the `<placeholders>` with your values.

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

#### Deploy Application Gateway with HTTPS listener

Now we can configure the application gateway. We'll start with normal TLS before implementing mTLS.

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

![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-listener.png)

The configuration consists of three parts:
1. The frontend for incoming traffic at the top defines the IP address, specifies the protocol and port to use, and specifies the SSL certificate to use.
2. The backend for outbound traffic at the bottom defines where requests should be forwarded to, specifying the protocol and port to use, timeouts, etc.
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
As you can see, the frontend IP configuration is linked to the previously added public IP address. We'll accept traffic on the standard HTTPS port `443`, so we'll also configure an SSL certificate. The HTTP listener connects these components together. We'll introduce a second listener when adding mTLS support, so we'll refer to this listener as the HTTPS listener for the remainder of this post.

In a real-world scenario, the SSL certificate would typically be stored in Key Vault, and we would link to it from the `sslCertificates` configuration. However, for this demo, we'll upload it directly to the application gateway. In the [next post](/blog/2024/05/24/securing-backend-connections-with-mtls-in-api-management/#call-backend-using-mtls) of this series, we'll explore how to create a certificate in Key Vault and use it.


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

If you've modified the certificate password, file path, or filename, be sure to update the Bicep code accordingly. See [the documentation](https://learn.microsoft.com/en-us/powershell/module/pki/new-selfsignedcertificate?view=windowsserver2022-ps) for more information about the `New-SelfSignedCertificate` cmdlet.

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

The backend HTTP settings section, among other things, defines the port and protocol to use, the backend hostname, and the associated health probe. 

It's important to note that the backend will use a normal TLS connection to communicate with API Management because it's currently not possible to use mTLS between the application gateway and a backend. Please refer to [the FAQ](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-faq#is-mutual-authentication-available-between-application-gateway-and-its-backend-pools) for more details.

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

Deploy the application gateway using the Azure CLI command you've used before. The deployment will take about 5-7 minutes to complete.


#### Test Deployment

The application gateway can be reached on `https://apim-sample.dev`. Since we've used a self-signed certificate and `apim-sample.dev` is not a registered domain, you'll have to update your hosts file to be able to reach the application gateway.

Locate the public IP address resource of the application gateway in the Azure Portal (`pip-agw-validate-client-certificate`), open it, and copy the IP address. Open your hosts file (`C:\Windows\System32\drivers\etc\hosts` on Windows, `/private/etc/hosts` on Mac, or `/etc/hosts` on Linux) and add the following line, replacing `<your-public-ip-address>` with the IP address you copied.

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

Now that we've checked that everything works, we can add mTLS support. Before proceeding, it's good to understand how the application gateway performs client certificate validation. The application gateway does **not** have the capability to 'whitelist' individual client certificates. However, it can verify whether a client certificate was issued by a trusted certificate authority (CA).

We'll use the same [self-signed certificates](/blog/2024/02/02/validate-client-certificates-in-api-management/#self-signed-certificates) used in the previous post. In our example, we only want to allow client certificates issued by `APIM Sample DEV Intermediate CA` to be able to call the application gateway. The figure below highlights which certificates we need to upload for this to work.

![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-agw-certificate-validation.png)

When using a well-known certificate authority, it's important to note the guidance provided on [Overview of mutual authentication with Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/mutual-authentication-overview#certificates-supported-for-mutual-authentication):

> "When issuing client certificates from well established certificate authorities, consider working with the certificate authority to see if an intermediate certificate can be issued for your organization to prevent inadvertent cross-organizational client certificate authentication."


We can reuse components configured for the HTTPS listener, such as the SSL certificate and backend configuration, to add mTLS support. The figure below highlights the new components we'll need to add.

![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-and-mtls-listener-1.png)

As you can see, we'll add a second listener that accepts traffic on port `53029`. We'll also need to configure an SSL profile with trusted certificates to validate the client certificate, and add a rule to route traffic to the API Management backend.

It's important to note that in this scenario, we allow both TLS and mTLS traffic to the application gateway. This can be useful when you support multiple authentication methods. While some clients may support mTLS and use a client certificate for authentication, others may only support TLS and authenticate with for example a bearer token.

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

Now we can configure the SSL profile and upload the trusted certificates. Add the following Bicep to the `properties` section of the `applicationGateway` resource. Replace `<path-to-certificates>` with the file path to your `.cer` file.

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

Please note that the `verifyClientCertIssuerDN` property is set to `true`. By default, only the root CA certificate is checked. In our example, this would mean that a client certificate issued by `APIM Sample TST Intermediate CA` for the test environment would be accepted, even though we've only uploaded the other intermediate certificate, `APIM Sample DEV Intermediate CA`, for the development environment. By setting `verifyClientCertIssuerDN` to `true`, the intermediate certificate will also be checked, and only certificates issued by `APIM Sample DEV Intermediate CA` will be accepted. You can find more details [here](https://learn.microsoft.com/en-us/azure/application-gateway/mutual-authentication-overview#verify-client-certificate-dn).


#### mTLS Port

Next, we'll need to configure a port. Since port `443` is already in use, we'll configure a second port. Add the following to the `frontendPorts` array:

```bicep
{
  name: 'port-mtls'
  properties: {
    port: 53029
  }
}
```

In this demo, we haven't configured any NSG rules for the application gateway subnet. If you have a stricter configuration, you might also need to allow inbound traffic on port `53029`.

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

As you can see, we're reusing the frontend IP configuration and SSL certificate. The frontend port and SSL profile differ from the HTTPS listener.

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

To test the new changes, add the following snippet to your `.http` file. Then, try sending the requests.

```
### Test that API Management can be reached

GET https://apim-sample.dev:53029/status-0123456789abcdef


### Validates client certificate using validate-client-certificate policy

GET https://apim-sample.dev:53029/client-cert/validate-using-policy


### Validates client certificate using the context.Request.Certificate property

GET https://apim-sample.dev:53029/client-cert/validate-using-context
```

All requests will fail with a response similar to the one below. This is because we haven’t configured the Visual Studio REST Client extension to send a client certificate yet.

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

Now, if you send a request to `https://apim-sample.dev:53029/status-0123456789abcdef`, it should succeed. If you use a client certificate from another intermediate CA, such as `tst-client-01.pfx`, a `400 Bad Request` should be returned.

Despite providing a valid client certificate, the requests to `/client-cert/validate-using-policy` and `/client-cert/validate-using-context` continue to fail. Both endpoints return a `401` with the message `Client certificate missing`. The reason for the error is that the client certificate is not sent to API Management due to the application gateway terminating the TLS session. As a result, we cannot use the `validate-client-certificate` policy or the `context.Request.Certificate` property that we used in the previous post. The next section will explain how to forward the certificate to API Management for further processing.


### Forward client certificate to API Management

We can forward the provided client certificate to API Management in a header. By using a rewrite rule in the application gateway, we can access the client certificate with the `client_certificate` server variable and then place it in the header. For more information on the available server variables, see [Rewrite HTTP headers and URL with Application Gateway - Mutual authentication server variables](https://learn.microsoft.com/en-us/azure/application-gateway/rewrite-http-headers-url#mutual-authentication-server-variables).

We'll use `X-ARR-ClientCert` as the header name. This is a common name that is also used in similar scenarios. For example, Azure App Services uses this header to pass a client certificate to an app like an ASP.NET Web API. _(For more details on this scenario, see [Configure TLS mutual authentication for Azure App Service - Access client certificate](https://learn.microsoft.com/en-us/azure/app-service/app-service-web-configure-tls-mutual-auth?tabs=azurecli#access-client-certificate)._)

The figure below shows the rewrite rule to add. As you can see, it will be linked to the routing rule of the mTLS listener.

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

To link the rewrite rule to the routing rule, locate the `apim-mtls-routing-rule` routing rule and add a reference to the new `mtls-rewrite-rules` rewrite rule set. Add the following Bicep to its `properties` section:

```bicep
rewriteRuleSet: {
  id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', applicationGatewayName, 'mtls-rewrite-rules')
}
```

To test whether the client certificate is forwarded to API Management, we'll add a new operation to our API. First, create a file called `validate-from-agw.operation.cshtml` and add the following policies. This will return a `200 OK` response with the forwarded client certificate in the response body. If no client certificate is forwarded, the text `No client certificate passed` is returned.

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

Add the following Bicep so the new operation is deployed within the existing `clientCertApi` API.

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

After deploying the changes, execute the following request to test the newly added operation.

```
### mTLS (should return the X-ARR-ClientCert header value and certificate details)

GET https://apim-sample.dev:53029/client-cert/validate-from-agw
```

The result should be a `200 OK` response, with the response body resembling the following snippet:

```
HTTP/1.1 200 OK

-----BEGIN%20CERTIFICATE-----%0AMIIDRTCCAi.....TRUNCATED.....6Zdlr9V53Q%3D%3D%0A-----END%20CERTIFICATE-----%0A
```

The response body contains the value of the `X-ARR-ClientCert` header. The value is the `Base-64 encoded X.509 (.CER)` representation of the client certificate, which includes the public part of the client certificate without the private key. Special characters, such as whitespaces, are encoded.

### Validate client certificate in API Management

The application gateway already performs a first check to verify that the client certificate is issued by the correct issuer. Further processing of the client certificate can be done within API Management using a policy expression.

To verify the client certificate and ensure it matches one of the uploaded client certificates, open to the file `validate-from-agw.operation.cshtml` and update the `inbound` section with the following XML:

```csharp
<inbound>
  <base />
  <choose>
    <when condition="@{
      var clientCertHeader = context.Request.Headers.GetValueOrDefault("X-ARR-ClientCert");

      // Return false if the certificate was not forwarded in the header
      if (string.IsNullOrWhiteSpace(clientCertHeader))
      {
          return false;
      }

      // Decode the header value (e.g. replace %20 with a whitespace) and remove the begin and end certificate markers.
      // The result is the base64 encoded certificate in X.509 (.cer) format without the private key.
      var pem = System.Net.WebUtility.UrlDecode(clientCertHeader)
                                     .Replace("-----BEGIN CERTIFICATE-----", "")
                                     .Replace("-----END CERTIFICATE-----", "");

      // Convert the base64 encoded certificate to a byte[] and create an X509Certificate2 instance
      var certificate = new X509Certificate2(Convert.FromBase64String(pem));

      // Check that the certificate is valid and matches one of the uploaded client certificates
      return certificate.VerifyNoRevocation() &&
             context.Deployment.Certificates.Any(c => c.Value.Thumbprint == certificate.Thumbprint);
    }">
      <return-response>
        <set-status code="200" />
        <set-body>@(context.Request.Headers.GetValueOrDefault("X-ARR-ClientCert"))</set-body>
      </return-response>
    </when>
    <otherwise>
      <return-response>
        <set-status code="401" reason="Invalid client certificate" />
      </return-response>
    </otherwise>
  </choose>
</inbound>
```

The policy expression in the `when` condition validates the client certificate. When the condition evaluates to true, a `200 OK` is returned, otherwise a `401 Unauthorized` is returned. The policy expression executes the following steps:

1. Store the value of the `X-ARR-ClientCert` header in a variable.
1. Return `false` when the header is empty.
1. If the header is not empty:
   1. Decode the string to replace characters like `%20` with whitespace.
   1. Remove the `-----BEGIN CERTIFICATE-----` and `-----END CERTIFICATE-----` markers.
   1. Convert the resulting string into a `byte[]` array and instantiate the [X509Certificate2](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.x509certificates.x509certificate2?view=net-8.0) class. 
   1. Verify the certificate and check if it matches any of the deployed client certificates.  

Since the `X509Certificate2` class is the same type as `context.Request.Certificate`, we can perform the same checks as shown in [the previous post](/blog/2024/02/02/validate-client-certificates-in-api-management/#validate-against-uploaded-client-certificates).


After deploying these changes, you can send a request to `/validate-from-agw` again to test the result.

```
### mTLS (should return the X-ARR-ClientCert header value and certificate details)

GET https://apim-sample.dev:53029/client-cert/validate-from-agw
```

If you have configured `dev-client-01.pfx` as the client certificate, you should receive a `200 OK` response because this certificate has been uploaded into the API Management client certificate store. However, when calling `/validate-from-agw` with the other development client certificate, `dev-client-02.pfx`, a `401` response with reason `Invalid client certificate` should be returned.

Additionally, the HTTPS listener on port `443` does not forward a client certificate. So, sending a request to `/validate-from-agw` on that listener will also result in `401` response. You can use the following request to test this:

```
### Should fail because no client certificate is passed

GET https://apim-sample.dev/client-cert/validate-from-agw
```

The operation returns the same response whether no certificate is supplied or an invalid client certificate is provided. A more comprehensive example can be found [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/api-management/validate-from-agw.operation.cshtml).


### Plugging the security hole

You may have noticed that a security vulnerability has been introduced. The `/validate-from-agw` operation relies on the presence of the `X-ARR-ClientCert` header to verify if a valid client certificate is provided. However, since it's a string in a header, an attacker could potentially exploit this by calling the HTTPS listener and provide a valid value for the `X-ARR-ClientCert` header. See the example request below.

```
### Fake a client certificate

GET https://apim-sample.dev/client-cert/validate-from-agw
X-ARR-ClientCert: -----BEGIN%20CERTIFICATE-----%0AMIIDRzCCAi%2BgAwIBAgIQGbcu6oSk1L1IwgiS5l0LkjANBgkqhkiG9w0BAQsFADAq%0AMSgwJgYDVQQDDB9BUElNIFNhbXBsZSBERVYgSW50ZXJtZWRpYXRlIENBMCAXDTI0%0AMDIwMjA4Mzk0M1oYDzIwNzQwMjAyMDg0OTQzWjAUMRIwEAYDVQQDDAlDbGllbnQg%0AMDEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDD7RihwDgTSI6NMvpG%0AUexk0YVzP43JXk5aJV4MlhijvqpypH%2FmBOci1Z%2F47TbrMk97UA3dDmkGuHxLMq8b%0AYjlmV2ZydXYq5PEZt07S%2FAz81qv0rxdvpJ%2Fo9Smwd82D63bVU4bxZN0oPLztcYjr%0AgoO6Xi1CtOO48cihC9VCcYJ0qmlu8IkXuGjbxuan34M9xgxUPR6%2FLggo%2BLO5rJiw%0AxZPtCv7Jnp0pp4ecDqo8ogUPj5u3Ju%2F54YO345rlGa8dcVCFZc%2Brxh19k2gUO2I2%0AgJxvxoGeQIoKnHwOR7%2BWOtcu2efzfM5LSgDKEj%2Fn7KUFAfC4qF6f78fvKCRCCfFD%0AUOm9AgMBAAGjfTB7MA4GA1UdDwEB%2FwQEAwIFoDAUBgNVHREEDTALgglDbGllbnQg%0AMDEwEwYDVR0lBAwwCgYIKwYBBQUHAwIwHwYDVR0jBBgwFoAUZL3oNXFrhkEdOq89%0AyRqgopB9oRswHQYDVR0OBBYEFMW457L8H%2FVvN12Gvsf58NqYcRYBMA0GCSqGSIb3%0ADQEBCwUAA4IBAQBcbUKU6mr7f0Eh%2BfXXB2EC%2B8%2BgzEvqy1%2F6rQJ1%2FiUWJ4Li9fzp%0AJzuEXi3H1MTIu3%2B9IAGHOvfEg%2BVvV5fezL6pOSk%2F0LTDv8XN0iJZH6Shqbqq7Xrn%0A8vT3gTPPN1dnfOxtgTnZyvABtO3Hkh8Zsg9Gdo4LL8M8IIrIayX7pGubeYcylV9W%0ASncfONgRKC2wWgoWjJ1dXwlpsb6ZY%2BlMqCfMA0xTdqPM3p3YxggqIYbvRnwA7qId%0A8kEuhbNW7IPNZwEG%2BB9MuweeuWYiEn7r7strODwlX%2FuuYXcc0N889fnlbw9%2FC2Sm%0AmxGt6Nou8lhYYpNSxKvU1oXpa%2Fp8wnh3CXNA%0A-----END%20CERTIFICATE-----%0A
```

If you send this request, you'll receive a `200 OK` response, despite no mTLS connection being established with the application gateway. _(Replace the header value with your own if you're using other client certificates.)_

There are several ways to address this issue:
1. If mTLS is required for all communication, configuring only an mTLS listener on the application gateway is the logical option. 
1. Another approach is removing the `X-ARR-ClientCert` header from requests sent to the HTTPS listener, ensuring that only the mTLS listener will send the header to API Management. This is the solution we'll implement.

For both approaches, it's crucial to ensure that API Management is exclusively accessible through the application gateway, with direct access being restricted. If there's a need to support direct access as well, the ideal approach would involve the application gateway authenticating itself to API Management using, for example, its own client certificate and only relying solely on the `X-ARR-ClientCert` header in that scenario. However, as previously mentioned, this is currently [not possible](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-faq#is-mutual-authentication-available-between-application-gateway-and-its-backend-pools).   

As an alternative, consider adding multiple hostnames to API Management. Assign one hostname for exclusive access from the application gateway, while another can be used for other types of communication. Then, determine the authentication mechanism based on the hostname on which the request was received. Implementing this solution is beyond the scope of this post.

To remove the `X-ARR-ClientCert` header from requests sent to the HTTPS listener, we'll introduce another rewrite rule. See the figure below.

![](../../../../../images/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw/diagrams-app-gateway-https-and-mtls-listener-3.png)

Add the following Bicep to the `rewriteRuleSets` array of the application gateway:

```bicep
{
  name: 'default-rewrite-rules'
  properties: {
    rewriteRules: [
      {
        ruleSequence: 100
        conditions: []
        name: 'Remove X-ARR-ClientCert HTTP header'
        actionSet: {
          requestHeaderConfigurations: [
            // We need to remove the client certificate header from the default listener,
            // to prevent clients from tricking APIM into thinking a successful mTLS connection was established.
            {
              headerName: 'X-ARR-ClientCert'
              headerValue: ''
            }
          ]
          responseHeaderConfigurations: []
        }
      }
    ]
  }
}
```

To link the rewrite rule to the routing rule, locate the `apim-https-routing-rule` routing rule and add a reference to the new `default-rewrite-rules` rewrite rule set. Add the following Bicep to its `properties` section:

```bicep
rewriteRuleSet: {
  id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', applicationGatewayName, 'default-rewrite-rules')
}
```

After deployment, execute the following request again. It should now result in a `401 Unauthorized` response.

```
### Fake a client certificate

GET https://apim-sample.dev/client-cert/validate-from-agw
X-ARR-ClientCert: -----BEGIN%20CERTIFICATE-----%0AMIIDRzCCAi%2BgAwIBAgIQGbcu6oSk1L1IwgiS5l0LkjANBgkqhkiG9w0BAQsFADAq%0AMSgwJgYDVQQDDB9BUElNIFNhbXBsZSBERVYgSW50ZXJtZWRpYXRlIENBMCAXDTI0%0AMDIwMjA4Mzk0M1oYDzIwNzQwMjAyMDg0OTQzWjAUMRIwEAYDVQQDDAlDbGllbnQg%0AMDEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDD7RihwDgTSI6NMvpG%0AUexk0YVzP43JXk5aJV4MlhijvqpypH%2FmBOci1Z%2F47TbrMk97UA3dDmkGuHxLMq8b%0AYjlmV2ZydXYq5PEZt07S%2FAz81qv0rxdvpJ%2Fo9Smwd82D63bVU4bxZN0oPLztcYjr%0AgoO6Xi1CtOO48cihC9VCcYJ0qmlu8IkXuGjbxuan34M9xgxUPR6%2FLggo%2BLO5rJiw%0AxZPtCv7Jnp0pp4ecDqo8ogUPj5u3Ju%2F54YO345rlGa8dcVCFZc%2Brxh19k2gUO2I2%0AgJxvxoGeQIoKnHwOR7%2BWOtcu2efzfM5LSgDKEj%2Fn7KUFAfC4qF6f78fvKCRCCfFD%0AUOm9AgMBAAGjfTB7MA4GA1UdDwEB%2FwQEAwIFoDAUBgNVHREEDTALgglDbGllbnQg%0AMDEwEwYDVR0lBAwwCgYIKwYBBQUHAwIwHwYDVR0jBBgwFoAUZL3oNXFrhkEdOq89%0AyRqgopB9oRswHQYDVR0OBBYEFMW457L8H%2FVvN12Gvsf58NqYcRYBMA0GCSqGSIb3%0ADQEBCwUAA4IBAQBcbUKU6mr7f0Eh%2BfXXB2EC%2B8%2BgzEvqy1%2F6rQJ1%2FiUWJ4Li9fzp%0AJzuEXi3H1MTIu3%2B9IAGHOvfEg%2BVvV5fezL6pOSk%2F0LTDv8XN0iJZH6Shqbqq7Xrn%0A8vT3gTPPN1dnfOxtgTnZyvABtO3Hkh8Zsg9Gdo4LL8M8IIrIayX7pGubeYcylV9W%0ASncfONgRKC2wWgoWjJ1dXwlpsb6ZY%2BlMqCfMA0xTdqPM3p3YxggqIYbvRnwA7qId%0A8kEuhbNW7IPNZwEG%2BB9MuweeuWYiEn7r7strODwlX%2FuuYXcc0N889fnlbw9%2FC2Sm%0AmxGt6Nou8lhYYpNSxKvU1oXpa%2Fp8wnh3CXNA%0A-----END%20CERTIFICATE-----%0A
```

With this, the security vulnerability has been addressed.


### Conclusion

In this post, we've explored the impact of validating a client certificate in API Management when it's behind an application gateway. There's quite a bit more involved than simply establishing an mTLS connection with API Management directly. Personally, I found the application gateway configuration to be rather complex at first, so I hope this post will give you a solid start.

The final result of this blog post can be found [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/02-validate-client-certificate-in-apim-behind-agw). I've divided the `main.bicep` file into several modules to improve readability.

**Final remark**

If you deploy this solution to an Azure subscription with limited credits, take note that the application gateway is not cheap. It's best to remove everything after you're done.  If you want to keep the solution around a little longer, you can stop the application gateway, which stops the billing.

To stop the application gateway, use the following Azure CLI command:

```powershell
az network application-gateway stop --name 'agw-validate-client-certificate' --resource-group '<your-resource-group>'
```

To start the application gateway again, use the following Azure CLI command:

```powershell
az network application-gateway start --name 'agw-validate-client-certificate' --resource-group '<your-resource-group>'
```
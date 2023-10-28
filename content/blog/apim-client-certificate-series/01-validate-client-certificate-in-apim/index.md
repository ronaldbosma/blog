---
title: "Validate client certificates in API Management"
date: 2023-10-27T00:00:00+02:00
publishdate: 2023-10-27T00:00:00+02:00
lastmod: 2023-10-27T00:00:00+02:00
tags: [ "Azure", "API Management", "Bicep", "Client Certificates", "Infra as Code", "Security" ]
summary: "This blog post is the start of a series on how to work with client certificates in Azure API Management. While Azure's official documentation provides excellent guidance on setting up client certificates via the Azure Portal, we'll dive into utilizing Bicep and the Azure CLI, to automate the entire deployment process. In this first post, we'll cover the basics of how to validate client certificates in API Management."
draft: true
---

This blog post is the start of a series on how to work with client certificates in Azure API Management. In the series, I'll cover both the validation of client certificates in API Management and how to connect to backends using client certificates. 

While Azure's official documentation provides excellent guidance on setting up client certificates via the Azure Portal, this series takes it a step further. We'll dive into utilizing Bicep and other essential tools, like the Azure CLI, to automate the entire deployment process.

Topics covered in this series:

- Validate client certificates in API Management
- Validate client certificates in API Management when its behind an Application Gateway
- Connection to backends using client certificates
- Deploying client certificates in Key Vault with Azure Pipeline 1/2
- Deploying client certificates in Key Vault with Azure Pipeline 2/2

### Intro

In this first post, we'll cover the basics of how to validate client certificates in API Management. We'll deploy both API Management and an API using Bicep. We'll also have a look at how to upload CA certificates and client certificates. in API Management.

This post provides a step by step guide. If you're interested in the end result, you can find it [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/01-validate-client-certificate-in-apim).

If you want to know how to configure all of this through the Azure Portal, have a look at [How to secure APIs using client certificate authentication in API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-mutual-certificates-for-clients).

### Prerequisites

This first section will cover the prerequisites required before we can start validating client certificates in API Management.

#### Self-signed certificates

First things first. We need some certificates. In this demo we'll be using self-signed certificates, but you can also use client certificates from a public CA.

Using [Generate and export certificates for point-to-site using PowerShell](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-certificates-point-to-site) as a guide, I've created the following tree of certificates.

![Self-signed certificates](../../../../static/images/apim-client-certificate-series/self-signed-certificates.png)  
![Self-signed certificates](../../../../../images/apim-client-certificate-series/self-signed-certificates.png)

As you can see, we have one root CA certificate. Underneath it are two intermediate CA certificates that represent a development and test environment. Finally, we have two client certificates for each environment.

I've created the script [generate-client-certificates.ps](https://github.com/ronaldbosma/blog-code-examples/blob/master/apim-client-certificate-series/00-self-signed-certificates/generate-client-certificates.ps1) to generate this certificate tree using PowerShell. It also exports all certificates in base64 encoded X.509 (.cer) files and additionally exports the client certificates with their private keys in PFX (.pfx) files. The results can be found in [this](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/00-self-signed-certificates/certificates) folder.

#### Deploy API Management

Next, we need an API Management instance. We'll be deploying everything using Bicep and the Azure CLI. The following script contains the bare minimum to create an API Management instance using Bicep.

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

As you can see, we're creating a Developer tier API Management instance. Normally for demos I'd use the Consumption tier because it's cheap and rolled out quickly. However, the Consumption tier does not support CA certificates, which we'll need later on.

Save the Bicep in a file called `main.bicep`. Then, use the following command to deploy the API Management instance. Replace the `<placeholders>` with your values. The deployment will take a while to complete (about ~30 minutes).

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

#### Deploy API

Once the API Management instance is deployed, we can create an API. The following Bicep creates an API called `client-cert-api` with two operations. Add it to the end of the `main.bicep`.

```bicep
// Client Cert API
resource clientCertApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  name: 'client-cert-api'
  parent: apiManagementService
  properties: {
    displayName: 'Client Cert API'
    path: 'client-cert'
    protocols: [ 
      'https' 
    ]
    subscriptionRequired: false
  }
}


// Operation to validate client certificate using validate-client-certificate policy
resource validateUsingPolicy 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = {
  name: 'validate-using-policy'
  parent: clientCertApi
  properties: {
    displayName: 'Validate (using policy)'
    description: 'Validates client certificate using validate-client-certificate policy'
    method: 'GET'
    urlTemplate: '/validate-using-policy'
  }

  resource policies 'policies' = {
    name: 'policy'
    properties: {
      format: 'rawxml'
      value: loadTextContent('./validate-using-policy.operation.cshtml') 
    }
  }
}


// Operation to validate client certificate using context.Request.Certificate property
resource validateUsingContext 'Microsoft.ApiManagement/service/apis/operations@2022-08-01' = {
  name: 'validate-using-context'
  parent: clientCertApi
  properties: {
    displayName: 'Validate (using context)'
    description: 'Validates client certificate using the context.Request.Certificate property'
    method: 'GET'
    urlTemplate: '/validate-using-context'
  }

  resource policies 'policies' = {
    name: 'policy'
    properties: {
      format: 'rawxml'
      value: loadTextContent('./validate-using-context.operation.cshtml') 
    }
  }
}
```

There are some things to take note off. First, I did not make the subscription key required to make testing the API as simple as possible. (This is not recommended for production scenarios.)

Second, both operations will load their respective policies from an XML file we'll need to create. Create two failes called `validate-using-policy.operation.cshtml` and `validate-using-context.operation.cshtml`. Add the following XML to both files.

  > The `.cshtml` extension is recognized by the [Azure API Management Extension for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-apimanagement). Among other things, this extension gives you some intellisense support on policies.

```xml
<policies>
    <inbound>
        <base />
        <return-response>
            <set-status code="200" />
            <set-body>@(context.Request.Certificate?.ToString())</set-body>
        </return-response>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <set-header name="ErrorSource" exists-action="override">
            <value>@(context.LastError.Source)</value>
        </set-header>
        <set-header name="ErrorReason" exists-action="override">
            <value>@(context.LastError.Reason)</value>
        </set-header>
        <set-header name="ErrorMessage" exists-action="override">
            <value>@(context.LastError.Message)</value>
        </set-header>
        <base />
    </on-error>
</policies>
```

We haven't configured any backend to forward requests to, so the `return-response` policy will ensures that a `200 OK` response is always returned. By using the `context.Request.Certificate?.ToString()` policy expression, it will also include any details about a provided client certificate in the response body.

Finally, in the `on-error` section, we're setting some headers to return information about the last error that occurred. This will provide additional information about why a request failed.

> In a real-world scenario, you might not want to disclose this error information to your clients. Instead, you would connect API Management to Application Insights so errors will be logged there.

Now redeploy the Bicep template using the previously provided Azure CLI command. This should take less than a minute to complete.


### Test API

After deploying the API, we can do a first test. I like to use the [REST Client extension for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=humao.rest-client). It allows me to quickly test APIs without having to leave my IDE.

> In this section I'll describe how to call the API with a client certificate using the extension. If you want to use Postman instead, you can follow the instructions in the following article: [Adding client certificates in Postman](https://learning.postman.com/docs/sending-requests/certificates/#adding-client-certificates). 
> 
> You can also call the API directly from the browser. You'll need to upload the client certificate with private key to your personal certificate store first. Then, when you browse to the full url of the API operation, you'll get a popup to select a client certificate. 

Create a file called `test.http` and add the following content. Replace `<your-api-management-instance-name>` with your API Management instance name.

```
# Configure your host name
@apimHostname = <your-api-management-instance-name>.azure-api.net

### Validates client certificate using validate-client-certificate policy
GET https://{{apimHostname}}/client-cert/validate-using-policy

### Validates client certificate using the context.Request.Certificate property
GET https://{{apimHostname}}/client-cert/validate-using-context
```

When you open the file in Visual Studio Code, you'll see a `Send Request` link above both requests. Clicking it will send the request to the API. The response will be displayed in the output window. This should be a `200 OK` with and empty response body for both operation, because we haven't configured a client certificate yet.

You can use your own certificates or download samples from [certificates](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/00-self-signed-certificates/certificates).

To use the certificates, we'll need to update the user settings in Visual Studio Code as described [here](https://github.com/Huachao/vscode-restclient#ssl-client-certificates).
- Open the  Command Palette (`Ctrl+Shift+P`) and choose `Preferences: Open User Settings (JSON)`.
- Add the following configuration to the settings file. 

  ```json
  "rest-client.certificates": {
      "<your-api-management-instance-name>.azure-api.net": {
          "pfx": "<path-to-certificates>/dev-client-01.pfx",
          "passphrase": "P@ssw0rd"
      }
  }
  ```
  
- Replace `<your-api-management-instance-name>` with your API Management instance name and `<path-to-certificates>` with the path to the folder with certificates. 
- Don't forget to change the passphrase if you're using your own certificates.
- Save the changes.

Click on the `Send Request` link again in the `test.http` file. You should now get a `200 OK` response with the details of the client certificate in the response body. It should look something like this.

```
[Subject]
  CN=Client 01

[Issuer]
  CN=APIM Sample DEV Intermediate CA

[Serial Number]
  790CE8EEE5F01997408E859972D94A9E

[Not Before]
  10/27/2023 9:05:11 AM

[Not After]
  10/27/2024 9:15:11 AM

[Thumbprint]
  5E7FC1A1F7AD302EDFBFB0B87C5AF2A299B72858
```

### Validate client certificate using policy

The first way to validate a client certificate is by using the [validate-client-certificate policy](https://learn.microsoft.com/en-us/azure/api-management/validate-client-certificate-policy). 

Open the `validate-using-policy.operation.cshtml` file and add the following policy in the `inbound` section between the `base` and `return-response` policy.

```xml
<validate-client-certificate 
    validate-revocation="false" 
    validate-trust="false" 
    validate-not-before="true" 
    validate-not-after="true" 
    ignore-error="false">
  <identities>
    <identity subject="CN=Client 01" />
  </identities>
</validate-client-certificate>
```

This policy will validate the client certificate against the provided identities. In this case, we're only allowing certificates with subject `CN=Client 01`. We're also validating that the certificate is valid at the time of the request. See [the documentation](https://learn.microsoft.com/en-us/azure/api-management/validate-client-certificate-policy) for more options.

After redeploying this change, we can retest the API. Click `Send Request` to call the `validate-using-policy` operation. It should still succeed because we're passing a valid client certificate.

Now configure a different client certificate in your user settings, for example `dev-client-02.pfx`, and call the operation again. You should get a `401 Unauthorized` response with the following details.

```
HTTP/1.1 401 Unauthorized
ErrorSource: validate-client-certificate
ErrorReason: ClientCertificateIdentityNotMatched
ErrorMessage: Certificate does not match any of allowed identities.

{
  "statusCode": 401,
  "message": "Invalid client certificate"
}
```

As you can see in the `ErrorMessage` response header, the certificate does not match any of the allowed identities. This is because we're only allowing certificates with the `CN=Client 01` subject. You can add more identities to the policy to allow more certificates.

#### Validate certificate chain

We've been using the client certificates for the development environment. If you use the test environment version (e.g. `tst-client-01.pfx`) you should get a `401 Unauthorized` response. However, a `200 OK` is returned with the current configuration, because we're not validating the certificate chain.

Locate the `validate-client-certificate` policy. Change the value of the `validate-trust` attribute to `true` and redeploy the change. Now you'll get the following `401 Unauthorized` response when calling the `validate-using-policy` operation. It indicates that the certificate chain of the client certificate could not be validated.

```
HTTP/1.1 401 Unauthorized
ErrorSource: validate-client-certificate
ErrorReason: ClientCertificateNotTrusted
ErrorMessage: A certificate chain could not be built to a trusted root authority.

{
  "statusCode": 401,
  "message": "Invalid client certificate"
}
```

You'll get this error for both the `dev-client-01.pfx` and `tst-client-01.pfx` client certificate though. We're using self-signed certificates, so to accept the dev environment certificate again, we'll need to upload the corresponding CA certificates to API Management.

Open the `main.bicep` and locate the `apiManagementService` resource. Add the following configuration to the `properties` section. This will upload the root CA certificate to the `Root` certificate store and the intermediate CA certificate to the `CertificateAuthority` certificate store.

```bicep
certificates: [
  {
    encodedCertificate: loadTextContent('./certificates/root-ca.without-markers.cer')
    storeName: 'Root'
  }
  {
    encodedCertificate: loadTextContent('./certificates/dev-intermediate-ca.without-markers.cer')
    storeName: 'CertificateAuthority'
  }
]
```

This snippet will load the certificates from the corresponding `.cer` files. If you're using your own, change the paths to the files. 

The value of the `encodedCertificate` property should be a base64 representation of the certificate without the private key. You can get this when you choose the `Base-64 encoded X.509 (.CER)` option when exporting the certificate from the Certificate Manager (Windows). The result is a file that should look like this.

```
-----BEGIN CERTIFICATE-----
MIIDCDCCAfCgAwIBAgIQTA+cOPepk41ICdLhY7AUwDANBgkqhkiG9w0BAQsFADAeMRwwGgYDVQQD
............................................................................
uLmEJRy8HbiC5HLkKWlQSmJEbXcNw3P8sEgub0/SblXOSV7gYSos
-----END CERTIFICATE-----
```

If you use this exported file directly, the deployment of API Management will fail with the following error: `Invalid parameter: The certificate's data file format associated with Intermediates must be a Base64-encoded .pfx file`. To prevent this, remove the `-----BEGIN CERTIFICATE-----` and `-----END CERTIFICATE-----` markers from the `.cer` file.

Now redeploy the Bicep template. This can take up to ~15 minutes to complete. After the deployment is finished, you can test the API again. You should now get a `200 OK` response for the `dev-client-01.pfx` client certificate. When using the `tst-client-01.pfx`, a `401 Unauthorized` response is returned.

### Validate client certificate using the context

The second option to validate a client certificate is by using the `context.Request.Certificate` property. This property contains the client certificate that was used to call the API.

Open the `validate-using-context.operation.cshtml` policy file and add the following snippet in the `inbound` section between the `base` and `return-response` policy.

```xml
<choose>
    <when condition="@(context.Request.Certificate == null || context.Request.Certificate.Subject != "CN=Client 01" || !context.Request.Certificate.VerifyNoRevocation())" >
        <return-response>
            <set-status code="401" reason="Invalid client certificate" />
        </return-response>
    </when>
</choose>
```

This snippet will check that a client certificates was provided and that it has the expected subject. It also checks the certificate chain against the CA certificates we've uploaded earlier using the `VerifyNoRevocation` operation. If you also need to check the revocation status, you can use the `Verify()` operation instead.

After deploying the change, call the `validate-using-context` operation to test the change. Try different client certificates to see the response.

#### Upload client certificate

It's also possible to check the client certificate against certificates uploaded to API Management. These can be accessed using the `context.Deployment.Certificates` property.

Open the `validate-using-context.operation.cshtml` file, locate the `choose` policy and replace it with the following snippet.

```xml
<choose>
    <when condition="@(context.Request.Certificate == null || !context.Request.Certificate.VerifyNoRevocation() || !context.Deployment.Certificates.Any(c => c.Value.Thumbprint == context.Request.Certificate.Thumbprint))" >
        <return-response>
            <set-status code="401" reason="Invalid client certificate" />
        </return-response>
    </when>
</choose>
```

This snippet will check the thumbprint of the provided client certificate against the thumbprints of the uploaded certificates.

After redeploying the change, call the `validate-using-context` operation to test the change. You should get a `401 Unauthorized` response, because we haven't uploaded any client certificates yet.

Open the `main.bicep` and add the following resource. It will upload the `dev-client-01.cer` client certificate to API Management.

```bicep
// Add client certificate for 'Dev Client 01'
resource devClient01Certificate 'Microsoft.ApiManagement/service/certificates@2022-08-01' = {
  name: 'dev-client-01'
  parent: apiManagementService
  properties: {
    data: loadTextContent('./certificates/dev-client-01.without-markers.cer')
  }
}
```

Similar to the CA certificates, the value of the `data` property should be base64 (no private key necessary). The `-----BEGIN CERTIFICATE-----` and `-----END CERTIFICATE-----` markers should be removed.

Note that we can't use the `certificates` property on the API Management resources. That property is only used for specifying CA certificates.

After redeploying the Bicep template, call the `validate-using-context` operation again. You should now get a `200 OK` response for the uploaded `dev-client-01.pfx` client certificate, but a `401 Unauthorized` response for the `dev-client-02.pfx` client certificate.

### Conclusion

In this post, we've covered the basics of how to validate client certificates in API Management. As you've seen, there are two ways to validate a client certificate. You can either use the `validate-client-certificate` policy or the `context.Request.Certificate` property.

Using Bicep in combination with the Azure CLI is a great way to automate the deployment of resources, like API Management and its APIs, to Azure. It also provides an easy way to deploy your CA and client certificates to API Management.

The end result of this blog post can be found [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/01-validate-client-certificate-in-apim).

In the next post we'll cover how to validate a client certificate in API Management when it's sitting behind an Azure Application Gateway.
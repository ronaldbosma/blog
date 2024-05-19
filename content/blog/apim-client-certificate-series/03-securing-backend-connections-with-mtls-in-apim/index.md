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

The following figure provides a full overview of the setup:

![Overview](../../../../../images/apim-client-certificate-series/03-securing-backend-connections-with-mtls-in-apim/diagrams-overview.webp)

This post provides a step by step guide. If you're interested in the end result, you can find it [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/03-securing-backend-connections-with-mtls-in-apim). If you want to know how to configure all of this through the Azure Portal, have a look at [Secure backend services using client certificate authentication in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-mutual-certificates).

### Prerequisites

The first section will cover the prerequisites for this post. You'll need:
1. A backend that requires mTLS for authentication. We'll use a Consumption tier API Management instance. The `enableClientCertificate` property needs to be set to `true` in order for mTLS to be enabled.
1. Another Consumption tier API Management instance that will act as the client and connect to the backend using a client certificate.
1. A Key Vault to store the client certificate. The API Management client instance needs access to the Key Vault using the 'Key Vaults Secrets' role.
1. Access to the Key Vault yourself to create a certificate in the Key Vault. The 'Key Vault Administrator' role will suffice.

The following diagram provides an overview of the prerequisites:

![Prerequisites](../../../../../images/apim-client-certificate-series/03-securing-backend-connections-with-mtls-in-apim/diagrams-prerequisites.webp)

You can create these resources manually, but I've created a Bicep template that will deploy all of them. You can find the Bicep template [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/03-securing-backend-connections-with-mtls-in-apim/prerequisites/prerequisites.bicep).

You can use the accompanying [deploy-prerequisites.ps1](https://github.com/ronaldbosma/blog-code-examples/tree/master/apim-client-certificate-series/03-securing-backend-connections-with-mtls-in-apim/prerequisites/deploy-prerequisites.ps1) PowerShell script to deploy the prerequisites. It uses the Azure CLI to:

1. Create the resource group if it doesn't exist.
1. Get your user id to grant you access to Key Vault. It uses the `az ad signed-in-user show` command. _(If this fails, use the `KeyVaultAdministratorId` parameter to specify your id manually.)_
1. Deploy the Bicep template.

Here's an example of how to run the script. Make sure to replace `<your-resource-group>`, `<your-apim-client-instance>`, `<your-apim-backend-instance>`, and `<your-key-vault>` with your own values.

```powershell
./deploy-prerequisites.ps1 `
    -ResourceGroupName "<your-resource-group>" `
    -ApiManagementServiceClientName "<your-apim-client-instance>" `
    -ApiManagementServiceBackendName "<your-apim-backend-instance>" `
    -KeyVaultName "<your-key-vault>"
```

The deployment will take a few minutes. After the deployment is finished, you can test the API Management instances by calling the health endpoint. Call the following URL in your browser to test the client API Management instance. It should return a 200 OK response. Replace `<your-apim-client-instance>` with your own value:

```plaintext
https://<your-apim-client-instance>.azure-api.net/internal-status-0123456789abcdef
```

For the backend API Management instance, use the following url. Replace `<your-apim-backend-instance>` with your own value:

```plaintext
https://<your-apim-backend-instance>.azure-api.net/internal-status-0123456789abcdef
```

Calling the backend API Management instance should return a 403 Forbidden response. This is because the backend requires a client certificate for authentication.

> Take note that while the default health endpoint for a Consumption tier API Management instance is `/internal-status-0123456789abcdef`, it's `/status-0123456789abcdef` for other tiers. 
> Also, if you're not using the Consumption tier, the default health endpoint will not require mTLS. Instead, you'll need to create you're own API in the backend API Management instance that requires mTLS. See the post [Validate client certificates in API Management](/blog/2024/02/02/validate-client-certificates-in-api-management/) in this series for more information.

### Add API and backend

Next, we'll call the backend API Management instance from the client API Management instance. For this, we'll need two things. First, we'll create a backend in the client API Management instance that will contain the backend configuration, like the base url of the backend. Then, we'll add an API to the client API Management instance that will forward requests to the backend. We'll apply a test driven approach and first connect to the backend using TLS. This should fail.

Start by creating a `main.bicep` file and add the following code:

```bicep
@description('The name of the API Management Service that will be the client side of the connection')
param apiManagementServiceClientName string

@description('The name of the API Management Service that will be the backend side of the connection')
param apiManagementServiceBackendName string

resource apiManagementServiceClient 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apiManagementServiceClientName
}

resource apiManagementServiceBackend 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apiManagementServiceBackendName
}
```

We're creating a reference to the existing client API Management instance so we can deploy the backend and API to it. The backend API Management instance will be used to get the url to the backend.

Next, add the following code to the `main.bicep` file to create the backend:


```bicep
resource testBackend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  name: 'test-backend'
  parent: apiManagementServiceClient
  properties: {
    url: apiManagementServiceBackend.properties.gatewayUrl
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}
```

As you can see, we're creating a backend called `test-backend`. The url is set to the gateway url of the backend API Management instance using `apiManagementServiceBackend.properties.gatewayUrl`. The `validateCertificateChain` and `validateCertificateName` TLS properties are both set to `true` so the client will validate the SSL server certificate of the backend. These are set to `false` by default.

The last step is to add the 'Backend API' to the client API Management instance. Add the following code to the `main.bicep` file:

```bicep
resource backendApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  name: 'backend-api'
  parent: apiManagementServiceClient
  properties: {
    displayName: 'Backend API'
    path: 'backend'
    protocols: [ 
      'https' 
    ]
    subscriptionRequired: false // Disable required subscription key for simplicity of the demo
  }

  // Set an API level policy so all operations use the backend
  resource policies 'policies' = {
    name: 'policy'
    properties: {
      value: '''
        <policies>
          <inbound>
            <base />
            <set-backend-service backend-id="test-backend" />
          </inbound>
          <backend><base /></backend>
          <outbound><base /></outbound>
          <on-error><base /></on-error>
        </policies>
      '''
    }
  }

  // Create a GET Backend Status operation
  resource operations 'operations' = {
    name: 'get-backend-status'
    properties: {
      displayName: 'GET Backend Status'
      method: 'GET'
      urlTemplate: '/internal-status-0123456789abcdef'
    }
  }

  dependsOn: [
    testBackend
  ]
}
```

This Bicep code creates an API called `backend-api`. I've disabled the required subscription key so it's easier to test, but this should not be done in real world scenarios if you don't have other authentication mechanism in place.

The API has a policy that sets the backend to the `test-backend` backend we created earlier. This will make sure that any request send to the API is forwarded to the backend.

We also create one operation on the API called `GET Backend Status` that will be used to test the connection to the backend. It will call the default health endpoint on the backend API Management instance because the operation's url template is `internal-status-0123456789abcdef`.

Because we're using the `test-backend` backend in the policy, we also need to add a dependency on the `testBackend` resource.

Save the `main.bicep` file and run the following command in a PowerShell prompt to deploy the resources. Make sure to replace `<your-resource-group>`, `<your-apim-client-instance>`, and `<your-apim-backend-instance>` with your own values.

```powershell
az deployment group create `
    --name "deploy-main-$(Get-Date -Format "yyyyMMdd-HHmmss")" `
    --resource-group '<your-resource-group>' `
    --template-file './main.bicep' `
    --parameters apiManagementServiceClientName='<your-apim-client-instance>' `
                 apiManagementServiceBackendName='<your-apim-client-instance>' `
    --verbose
```

After the deployment is finished, you can test the connection to the backend by calling the `GET Backend Status` operation on the `backend-api` API. You can do this by calling the following URL in your browser, replacing `<your-apim-client-instance>` with your own value:

```plaintext
https://<your-apim-client-instance>.azure-api.net/backend/internal-status-0123456789abcdef
```

The result should be a 403 Forbidden response. This is because the backend requires a client certificate for authentication. We'll add the client certificate in the next section.


### Call backend using mTLS

In this section, we'll create a client certificate in the Key Vault, create a link to the certificate in the client API Management instance, and update the backend to use the client certificate for authentication.

Lets start with the client certificate. We can use the [az keyvault certificate create](https://learn.microsoft.com/nl-nl/cli/azure/keyvault/certificate?view=azure-cli-latest#az-keyvault-certificate-create) command to create a self-signed certificate in the Key Vault. The [az keyvault certificate get-default-policy](https://learn.microsoft.com/nl-nl/cli/azure/keyvault/certificate?view=azure-cli-latest#az-keyvault-certificate-get-default-policy) command is used to get the default policy for creating a certificate. Which will suffice for this demo.

You can use the following PowerShell script to create the certificate. Make sure to replace `<your-key-vault>` with your own value.

```powershell
az keyvault certificate get-default-policy | Out-File -Encoding utf8 defaultpolicy.json
az keyvault certificate create --vault-name "<your-key-vault>" `
                               --name "generated-client-certificate" `
                               --policy `@defaultpolicy.json
```

This will create a certificate with the name `generated-client-certificate` that will be valid for 1 year by default. The private key is exportable by default, which is required to use the certificate in API Management. Also, the key type is RSA by default, which is important. We'll come back to this later on.

With the client certificate in the Key Vault, we can use it in API Management. Open your `main.bicep` file and add the following code:

```bicep
@description('The name of the Key Vault that will contain the client certificate')
@maxLength(24)
param keyVaultName string

@description('The name of the secret in the Key Vault that contains the client certificate')
param clientCertificateSecretName string = 'generated-client-certificate'

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource clientCertificateSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' existing = {
  name: clientCertificateSecretName
  parent: keyVault
}
```

We're creating a reference to the client certificate in the Key Vault using the `Microsoft.KeyVault/vaults/secrets` resource. Since the `Microsoft.KeyVault/vaults/certificates` resources does not exist, this is the only way to reference the certificate in the Key Vault. Although we've imported the client certificate as a certificate, the Key Vault will also create a secret with the same name that can be used to reference the certificate. 

The name of the client certificate in the Key Vault can be specified through the `clientCertificateSecretName` parameter. This is useful if you want to try out different types of certificates.

Next, add the following code to the `main.bicep` file to create a references to the client certificate from the client API Management instance:

```bicep
resource clientCertificate 'Microsoft.ApiManagement/service/certificates@2022-08-01' = {
  name: 'client-certificate'
  parent: apiManagementServiceClient
  properties: {
    keyVault: {
      secretIdentifier: clientCertificateSecret.properties.secretUri
    }
  }
}
```

This code creates a reference to the client certificate in the Key Vault. The `secretIdentifier` property is set to the `secretUri` of the client certificate secret in the Key Vault. This is the URI that can be used to always get the latest version of the secret.

The last step is to update the backend to use the client certificate for authentication. Replace the current `testBackend` resource with the following code:

```bicep
resource testBackend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  name: 'test-backend'
  parent: apiManagementServiceClient
  properties: {
    url: apiManagementServiceBackend.properties.gatewayUrl
    protocol: 'http'
    credentials: {
      certificateIds: [
        clientCertificate.id
      ]
    }
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}
```

We've added a `credentials` property to the backend that contains a `certificateIds` property. This property is an array containing the id of the client certificate we created earlier. This will make sure that the client certificate is used for authentication when connecting to the backend.

Save the `main.bicep` file and run the following command in a PowerShell prompt to deploy the resources. Make sure to replace `<your-resource-group>`, `<your-apim-client-instance>`, `<your-apim-backend-instance>`, and `<your-key-vault>` with your own values.

```powershell
az deployment group create `
    --name "deploy-main-$(Get-Date -Format "yyyyMMdd-HHmmss")" `
    --resource-group '<your-resource-group>' `
    --template-file './main.bicep' `
    --parameters apiManagementServiceClientName='<your-apim-client-instance>' `
                 apiManagementServiceBackendName='<your-apim-client-instance>' `
                 keyVaultName='<your-key-vault>' `
                 clientCertificateSecretName='generated-client-certificate' `
    --verbose
```

After deploying the changes, you can retest the connection to the backend by calling the `GET Backend Status` operation on the `backend-api` API. Navigate to the following URL in your browser, replacing `<your-apim-client-instance>` with your own value:

```plaintext
https://<your-apim-client-instance>.azure-api.net/backend/internal-status-0123456789abcdef
```

Instead of a 403 Forbidden response, you should now receive a 200 OK response, because the backend is called using a valid client certificate.

> Note that at the moment, any client certificate will be accepted by the backend. This is because we're not validating the client certificate in the backend API Management instance. How to do this was covered in the first and second posts of this series. You can find them [here](/blog/2024/02/02/validate-client-certificates-in-api-management/) and [here](/blog/2024/02/19/validate-client-certificates-in-api-management-when-its-behind-an-application-gateway/).

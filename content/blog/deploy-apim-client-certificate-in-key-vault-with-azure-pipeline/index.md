---
title: "Deploy API Management Client Certificate in Key Vault with Azure Pipeline"
date: 2023-07-08T00:00:00+02:00
publishdate: 2023-07-08T00:00:00+02:00
lastmod: 2023-07-08T00:00:00+02:00
tags: [ "Azure", "Azure CLI", "Azure DevOps", "Azure Pipeline", "API Management", "Bicep", "Continuous Integration", "Infra as Code", "Key Vault" ]
summary: "Azure API Management is a powerful service that enables you to expose, secure, and manage APIs. In some scenarios, you may need to connect to a backend system that is secured with mTLS (mutual Transport Layer Security). This blog post will guide you through the process of creating an Azure Pipeline that imports a client certificate into Azure Key Vault and use it in Azure API Management."
draft: true
---

Azure API Management is a powerful service that enables you to expose, secure, and manage APIs. In some scenarios, you may need to connect to a backend system that is secured with mTLS (mutual Transport Layer Security). On [Secure backend services using client certificate authentication in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-mutual-certificates) Microsoft already gives a good explanation on how to configure mTLS in Azure API Management. This blog post will guide you through the process of creating an Azure Pipeline that the steps for you.

In this post I've chosen to store the original client certificate in Azure DevOps. This can be useful when you don't have the necessary permissions to import the certificate into the Key Vault. If you have already imported the client certificate in Key Vault, you can skip some of the steps, which I'll explain later.

- [Prerequisites](#prerequisites)
- [Azure Pipeline](#azure-pipeline)
    - [Download Secure File](#download-secure-file)
    - [Import Client Certificate](#import-client-certificate)
    - [Use Client Certificate in API Management](#use-client-certificate-in-api-management)

>TODO: add rest to table of contents

### Prerequisites

For this solution to work, you'll need an Azure API Management instance and a Key Vault. You can give API Management access to the Key Vault by enabling RBAC Authorization and assigning the API Management identity the [Key Vault Secrets User](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#key-vault-secrets-user) role. See [Secure backend services using client certificate authentication in Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-mutual-certificates) for a detailed explanation.

I've created a Bicep script that creates the required prerequisites and a PowerShell script to deploy them. You can find them [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/deploy-apim-client-certificate-in-key-vault-with-azure-pipeline/prerequisites/README.md).

You'll also need a client certificate to use in API Management. You can use your own or use the self-signed certificate [my-sample-client-certificate.pfx](https://github.com/ronaldbosma/blog-code-examples/blob/master/deploy-apim-client-certificate-in-key-vault-with-azure-pipeline/client-certificates/README.md) that I'm using. The password is `MyPassword`.

### Azure Pipeline

This post assumes you have experience creating Azure Pipelines. If not, have a look at [Create your first pipeline](https://learn.microsoft.com/en-us/azure/devops/pipelines/create-first-pipeline?view=azure-devops&tabs=java%2Ctfs-2018-2%2Cbrowser) first.

Let's start with a couple of variables that we'll use throughout the pipeline. Create an `azure-pipelines.yaml` file and add the follow Bicep. Replace the placeholders with your own values.

```yaml
trigger: none

jobs:
- job: deploy
  variables:
    azureServiceConnection: '<your-azure-service-connection>'
    resourceGroupName: '<your-resource-group-name>'
    keyVaultName: '<your-key-vault-name>'
    clientCertificateName: '<your-client-certificate-name>'
    clientCertificatePassword: '<your-client-certificate-password>' # Should be a secret variable in a real world scenario
    apiManagementServiceName: '<your-api-management-service-name>'
```

The `clientCertificateName` variable will be used as the name of the certificate in Key Vault. Don't use the `.pfx` extension of the certificate file name, because this will result in an error.

The `clientCertificatePassword` variable will be used to import the certificate with its private key. Normally this would be a secret in e.g. a variable group, but for the sake of this example, I've put it directly in the pipeline.

If you already have a client certificate in Key Vault, you can skip the next two steps an go directly to [Use Client Certificate in API Management](#use-client-certificate-in-api-management).

#### Download Secure File

The client certificate has a private key that needs to be protected. We can protect it by storing the certificate in the Secure files library of Azure DevOps. Secure files are encrypted and can only be used in a pipeline by referencing them in a task. See [Secure files](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/secure-files?view=azure-devops&tabs=yaml) for more information.

Click on the Library menu item under Pipelines and open the Secure files tab. Upload your certificate. The result should look like the following image:

![Secure Files - Client Certificate](../../../../../images/deploy-apim-client-certificate-in-key-vault-with-azure-pipeline/secure-files-client-certificate.png)

You'll also need to give your pipeline permission to access the secure file. Follow these steps:

1. Open the Secure file you just uploaded.
1. Click the 'Pipeline permissions' button.
1. Add your pipeline.

In the pipeline, we can access the secure file using the [DownloadSecureFile](https://docs.microsoft.com/en-us/azure/devops/pipelines/tasks/utility/download-secure-file?view=azure-devops) task. The task will download the certificate in the `$(Agent.TempDirectory)` directory. See the example below:

```yaml
- task: DownloadSecureFile@1
  name: clientCertificate
  displayName: 'Download Client Certificate from Secure files library'
  inputs:
    secureFile: 'my-sample-client-certificate.pfx'
```

We can access the path to the downloaded secure file in subsequent steps using the `$(clientCertificate.secureFilePath)` variable. Where `clientCertificate` is the name of the `DownloadSecureFile` task. 

#### Import Client Certificate

Now that we've stored the client certificate in the Secure files library, we can import it into Key Vault. Since I use Bicep to create most of my Azure resources, I wanted to import the client certificate using Bicep. Unfortunately, Bicep only supports adding secrets and keys to Key Vault, not certificates. We can however use the Azure CLI or PowerShell as described on [Tutorial: Import a certificate in Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/certificates/tutorial-import-certificate?tabs=azure-cli).

Using the [az keyvault certificate import](https://learn.microsoft.com/nl-nl/cli/azure/keyvault/certificate?view=azure-cli-latest#az-keyvault-certificate-import) command in combination with the [AzureCLI](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/azure-cli-v2?view=azure-pipelines) task, we can import the certificate. See the example below:

```yaml
- task: AzureCLI@2
  displayName: "Import Client Certificate into Key Vault"
  inputs:
    azureSubscription: '${{ variables.azureServiceConnection }}'
    scriptType: 'pscore'
    scriptLocation: 'inlineScript'
    inlineScript: |
    az keyvault certificate import `
        --file '$(clientCertificate.secureFilePath)' `
        --vault-name '$(keyVaultName)' `
        --name '$(clientCertificateName)' `
        --password '$(clientCertificatePassword)'
```

It's important to note that when you import a certificate, an addressable key and secret are also created with the same name. If you try to import a new certificate with the same name as an existing secret, you'll get an error. See [About Azure Key Vault certificates](https://learn.microsoft.com/en-us/azure/key-vault/certificates/about-certificates) for more information.

If you execute the pipeline now, you might get the following error:

```
Code: Forbidden
Message: Caller is not authorized to perform action on resource.
If role assignments, deny assignments or role definitions were changed recently, please observe propagation time.
Caller: appid=***;oid=<your-service-connection-principal-id>;iss=https://sts.windows.net/<your-azure-tenant-id>/
Action: 'Microsoft.KeyVault/vaults/certificates/import/action'
Resource: '/subscriptions/<your-subscription-id>/resourcegroups/<your-resource-group-name>/providers/microsoft.keyvault/vaults/<your-key-vault-name>/certificates/<your-certificate-name>'
Assignment: (not found)
DecisionReason: 'DeniedWithNoValidRBAC' 
Vault: <your-key-vault-name>;location=<your-location>

Inner error: {
    "code": "ForbiddenByRbac"
}
```

This error message tells us that the service connection principal is not authorized to perform the action. In my case, the service connection had the [Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#contributor) role. This role does not have the data action `Import Certificate`, which is required to import a certificate.

We can fix this by assigning the service connection the built-in role [Key Vault Certificates Officer](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#key-vault-certificates-officer) (id: `a4417e6f-fecd-4de8-b567-7b0420556985`). Use the following Azure CLI command. Replace the placeholders with your own values. You can find them in the error message.

```powershell
az role assignment create `
    --role "a4417e6f-fecd-4de8-b567-7b0420556985" `
    --assignee-object-id "<your-service-connection-principal-id>" `
	--assignee-principal-type ServicePrincipal `
    --scope "/subscriptions/<your-subscription-id>/resourcegroups/<your-resource-group-name>/providers/microsoft.keyvault/vaults/<your-key-vault-name>"
```

The pipeline should now run successfully and the client certificate should be imported into Key Vault as shown below.

![Imported Client Certificate](../../../../../images/deploy-apim-client-certificate-in-key-vault-with-azure-pipeline/imported-client-certificate.png)

> If the role 'Key Vault Certificates Officer' has to much permissions for your scenario, you can create a custom role with the required permissions. See [Azure custom roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/custom-roles) for more information.

#### Use Client Certificate in API Management

Now that we've imported the client certificate in Key Vault, it's time to use it in API Management. We'll be using [Bicep](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/overview?tabs=bicep) to do the following:

- Create a certificate in API Management that references the client certificate in Key Vault.
- Create a backend that uses the certificate.
- Create an API that uses the backend.

We'll need a couple of parameters to make the Bicep script reusable. Create a `main.bicep` file and add the following snippet:

```bicep
@description('The name of the Key Vault that contains the client certificate')
param keyVaultName string

@description('The name of the client certificate in Key Vault')
param clientCertificateName string

@description('The name of the API Management Service')
param apiManagementServiceName string
```

The script assumes that the Key Vault, client certificate and API Management Service already exist. We can reference them using the `existing` keyword with the following Bicep.

```bicep
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

resource clientCertificateSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' existing = {
  name: clientCertificateName
  parent: keyVault
}

resource apiManagementService 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apiManagementServiceName
}
```

Now we can create the certificate in API Management that references the client certificate in Key Vault. We'll use the [Microsoft.ApiManagement/service/certificates](https://learn.microsoft.com/en-us/azure/templates/microsoft.apimanagement/service/certificates?pivots=deployment-language-bicep) resource type, which should not be mistaken for the `certificates` property on the API Management service resource intended for CA certificates.

The `secretUri` property of the `clientCertificateSecret` is used to create the reference to the client certificate in Key Vault.

```bicep
resource clientCertificate 'Microsoft.ApiManagement/service/certificates@2022-08-01' = {
  name: 'my-sample-client-certificate'
  parent: apiManagementService
  properties: {
    keyVault: {
      secretIdentifier: clientCertificateSecret.properties.secretUri
    }
  }
}
```

To use the certificate in an API, we create a backend and pass in the `id` of the `clientCertificate` resource we just created. 

```bicep
resource echoBackend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  name: 'echo-backend'
  parent: apiManagementService
  properties: {
    url: 'http://echoapi.cloudapp.net/api'
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

> The API http://echoapi.cloudapp.net/api that we're calling doesn't really validate the certificate, but this is not a problem for the demo.

Finally, we create an API with a POST operation. We also set an API level policy so all operations use the `echo-backend`.

```bicep
resource echoApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  name: 'echo-api'
  parent: apiManagementService
  properties: {
    displayName: 'Echo API'
    path: 'echo'
    protocols: [ 
      'https' 
    ]
  }

  // Set an API level policy so all operations use the echo-backend
  resource policies 'policies' = {
    name: 'policy'
    properties: {
      value: '<policies><inbound><base /><set-backend-service backend-id="echo-backend" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
    }
  }

  // Create a POST operation
  resource operations 'operations' = {
    name: 'post'
    properties: {
      displayName: 'Post'
      method: 'POST'
      urlTemplate: '/'
    }
  }

  dependsOn: [
    echoBackend // Depend on the backend because it's used in the policy
  ]
}
```

A full version of the `main.bicep` file can be found [here](https://github.com/ronaldbosma/blog-code-examples/blob/master/deploy-apim-client-certificate-in-key-vault-with-azure-pipeline/sample/main.bicep).

The last thing we need to do is to deploy the Bicep script from our pipeline. We can use the [AzureCLI](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/deploy/azure-cli?view=azure-devops) task to do this. See the example below. Replace `<folder-with-bicep-file>` with the path to the folder that contains `main.bicep`.

```yaml
- task: AzureCLI@2
  displayName: 'Deploy Bicep Template'
  inputs:
    azureSubscription: '${{ variables.azureServiceConnection }}'
    scriptType: 'pscore'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az deployment group create `
        --name 'apim-client-cert-sample-deployment' `
        --resource-group '$(resourceGroupName)' `
        --template-file '<folder-with-bicep-file>/main.bicep' `
        --parameters keyVaultName='$(keyVaultName)' `
                     clientCertificateName='$(clientCertificateName)' `
                     apiManagementServiceName='$(apiManagementServiceName)' `
        --verbose
```

After executing the pipeline you should have a certificate in your API Management instance like the following image.

![API Management Certificate](../../../../../images/deploy-apim-client-certificate-in-key-vault-with-azure-pipeline/apim-certificate.png)

The backend should  be configured to use the certificate as shown below.

![Backend with Client Certificate](../../../../../images/deploy-apim-client-certificate-in-key-vault-with-azure-pipeline/backend-with-client-certificate.png)

You can test the API with the Visual Studio Code [REST Client](https://marketplace.visualstudio.com/items?itemName=humao.rest-client) extension using the following request. Replace `<your-api-management-service-name>` with the name of your API Management instance and `<your-subscription-key>` a valid subscription key of your API Management instance. 

```http
POST https://<your-api-management-service-name>.azure-api.net/echo HTTP/1.1
Ocp-Apim-Subscription-Key: <your-subscription-key>

{
    "foo": "bar"
}
```

### Other stuff

#### Don't import Client Certificate if it already exists

>TODO: every import creates a new version in key vault even though the certificate is the same. Check by thumbprint if it already exists.

```powershell
$pwd = ConvertTo-SecureString -String "<your-client-certificate-password" -Force -AsPlainText
$cert = Get-PfxCertificate -FilePath .\my-sample-client-certificate.pfx -Password $pwd
$cert.Thumbprint
```

#### Pipeline Template

>TODO: describe template multi environment setup

There are a couple of things to note here. Variable groups are a great way to define environment specific variables. You can create a variable group per environment and reference it in the corresponding stage of your pipeline. However, it's not possible to link a secure file to a variable group. So if you have a different client certificate per environment, you'll have to create a separate secure file for each environment.

Also, the value of the `secureFile` input of the `DownloadSecureFile` task can not be specified by a variable.
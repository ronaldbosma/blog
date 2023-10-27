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

![Self-signed certificates](../../../../static/images/apim-client-certificate-series/self-signed-certificates.png)
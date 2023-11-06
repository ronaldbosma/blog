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
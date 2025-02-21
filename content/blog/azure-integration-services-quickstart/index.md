---
title: "Azure Integration Services Quickstart"
date: 2025-02-21T11:00:00+01:00
publishdate: 2025-02-21T11:00:00+01:00
lastmod: 2025-02-21T11:00:00+01:00
tags: [ "API Management", "Azure", "Azure Functions", "Azure Integration Services", "azd", "Bicep", "Event Hub", "Infra as Code", "Logic Apps", "Service Bus" ]
---

I've recently published a Bicep template for quickly deploying Azure Integration Services, including Azure API Management, Function App, Logic App, Service Bus and Event Hubs namespace, along with supporting resources such as Application Insights, Key Vault and Storage Account. This template is ideal for demos, testing or getting started with Azure Integration Services. It can be deployed using the Azure Developer CLI (azd) and is available on [awesome-azd](https://azure.github.io/awesome-azd/?name=Azure+Integration+Services+Quickstart) and [GitHub](https://github.com/ronaldbosma/azure-integration-services-quickstart).

The template is designed to simplify and accelerate the deployment of Azure Integration Services for:

- Demos
- Testing configurations
- Quick setups for experimentation
- CI scenarios in your pipeline

To minimize cost and reduce deployment time, the cheapest possible SKUs are used for each service. Virtual networks, application gateways and other security measures typically implemented in production scenarios are not included. Keep in mind that some resources may still incur costs, so it's a good idea to clean up when you're finished to avoid unexpected charges.

A sample application is included in the template to demonstrate how the services can be used together. It consists of an API that allows a message to be published to a Service Bus topic. A function and a workflow are triggered by the message. The function stores the message in table storage, while the workflow stores the message in blob storage. Using the API, stored messages can be retrieved. See the following diagram for an overview:

![Application Diagram](../../../../../images/azure-integration-services-quickstart/aisquick-diagrams-app.png)

See the [README](https://github.com/ronaldbosma/azure-integration-services-quickstart#readme) for more details.
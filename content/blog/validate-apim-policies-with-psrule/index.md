---
title: "Validate API Management policies with PSRule"
date: 2024-08-12T00:00:00+02:00
publishdate: 2024-08-12T00:00:00+02:00
lastmod: 2024-08-12T00:00:00+02:00
tags: [ "Azure", "API Management", "Infra as Code", "PSRule", "Test Automation" ]
draft: true
---

I've been working with Azure API Management for a while now, and one of the challenges I’ve faced is finding a reliable way to validate the XML policies I write. When working with .NET, tools like SonarQube are available for code quality checks, but these tools don’t support the kind of checks I want to perform on the policies used in Azure API Management.

After some searching, I discovered [PSRule](https://microsoft.github.io/PSRule)—a cross-platform PowerShell module to validate infrastructure as code (IaC) files and objects using PowerShell rules. It's hosted in the Microsoft Github account [here](https://github.com/microsoft/PSRule), and is also included in [Microsoft Defender for Cloud](https://learn.microsoft.com/en-us/azure/defender-for-cloud/iac-vulnerabilities#view-details-and-remediation-information-for-applied-iac-rules) as part of Template Analyzer.

In this blog post, I’ll demonstrate how to use PSRule to validate your Azure API Management policies. But fefore we start, let's start with some requirements first.

First off, we'll store our policies in separate files. This makes it easier to manage and maintain them. I commonly use the `.cshtml` file extension for these files, because it this enables IntelliSense on policies when using the [Azure API Management for VS Code](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-apimanagement) extension. So, PSRule will need to recognize these files as API Management policies.

As you might be aware, policies in API Management can be applied to different [scopes](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-policies#scopes). We'll be creating several rules, where some will apply to all scopes and others to specific scopes. Because there's nothing in the policy files to indicate the scope, we'll use the file name to determine the scope. For example, a file named `test.api.cshtml` will apply to the API scope, while a file named `test.operation.cshtml` will apply to the operation scope.

We'll create the following custom rules:
1. The inbound section should always start with a `base` policy to make sure important logic, like security checks, are applied first. This rule should apply to all levels, except for the global level and policy fragments.
1. The subscription key header (`Ocp-Apim-Subscription-Key`) should be removed in the inbound section of the global policy to prevent it from being forwarded to the backend.
1. A `set-backend-service` policy should use a backend entity (by setting the `backend-id` attribute) so the backend configuration is reusable and easier to maintain.
1. Files with the `.cshtml` extension should following the naming convention and specify the scope.
1. Files with API Management policies should have valid XML syntax.
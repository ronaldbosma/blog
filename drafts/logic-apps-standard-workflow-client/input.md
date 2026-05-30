# Logic Apps Standard Workflow Client

I've created a helpful client class in C# that can be used to determine the callback url of a workflow in Logic Apps Standard that has an HTTP trigger. 


I'm using it myself in an integration test, where the pipelien as enough permissions to retrieve the callback url/


See https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/Clients/LogicAppWorkflowClient.cs for the code.
See https://raw.githubusercontent.com/ronaldbosma/call-apim-with-managed-identity/refs/heads/main/tests/IntegrationTests/ApiManagementTests.cs for how to use it.

Explain why it's usefull and explain the code with a couple of snippets.



This will most likely be a relative small post so if a table of content doesn't make sense, don't include it.
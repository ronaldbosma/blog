---
title: "Track Availability in Application Insights using Logic App Workflow"
date: 2026-01-26T16:00:00+01:00
publishdate: 2026-01-16T09:45:00+01:00
lastmod: 2026-01-16T09:45:00+01:00
tags: [ "Azure", "Application Insights", "Azure Monitor", "Logic Apps", "Azure Integration Services" ]
series: [ "track-availability-in-app-insights" ]
summary: "I've worked with clients following a low-code first strategy where Logic Apps are preferred over .NET solutions. This post shows you how to create custom availability tests using Logic App workflows and track the results in Application Insights. This approach gives you access to all Logic App capabilities while requiring minimal code."
draft: true
---

In my [previous post](/blog/2026/01/19/track-availability-in-application-insights-using-.net/), I showed you how to create custom availability tests using .NET and Azure Functions. While that solution gives you full control over the test logic and enables complex scenarios, it requires writing and maintaining code.

I've worked with clients following a low-code first strategy where Logic Apps are preferred over high-code solutions like .NET Azure Functions. For those cases, I've created a solution where a Logic App (Standard) workflow can be used as an availability test. It still has a bit of code to track the results in Application Insights, but most logic can be created in the workflow itself, meaning you can use all the features that Logic Apps provide.

Additionally, if you already have a Logic App deployed you don't have to deploy additional resources like a Function App and App Service Plan (depending on your hosting model and tier), which could increase costs.

This is the third post in a series about tracking availability in Application Insights:

- [Track Availability in Application Insights using Standard Test](/blog/2026/01/12/track-availability-in-application-insights-using-standard-test/)
- [Track Availability in Application Insights using .NET (Azure Function)](/blog/2026/01/19/track-availability-in-application-insights-using-.net/)
- **Track Availability in Application Insights using Logic App Workflow - _this post_**

### Table of Contents

- [Solution Overview](#solution-overview)
- [Backend Availability Test Workflow](#backend-availability-test-workflow)
- [Custom Functions for Tracking Availability](#custom-functions-for-tracking-availability)
- [SSL Certificate Validation Workflow](#ssl-certificate-validation-workflow)
- [SSL Certificate Function](#ssl-certificate-function)
- [Viewing Availability Test Results](#viewing-availability-test-results)
- [Setting Up Alerts](#setting-up-alerts)
- [Considerations](#considerations)
- [Conclusion](#conclusion)

## Solution Overview

The solution includes the following components:

![Overview](../../../../../images/track-availability-in-app-insights-series/track-availability-in-app-insights-using-logic-app-workflow/diagrams-overview-logic-app-workflow.png)

- **Logic App (Standard) workflow**: Timer-triggered workflow that executes the availability test and tracks the result in Application Insights using custom functions
- **API**: Represents a backend system for which we want to track availability. It randomly returns a 200 OK or 503 Service Unavailable response based on a configurable 'approximate failure percentage'
- **Application Insights**: Receives the custom availability telemetry and shows the test results

While this example uses an API on API Management, the same approach applies when calling any other backend system for which you want to track availability. You can also use other Logic App connectors besides HTTP, like calling a function in SAP using a SAP-specific connector.

To make deployment easier, I've created an Azure Developer CLI (`azd`) template: [Track Availability in Application Insights](https://github.com/ronaldbosma/track-availability-in-app-insights). The template demonstrates three scenarios for tracking availability: standard test (webtest), .NET Azure Function and Logic App workflow. If you want to deploy and try the solution, check out the [getting started section](https://github.com/ronaldbosma/track-availability-in-app-insights#getting-started) for the prerequisites and deployment instructions. This post focuses on the Logic App implementation.

## Backend Availability Test Workflow

The first workflow performs a simple HTTP GET request to check if the backend API is available. Here's what the workflow looks like in the designer:

![Logic App Workflow - Backend Status](../../../../../images/track-availability-in-app-insights-series/track-availability-in-app-insights-using-logic-app-workflow/logic-app-workflow-backend-status.png)

The workflow is structured as follows:

- **Recurrence trigger**: Executes the workflow every minute
- **Initialize TestName**: Sets a variable with the test name that will be used when tracking availability
- **Start time**: Captures the current timestamp to track the test duration
- **HTTP action**: Makes a GET request to the `/backend/status` endpoint in API Management
- **Conditional branching**: Depending on the response status code:
  - If successful (200 OK), the `Track is available (in App Insights)` action is called
  - If failed (any other status), the `Track is unavailable (in App Insights)` action is called

This workflow demonstrates the key advantage of using Logic Apps: most of the logic is visual and doesn't require coding. You can easily modify the HTTP request, add authentication, or include additional steps using the workflow designer.

## Custom Functions for Tracking Availability

The logic to track availability in Application Insights is implemented in C# using a [Logic App with custom code project](https://learn.microsoft.com/en-us/azure/logic-apps/create-run-custom-code-functions). I've created functions similar to what I showed in the previous post, but packaged as Logic App custom functions.

> I started on a [custom connector](https://github.com/ronaldbosma/LogicApps.ServiceProviders.ApplicationInsights.TrackAvailability), but the deploy size went from several KBs to hundreds of MBs. So I decided to use a custom code project instead. The current size is about 600KB.

The following image shows the use of the `TrackIsAvailable` function in the workflow:

![Track is available action](../../../../../images/track-availability-in-app-insights-series/track-availability-in-app-insights-using-logic-app-workflow/track-is-available-action.png)

The function takes the test name and start time as parameters and tracks a successful availability test. The `TrackIsUnavailable` function tracks a failure and takes an additional parameter for the error message.

Here's the implementation from [AvailabilityTestFunctions.cs](https://github.com/ronaldbosma/track-availability-in-app-insights/blob/main/src/logicApp/Functions/AvailabilityTestFunctions.cs):

```csharp
public class AvailabilityTestFunctions
{
	private readonly TelemetryClient _telemetryClient;
	private readonly ILogger<AvailabilityTestFunctions> _logger;

	public AvailabilityTestFunctions(TelemetryClient telemetryClient, ILoggerFactory loggerFactory)
	{
		_telemetryClient = telemetryClient;
		_logger = loggerFactory.CreateLogger<AvailabilityTestFunctions>();
	}

	[Function("TrackIsAvailable")]
	public Task TrackIsAvailable([WorkflowActionTrigger] string testName, DateTimeOffset startTime)
	{
		_logger.LogInformation("TrackIsAvailable function invoked with testName: {TestName}, startTime: {StartTime}", testName, startTime);

		return TrackAvailability(testName, true, startTime, null);
	}

	[Function("TrackIsUnavailable")]
	public Task TrackIsUnavailable([WorkflowActionTrigger] string testName, DateTimeOffset startTime, string message)
	{
		_logger.LogInformation("TrackIsUnavailable function invoked with testName: {TestName}, startTime: {StartTime}, message: {Message}", testName, startTime, message);

		return TrackAvailability(testName, false, startTime, message);
	}

	public Task TrackAvailability([WorkflowActionTrigger] string testName, bool success, DateTimeOffset startTime, string message)
	{
		ArgumentException.ThrowIfNullOrWhiteSpace(testName, nameof(testName));

		AvailabilityTelemetry availability = new()
		{
			Name = testName,
			RunLocation = Environment.GetEnvironmentVariable("REGION_NAME") ?? "Unknown",
			Success = success,
			Message = message,
			Timestamp = startTime,
			Duration = DateTimeOffset.UtcNow - startTime
		};

		// Create activity to enable distributed tracing and correlation of the telemetry in App Insights
		using (Activity activity = new("AvailabilityContext"))
		{
			activity.Start();
			
			// Connect the availability telemetry to the logging activity
			availability.Id = activity.SpanId.ToString();
			availability.Context.Operation.ParentId = activity.ParentSpanId.ToString();
			availability.Context.Operation.Id = activity.RootId;
			
			_telemetryClient.TrackAvailability(availability);
			_telemetryClient.Flush();
		}
		
		return Task.CompletedTask;
	}
}
```

The `AvailabilityTestFunctions` class provides two public functions that can be called from workflows:

- **TrackIsAvailable**: Tracks a successful availability test by calling `TrackAvailability` with `success` set to `true`
- **TrackIsUnavailable**: Tracks a failed test by calling `TrackAvailability` with `success` set to `false` and includes an error message

The `TrackAvailability` method does the actual work:
- Creates an `AvailabilityTelemetry` object with the test results including the run location (retrieved from an environment variable)
- Calculates the test duration by subtracting the start time from the current time
- Creates an `Activity` to enable distributed tracing and correlation of telemetry in Application Insights
- Sets various IDs on the availability telemetry to enable end-to-end correlation
- Publishes the telemetry to Application Insights using the `TelemetryClient`

The `TelemetryClient` is registered in the [Startup.cs](https://github.com/ronaldbosma/track-availability-in-app-insights/blob/main/src/logicApp/Functions/Startup.cs) of the Logic App's custom code project. The `ILoggerFactory` is already registered by default.

I could have created a single function that performed both the HTTP GET and tracked the (un)availability of the backend. But I decided to only put the 'track availability' code in functions to visualize the logic and so other logic can rely on the Logic App capabilities. For example, using a managed identity to call a backend is super easy in a workflow, as I describe in my post [Call OAuth-Protected APIs with Managed Identity from Logic Apps](/blog/2025/09/24/call-oauth-protected-apis-with-managed-identity-from-logic-apps/).

## SSL Certificate Validation Workflow

Similar to my previous posts, I've created a separate availability test to check the SSL server certificate of API Management. Here's what this workflow looks like in the designer:

![Logic App Workflow - SSL Certificate Check](../../../../../images/track-availability-in-app-insights-series/track-availability-in-app-insights-using-logic-app-workflow/logic-app-workflow-ssl-cert-check.png)

The workflow is structured as follows:

- **Recurrence trigger**: Executes the workflow every minute
- **Initialize TestName**: Sets a variable with the test name
- **Start time**: Captures the current timestamp
- **Get APIM SSL server certificate expiration in days**: Calls a custom function to retrieve the number of days until the certificate expires
- **Conditional branching**: Depending on the expiration days:
  - If the certificate expires soon or has expired (less than or equal to the configured threshold), the workflow:
    - Tracks the test as unavailable in Application Insights, including the number of remaining days in the error message
    - Terminates with a failed status
  - If the certificate is still valid (more than the threshold days remaining), the workflow tracks the test as available
- **Error handling**: If determining the expiry fails, the test is tracked as unavailable

The default threshold is 30 days, which means the test will fail if the certificate expires within 30 days or has already expired.

## SSL Certificate Function

The `GetSslServerCertificateExpirationInDays` function retrieves the SSL certificate and calculates how many days remain until it expires. Here's the implementation from [SslServerCertificateFunctions.cs](https://github.com/ronaldbosma/track-availability-in-app-insights/blob/main/src/logicApp/Functions/SslServerCertificateFunctions.cs):

```csharp
[Function("GetSslServerCertificateExpirationInDays")]
public async Task<int> GetSslServerCertificateExpirationInDays([WorkflowActionTrigger] string hostname, int port)
{
	_logger.LogInformation("GetSslServerCertificateExpirationInDays function invoked with hostname: {Hostname}, port: {Port}", hostname, port);
	
	try
	{
		// Connect client to remote TCP host using provided hostname and port
		using var tcpClient = new TcpClient();
		await tcpClient.ConnectAsync(hostname, port);

		// Create an SSL stream over the TCP connection and authenticate with the server
		// This will trigger the SSL/TLS handshake and allow us to access the server's certificate
		using var sslStream = new SslStream(tcpClient.GetStream());
		await sslStream.AuthenticateAsClientAsync(hostname);

		// Retrieve the remote server's SSL certificate from the authenticated connection
		var certificate = sslStream.RemoteCertificate;
		if (certificate != null)
		{
			// Calculate the remaining lifetime of the certificate in days
			var x509Certificate = new X509Certificate2(certificate);
			return (x509Certificate.NotAfter - DateTime.UtcNow).Days;
		}

		// Throw an exception if no certificate was found
		throw new Exception($"No SSL server certificate found for host {hostname} on port {port}");
	}
	catch (Exception ex)	{
		_logger.LogError(ex, "Error retrieving SSL server certificate expiration for host {Hostname} on port {Port}: {Exception}", hostname, port, ex.ToString());
		throw;
	}
}
```

The function performs the following steps:

- Connects to the remote host using a `TcpClient` with the provided hostname and port
- Creates an `SslStream` over the TCP connection to establish an SSL/TLS handshake
- Authenticates with the server using `AuthenticateAsClientAsync`, which retrieves the server's certificate
- Extracts the certificate's expiration date and calculates the remaining days until expiry
- Returns the number of days or throws an exception if the certificate couldn't be retrieved

I'm using the `TcpClient` class in this solution while I used a custom `HttpClientHandler` in the previous blog post. I could have used a similar `HttpClientHandler` solution here, or the `TcpClient` in the previous post. Both work, but the `TcpClient` solution makes it easier to retrieve the certificate expiration.

## Viewing Availability Test Results

The availability test results from Logic App workflows appear in Application Insights just like the results from standard tests and Azure Functions. You can view them in the Availability section of Application Insights:

![Availability Test Details](../../../../../images/track-availability-in-app-insights-series/track-availability-in-app-insights-using-logic-app-workflow/availability-test-details.png)

The tests are marked with a `CUSTOM` label to indicate they're not standard tests executed from Application Insights, but custom tests executed from a different location that publish their results to Application Insights.

When you drill into the details of a specific test result, you can view the end-to-end transaction details:

![End-to-end Transaction Details](../../../../../images/track-availability-in-app-insights-series/track-availability-in-app-insights-using-logic-app-workflow/logic-app-workflow-end-to-end-transaction-details.png)

The end-to-end transaction view shows the correlation between the Logic App workflow execution, the HTTP request to API Management and the availability test result. The timeline is a bit 'messy' compared to the Azure Function implementation because of the way the workflow tracks the availability result as a separate action. However, all the telemetry is properly correlated, allowing you to trace the complete flow.

Similar to the Azure Function implementation, the test only runs from a single region because it's executed from your Logic App deployment location. Standard tests can run from multiple Azure locations, but custom tests are limited to where your code runs.

## Setting Up Alerts

Setting up alerts for Logic App-based availability tests works the same as for Azure Function-based tests. You can create alerts that trigger when availability tests fail or when specific conditions are met.

Here's an example alert rule that triggers when any availability test doesn't succeed 100% of the time in the last 5 minutes:

- **Signal**: Availability (under Application Insights)
- **Aggregation type**: Average
- **Threshold**: Less than 100%
- **Evaluation frequency**: 5 minutes
- **Lookback period**: 5 minutes
- **Split by dimensions**: Test name (to get separate alerts for each test)

You can also create alerts for failed requests logged in Application Insights, or combine multiple conditions to create more sophisticated alerting rules. For more detailed information on configuring alerts, see my post on [Track Availability in Application Insights using Standard Test](/blog/2026/01/12/track-availability-in-application-insights-using-standard-test/).

## Considerations

While Logic App workflows provide a great low-code solution for availability testing, there are some considerations to keep in mind:

**Timer Trigger Configuration**: While it's easy to configure the timer trigger of an Azure Function via an app setting, this isn't supported by the Recurrence trigger of a Logic App workflow. You can't set the interval or frequency using an app setting, making it difficult to set different frequencies per environment. In dev/test you might want a lower frequency to save cost. You could put a placeholder in the `workflow.json` and add the correct interval and frequency during deployment, but that adds complexity to your deployment process.

**Reusable Workflows**: If you expect to create multiple availability tests, consider creating a generic workflow with an HTTP trigger that takes the test name and the URL to test. That workflow will perform the HTTP GET and track the availability. You can then create a simplified workflow per availability test that has the Recurrence trigger and calls the generic workflow with the correct test name and URL. I've used this in one of my own projects and it works great.

**Cost**: Logic Apps charge based on workflow executions and connector actions. If you already have a Logic App (Standard) deployed, adding availability test workflows is cost-effective. But if you need to deploy a new Logic App just for availability testing, compare the costs with Azure Functions or standard tests to determine the most economical option for your scenario.

**Single Region**: Similar to Azure Functions, Logic App-based availability tests run from a single region (where your Logic App is deployed). If you need multi-region testing, you'll need to deploy Logic Apps in multiple regions or use standard availability tests.

## Conclusion

Logic App workflows provide a compelling option for implementing custom availability tests, especially when working in organizations with a low-code first strategy. The approach combines the flexibility of custom code for tracking availability in Application Insights with the visual, low-code nature of Logic App workflows for the actual testing logic.

The key benefits include:
- Visual workflow design that's easy to understand and maintain
- Access to all Logic App connectors and capabilities
- Minimal custom code required (only for tracking availability)
- Potential cost savings if you already have a Logic App deployed
- Easy integration with other Azure services using managed identities

While there are some limitations around configuration and multi-region testing, the Logic App approach offers a practical solution for many availability testing scenarios. The generic custom functions I've shown can be reused across multiple workflows, making it straightforward to add new availability tests as needed.

For organizations committed to low-code solutions or those already using Logic Apps, this approach provides a natural way to implement custom availability monitoring without requiring extensive .NET development expertise.
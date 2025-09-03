---
title: "Converting Base64 Files to multipart/form-data with Azure API Management"
date: 2025-09-03T00:00:00+02:00
publishdate: 2025-09-03T00:00:00+02:00
lastmod: 2025-09-03T00:00:00+02:00
tags: [ "Azure", "API Management", "Azure Integration Services" ]
summary: "In this post, I'll show you how to use Azure API Management policies to transform a JSON request containing a base64-encoded file into a multipart/form-data request. This is useful when your client sends files as base64 in JSON, but your backend expects a form upload."
draft: true
---

I've been working with Azure API Management on an integration where the client sends a JSON payload containing a base64-encoded file. The backend service that processes the file expects a multipart/form-data request, which is typically used in HTML form uploads.

In this post, I'll show you how to use API Management policies to transform the base64-encoded data into a properly formatted multipart/form-data request. I'll use a .NET Azure Function as the backend, but the approach works for any service that expects form uploads.

### Table of Contents

- [Prerequisites](#prerequisites)
- [Understanding multipart/form-data in .NET](#understanding-multipartformdata-in-net)
- [Sample Azure Function for File Uploads](#sample-azure-function-for-file-uploads)
- [Testing with an HTML Form](#testing-with-an-html-form)
- [API Management: Transforming Base64 to multipart/form-data](#api-management-transforming-base64-to-multipartformdata)
- [Testing the Transformation](#testing-the-transformation)
- [Conclusion](#conclusion)

### Prerequisites

To follow along, you'll need:

- An Azure API Management (APIM) instance
- An Azure Function App (using .NET)

If you want to deploy both quickly, you can use my [Azure Integration Services Quickstart](https://github.com/ronaldbosma/azure-integration-services-quickstart) template. Set `includeApiManagement` and `includeFunctionApp` to `true` when deploying. The other parameters can be left as `false`.

### Understanding multipart/form-data in .NET

Converting a base64 string to a multipart/form-data request is straightforward in .NET using the [`MultipartFormDataContent`](https://learn.microsoft.com/en-us/dotnet/api/system.net.http.multipartformdatacontent?view=net-9.0) class. If you want to understand the structure of multipart requests, I recommend [Andrew Lock's post](https://andrewlock.net/reading-json-and-binary-data-from-multipart-form-data-sections-in-aspnetcore/). It explains how to read and construct multipart requests in ASP.NET Core.

### Sample Azure Function for File Uploads

Let's start with a simple Azure Function that accepts a file upload as multipart/form-data. This function reads the file and returns it as a download.

```csharp
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace AISQuick.FunctionApp;

/// <summary>
/// Function that retrieves a file as part of a multipart form data request and returns it as a file stream.
/// </summary>
public class ProcessFileFunction
{
	private readonly ILogger<ProcessFileFunction> _logger;

	public ProcessFileFunction(ILogger<ProcessFileFunction> logger)
	{
		_logger = logger;
	}

	[Function(nameof(ProcessFileFunction))]
	public async Task<IActionResult> Run(
		[HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "process-file")] HttpRequest request)
	{
		try
		{
			var formdata = await request.ReadFormAsync();

			string? fileId = formdata["fileId"];
			_logger.LogInformation("File ID: {FileID}", fileId);

			var file = request.Form.Files["file"];
			if (file == null)
			{
				return new BadRequestObjectResult("File not provided.");
			}

			_logger.LogInformation("File Name: {FileName}, Content Type: {ContentType}, Size: {Size} bytes",
				file.FileName, file.ContentType, file.Length);

			var stream = file.OpenReadStream();
			return new FileStreamResult(stream, file.ContentType)
			{
				FileDownloadName = file.FileName
			};
		}
		catch (Exception ex)
		{
			// If something goes wrong, return the exception details.
			// Don't do this in production code, as it can expose sensitive information.
			return new ContentResult
			{
				StatusCode = StatusCodes.Status500InternalServerError,
				Content = ex.ToString(),
				ContentType = "text/plain"
			};
		}
	}
}
```

Deploy this function to your Azure Function App.

### Testing with an HTML Form

To verify the function, you can use a simple HTML form. Download [test-form.html](https://github.com/ronaldbosma/azure-apim-samples/blob/main/convert-base64-to-multipart-formdata/test-form.html) and update the `action` attribute to point to your function app's URL (e.g., `https://<your-function-app-name>.azurewebsites.net/api/process-file`).

Open the HTML file in your browser, upload a file, and submit the form. The function will return the file as a download. You can inspect the multipart/form-data request in your browser's developer tools. If you have Application Insights enabled, you'll also see the file ID in your logs.

### API Management: Transforming Base64 to multipart/form-data

Now let's tackle the main challenge: converting a JSON request with a base64-encoded file to a multipart/form-data request in APIM.

Suppose your client sends a request like this:

```json
{
	"id": "12345",
	"name": "sample.jpg",
	"mimeType": "image/jpeg",
	"base64Content": "...BASE64_CONTENT..."
}
```

But your backend expects a multipart/form-data request. Here's what the equivalent multipart request looks like (simplified for clarity):

```
--b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec
Content-Disposition: form-data; name="fileId"

12345
--b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec
Content-Disposition: form-data; name="file"; filename="sample.jpg"
Content-Type: image/jpeg

(binary file content)
--b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec--
```

#### APIM Policy Transformation

We'll create an API in APIM with a POST operation. In the inbound policy, add the following steps:

1. **Configure the backend** (replace `<your-function-app-name>`):

	```xml
	<set-backend-service base-url="https://<your-function-app-name>.azurewebsites.net" />
	<rewrite-uri template="/api/process-file" copy-unmatched-params="false" />
	```

2. **Set the Content-Type header with a boundary**:

	```xml
	<set-header name="Content-Type" exists-action="override">
		<value>multipart/form-data; boundary=b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec</value>
	</set-header>
	```

3. **Transform the body**:

	```xml
	<set-body>@{
		// The Process File function expects a multipart/form-data request with the following parts:
		// - fileId: string           - Id of the file to be processed
		// - file:   string($binary)  - The file that is to be processed

		var request = context.Request.Body.As<JObject>();
		string id = request.Value<string>("id");
		string name = request.Value<string>("name");
		string mimeType = request.Value<string>("mimeType");

		// Convert file to binary data
		string base64Content = request.Value<string>("base64Content");
		byte[] binaryData = Convert.FromBase64String(base64Content);
        
		var formData = new List<byte>();

		// Part 1: file id
		AppendLine($"--b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec");
		AppendLine("Content-Disposition: form-data; name=\"fileId\"");
		AppendLine("");
		AppendLine(id);

		// Part 2: file metadata
		AppendLine($"--b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec");
		AppendLine($"Content-Disposition: form-data; name=\"file\"; filename=\"{name}\"");
		AppendLine($"Content-Type: {mimeType}");
		AppendLine("");

		// Part 3: file content (raw bytes, not base64)
		formData.AddRange(binaryData);
		AppendLine("");

		// End boundary
		AppendLine($"--b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec--");

		return formData.ToArray();

		// Helper methods to add strings with proper encoding
		void AppendLine(string s)
		{
			AppendString(s + "\r\n");
		}

		void AppendString(string s)
		{
			formData.AddRange(Encoding.UTF8.GetBytes(s));
		}
	}</set-body>
	```

**A few notes on the transformation:**

- The boundary (`b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec`) is used to separate parts in the multipart request. It must match the value in the `Content-Type` header.
- Each part starts with `--<boundary>`, and the final boundary ends with `--`.
- I'm using a static GUID for readability, but you can generate a unique value if you prefer. Just make sure it matches everywhere.
- The file content is added as raw binary, not as a string, to avoid corrupting the file.

### Testing the Transformation

You can test the API using a tool like [test.http](https://github.com/ronaldbosma/azure-apim-samples/blob/main/convert-base64-to-multipart-formdata/test.http). Update the URL to point to your APIM instance (replace `<your-apim-service-name>`).

Send a request with a base64-encoded file. If everything is set up correctly, you'll get the file back as a download.

If you want to validate the request size or content type, you can add a `validate-content` policy. By default, the max size is 4MB. To support larger files, set `size-exceeded-action="ignore"`.

```xml
<validate-content unspecified-content-type-action="prevent" max-size="4194304" size-exceeded-action="prevent">
	<content type="application/json" validate-as="json" action="prevent" />
</validate-content>
```

### Conclusion

Transforming a base64-encoded file in a JSON request to a multipart/form-data upload is a common integration challenge. With Azure API Management, you can handle this conversion entirely in policy, allowing your backend to work with standard form uploads.

This approach keeps your client and backend decoupled, and you can reuse the pattern for other file types or APIs. If you want to see the full sample, including the test files and policies, check out [my GitHub repository](https://github.com/ronaldbosma/azure-apim-samples/tree/main/convert-base64-to-multipart-formdata).

Let me know if you run into any issues or have suggestions for improvements!

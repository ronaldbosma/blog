---
title: "Convert Base64 to multipart/form-data with API Management"
date: 2025-09-03T17:30:00+02:00
publishdate: 2025-09-03T17:30:00+02:00
lastmod: 2025-09-03T17:30:00+02:00
tags: [ "Azure", "API Management", "Azure Integration Services" ]
summary: "In this post, I'll show you how to use Azure API Management policies to transform a JSON request containing a base64-encoded file into a multipart/form-data request. This is useful when your client sends files as base64 in JSON, but your backend expects a form upload."
draft: true
---

I've been working with Azure API Management on an integration where the client sends a JSON payload containing a base64-encoded file. The backend service that processes the file expects a multipart/form-data request, which is typically used in HTML form uploads.

In this post, I'll show you how to use API Management policies to transform the base64-encoded data into a properly formatted multipart/form-data request.

### Table of Contents

- [Prerequisites](#prerequisites)
- [Understanding multipart/form-data](#understanding-multipartform-data)
- [Creating the Backend Function](#creating-the-backend-function)
- [Testing with an HTML Form](#testing-with-an-html-form)
- [Creating the API Management Transformation](#creating-the-api-management-transformation)
- [Testing the API](#testing-the-api)
- [Conclusion](#conclusion)

### Prerequisites

To follow along with this post, you'll need:

- An Azure API Management service instance
- An Azure Function App (.NET)

If you don't have these resources yet, you can use my [Azure Integration Services Quickstart](https://github.com/ronaldbosma/azure-integration-services-quickstart) template to deploy them. See the [Getting Started](https://github.com/ronaldbosma/azure-integration-services-quickstart?tab=readme-ov-file#getting-started) section for instructions. When requested during deployment, set the `includeApiManagement` and `includeFunctionApp` parameters to `true` and the rest to `false`.

### Understanding multipart/form-data

Before diving into the implementation, it's worth understanding what multipart/form-data requests look like.

A multipart/form-data request consists of multiple sections separated by boundaries. These sections can contain form field values, files, or other data types.

When uploading a file using an HTML form like the following:

![Test HTML form](../../../../../../images/convert-base64-to-multipart-formdata-with-api-management/test-html-form.png)

The browser creates a request that includes a `Content-Type` header specifying the type as `multipart/form-data` and the boundary string:

```
Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryKWINm4cKboHb55vB
```

Here's an example of what the request body looks like:

```
------WebKitFormBoundaryKWINm4cKboHb55vB
Content-Disposition: form-data; name="fileId"

123
------WebKitFormBoundaryKWINm4cKboHb55vB
Content-Disposition: form-data; name="file"; filename="sample.jpg"
Content-Type: image/jpeg

... BINARY DATA ...
------WebKitFormBoundaryKWINm4cKboHb55vB--
```

Each section starts with a boundary (prefixed with `--`), followed by headers that describe the form field. The `Content-Disposition` header specifies the field name and, for file uploads, the filename. File sections include a `Content-Type` header that specifies the media type (like `image/jpeg`). Text fields typically don't include this header and default to `text/plain`. The actual data follows after a blank line.

For a deeper understanding of multipart/form-data requests, I recommend reading [Reading JSON and binary data from multipart/form-data sections in ASP.NET Core](https://andrewlock.net/reading-json-and-binary-data-from-multipart-form-data-sections-in-aspnetcore/) by Andrew Lock. It provides excellent examples of how to construct and handle these requests in .NET.

### Creating the Backend Function

Let's start by creating an Azure Function that can receive multipart/form-data requests. This function will extract a file from the form data and return it as a downloadable file.

```csharp
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace AISQuick.FunctionApp;

/// <summary>
/// Function that retrieves a file as part of a multipart form data request
/// and returns it as a file stream.
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
            // 1. Read the form data
            var formdata = await request.ReadFormAsync();

            // 2. Extract the file ID from the form data and log it
            string? fileId = formdata["fileId"];
            _logger.LogInformation("File ID: {FileID}", fileId);

            // 3. Extract the binary file from the form data. Throw an exception if it's not present.
            var file = request.Form.Files["file"];
            if (file == null)
            {
                return new BadRequestObjectResult("File not provided.");
            }

            // 4. Log the file details
            _logger.LogInformation("File Name: {FileName}, Content Type: {ContentType}, Size: {Size} bytes",
                file.FileName, file.ContentType, file.Length);

            // 5. Return the file as a stream.
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

This function does the following:
1. Reads the form data from the incoming request
1. Extracts the `fileId` field and logs it
1. Retrieves the uploaded file and validates it exists
1. Logs the file details
1. Returns the file as a downloadable stream

Deploy this function to your Azure Function App before proceeding to the next step.

### Testing with an HTML Form

To understand how multipart/form-data works, let's test our function with a simple HTML form. Create a new HTML file using the sample below or download the test form [here](https://github.com/ronaldbosma/azure-apim-samples/blob/main/convert-base64-to-multipart-formdata/test-form.html):

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Upload File</title>
</head>
<body>
    <form action="https://<your-function-app-name>.azurewebsites.net/api/process-file" method="post" enctype="multipart/form-data">
        <label for="fileId">File ID:</label>
        <input type="text" id="fileId" name="fileId" required>
        <br><br>
        <label for="file">Select file:</label>
        <input type="file" id="file" name="file" required>
        <br><br>
        <button type="submit">Upload</button>
    </form>
</body>
</html>
```

Update the `action` attribute in the HTML form to point to your Function App URL by replacing `<your-function-app-name>` with your actual Function App name.

Open the HTML file in your browser, enter a file ID and select a file. The form will look like this:  

![Test HTML form](../../../../../../images/convert-base64-to-multipart-formdata-with-api-management/test-html-form.png)

To see how the multipart/form-data request is structured, open your browser's developer tools before submitting the form. When you submit the form, you should see the file downloaded back to your browser. In the Network tab, you can inspect the request structure - it will look similar to the example shown in the [Understanding multipart/form-data](#understanding-multipartform-data) section.

If you have Application Insights configured, you can also check the logs to see the file ID and file details being logged by the function.

### Creating the API Management Transformation

Now let's create an API in API Management that transforms a JSON request with base64-encoded content into the multipart/form-data format our function expects.

You can create the API using this [OpenAPI specification](https://raw.githubusercontent.com/ronaldbosma/azure-apim-samples/refs/heads/main/convert-base64-to-multipart-formdata/convert-file-api.openapi.yaml). 
This will create an API called 'Convert File API' with a 'Convert a Base64-encoded file' operation. 
It expects a JSON request with the following structure:

```json
{
    "id": "12345",
    "name": "sample.jpg",
    "mimeType": "image/jpeg",
    "base64Content": "...BASE64_CONTENT..."
}
```

We'll transform that JSON request into a multipart/form-data request with these parts:
- `fileId`: The ID from the JSON
- `file`: The binary file data with proper metadata

Here's how to set up the transformation for the 'Convert a Base64-encoded file' operation. In the inbound processing section, add the following policies:

1. **Configure the backend** to forward the request to the Azure Function:

    ```xml
    <set-backend-service base-url="https://<your-function-app-name>.azurewebsites.net" />
    <rewrite-uri template="/api/process-file" copy-unmatched-params="false" />
    ```

    Replace `<your-function-app-name>` with your actual Function App name.

2. **Set the Content-Type header** to multipart/form-data with a boundary:

    ```xml
    <set-header name="Content-Type" exists-action="override">
        <value>multipart/form-data; boundary=b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec</value>
    </set-header>
    ```

3. **Transform the request body** from JSON to multipart/form-data:

    ```xml
    <set-body>@{
        // The Process File function expects a multipart/form-data request with the following parts:
        // - fileId: string           - Id of the file to be processed
        // - file:   string($binary)  - The file that is to be processed
        //
        // We're not constructing the entire request as a string where the file contents is converted using Encoding.UTF8.GetString(),
        // because that would corrupt the binary data of the file.

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

4. **Save the changes** to apply the transformation.


#### Understanding the Transformation

> TODO: add a more detailed explanation of the transformation process.

The transformation works by:

1. **Boundary usage**: The boundary `b5f36865-8df9-4d14-8d2c-4ae2eb78d0ec` is used to separate different parts of the form data. Each section starts with `--` followed by the boundary, and the final boundary is surrounded by `--` on both sides.

2. **Binary data handling**: Instead of converting the entire request to a string (which would corrupt binary data), we work with byte arrays and only convert text portions to UTF-8 bytes.

3. **Form structure**: We create two form fields:
   - `fileId`: A simple text field containing the ID
   - `file`: A file field with proper filename and content-type metadata

I'm using a static GUID for the boundary for readability, but you can generate a unique value as long as it matches between the Content-Type header and the request body.

### Testing the API

You can test the API using an HTTP client. Download the test file from my [Azure APIM samples repository](https://github.com/ronaldbosma/azure-apim-samples/blob/main/convert-base64-to-multipart-formdata/test-request.http) and replace `<your-apim-service-name>` with your API Management service name.

Execute the test request and verify that the image is returned correctly.

### Content Validation

For production use, consider adding content validation to protect against large files:

```xml
<validate-content unspecified-content-type-action="prevent" max-size="4194304" size-exceeded-action="prevent">
    <content type="application/json" validate-as="json" action="prevent" />
</validate-content>
```

This policy limits uploads to 4MB, which is the current limit for the `max-size` attribute. 
Set `size-exceeded-action` to `ignore` if you need to support larger files.

You can find the complete policy with all the transformations [here](https://github.com/ronaldbosma/azure-apim-samples/blob/main/convert-base64-to-multipart-formdata/convert-file.policy.xml).

### Conclusion

Using API Management policies, we can seamlessly transform JSON requests with base64-encoded files into multipart/form-data requests that backend services expect. This approach is particularly useful when integrating with legacy systems or third-party APIs that require specific content types.

The key benefits of this approach include:
- No code changes required on the client side
- Proper handling of binary data without corruption
- Centralized transformation logic in API Management
- Support for different file types and metadata

You can find the complete sample code in my [Azure APIM samples repository](https://github.com/ronaldbosma/azure-apim-samples/tree/main/convert-base64-to-multipart-formdata). For more complex scenarios, consider implementing additional validation, error handling, and monitoring to ensure robust file processing.

> TODO: mention that it's more difficult to construct a multipart/form-data request via APIM than in .NET.
> TODO: mention that we can't use [MultipartFormDataContent](https://learn.microsoft.com/en-us/dotnet/api/system.net.http.multipartformdatacontent?view=net-9.0) in APIM.
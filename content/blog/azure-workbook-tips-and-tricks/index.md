---
title: "Azure Workbook Tips & Tricks"
date: 2023-02-10T00:00:00+02:00
publishdate: 2023-02-10T00:00:00+02:00
lastmod: 2023-02-10T00:00:00+02:00
tags: [ "Azure", "Application Insights", "kusto" ]
draft: true
summary: "foo"
---

If you use Azure, you most likely will use Application Insights for logging. You can use a [Dashboard](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/tutorial-logs-dashboards) to visualize your logging and gain better insights, but dashboards come with some limitations. For instance, you can't add your own custom parameters to filter data. For these situations Azure has [Workbooks](https://learn.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview).

In this blog post I'll share some tips & tricks that I've gathered over the years. As a sample we'll create a workbook that shows information about requests send to an API Management instance.

- [Construct a query](#construct-a-query)
- [Create reusable query](#create-reusable-query)
- [Workbook](#workbook)
  - [Parameters](#parameters)
    - [Time Range Parameter](#time-range-parameter)
    - [Subscription Parameter](#subscription-parameter)
    - [Api Parameter](#api-parameter)
    - [Success Parameter](#success-parameter)
  

### Construct a query

When you want to display data from Application Insights on a dashboard or workbook, you'll need to create a query. Azure uses the [Kusto Query Language](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/) for this.

Creating such a query can be daunting if you're unfamiliar with the syntax. I always like to start by constructing an initial query through the transaction search screen of Application Insights.

For this, open your Application Insights instance in the portal and go the transaction search. At the top you'll see 'pills' that you can use to filter the data. By default it will show logging from the last 24 hours for all event types. In our case, we're interested in requests, so unselect all event types except 'Request'.

We can also add extra filters by adding a new pill. You can then select the property on which to filter and the value(s). 

To filter on requests from our API Management instance, first select the 'Service ID' property and then the name of the API Management instance. 

I also want to be able to filter on requests from specific API's. Add another pill, select 'API Name' as the property and select the API's on which to filter.

The result should look similar to the image below.

![Transaction Search](../../../../../images/azure-workbook-tips-and-tricks/transaction-search.png)

By clicking on 'View in Logs' you'll go to the Logs screen where the query we've just constructed is loaded. It should look like the query below.

```kusto
union isfuzzy=true requests
| where timestamp > datetime("2023-02-24T11:12:00.662Z") and timestamp < datetime("2023-02-25T11:12:00.662Z")
| where customDimensions["Service ID"] in ("apim-robo-test")
| where customDimensions["API Name"] in ("bar", "qux")
| order by timestamp desc
| take 100
```

At the left of the Logs screen you can see which tables you can query and the columns in the table. Here's part of the request table for example.

![Requests Table Properties](../../../../../images/azure-workbook-tips-and-tricks/requests-table-properties.png)

The `timestamp` property is a property we can directly use on our queries because it's a column of the `requests` table. The `Service ID` and `API Name` are not default columns in the requests table because they are specific to API Management. These are stored in the `customDimensions` property and can be accessed with the syntax `customDimensions["Service ID"]` and `customDimensions["API Name"]`. When you specify custom properties to log from your application, you'll find them in this `customDimensions` property.

### Create reusable query

In our workbook we'll be reusing the same query in different places, so we're going to make a function.

First we'll cleanup the generated query and only select the columns we're interested in.

- The `union isfuzzy=true` part is useful when quering multiple even types. Because we're only querying requests we can remove it.
- The query screen provides a 'Time range' pill that can be used to specify a time range to filter on. We will provide a similar filter on our workbook. So the where clause on `timestamp` can be removed.
- We'll only query on a single API Management instance, so the 'in' filter can become an 'equals'.
- We'll be adding the filter on the API name in our workbook. So we can remove it for now.
- We add a projection so we only show specific columns. The custom dimensions are by default dynamic, so we convert them to a string.
- Lastly, we can remove the `| take 100` to show more columns.

The result should look like the following query.

```kusto
requests
| where customDimensions["Service ID"] == "apim-robo-test"
| project timestamp
    , subscription = tostring(customDimensions["Subscription Name"])
    , api = tostring(customDimensions["API Name"])
    , name
    , success
    , resultCode
    , duration
    , itemId
    , sessionCorrelationId = tostring(customDimensions["Request-Session-Correlation-Id"])
```

Note the custom dimension `Request-Session-Correlation-Id`. I've configured my API Management instance to log the header `Session-Correlation-Id` with every request so I can correlate all requests from a specific session. We'll use it when creating a master detail table.

To save the query as a function, choose 'Save > Save as function' and give it a name like 'ApimRequests'. You can then use it in a query like this:

```kusto
ApimRequests
| where api in ('bar', 'qux')
| order by timestamp desc
```

### Workbook

Now that we have our query, we can start creating our workbook. Open your Application Insights instance and go to Workbooks. As you can see, Azure already provides several workbooks that you can use and customize. We'll start from scratch, so click on Empty _(A completely empty workook)_.

When you click on Add, you'll see that we can add different items to the workbook. We'll focus on parameters and queries in this workbook.

![Add Items Menu](../../../../../images/azure-workbook-tips-and-tricks/add-items-menu.png)

#### Parameters

The first thing we'll do is add a couple of parameters. These will allow us to filter on the data that will be displayed.

Click on 'Add > Add parameters' to add a parameters section to the top of the workbook.

##### Time Range Parameter

We'll want to filter on a specific time range, so click on the 'Add Parameter' button. Enter the parameter name 'Time', select 'Time range picker' as the parameter type and make it required.

![Add Parameter Time](../../../../../images/azure-workbook-tips-and-tricks/add-parameter-time.png)

Click Save to add the parameter.

##### Subscription Parameter

When calling API Management, we need to use a subscription for authentication. I want to filter on this subscription so we can see who performed which requests.

Click on the 'Add Parameter' button. Enter the parameter name 'Subscription', select 'Drop down' as the parameter type, check the 'Allow multiple selections' box and select 'Query' as the source of the data.

Enter the following query. We're using the function that we've created in a previous step.

```kusto
ApimRequests
| distinct subscription
| sort by subscription asc
```

If you want to filter the results in your parameter based on the selected time in the Time parameter, then select Time in the Time Range drop down.

To test the query, click the Run Query button. You might have to select a time range in the Time parameter for the query to work.

The New Parameter screen should look like this.

![Add Parameter Subscription](../../../../../images/azure-workbook-tips-and-tricks/add-parameter-subscription.png)

> NOTE: if you scroll down in the New Parameter window, you'll see how you can use this parameter in a query.

Click Save to add the parameter.

##### Api Parameter

As mentioned before, we also want to filter on the API that was called.

Click on the 'Add Parameter' button. Enter the parameter name 'Api', select 'Drop down' as the parameter type, check the 'Allow multiple selections' box and select 'Query' as the source of the data.

Enter the following query and select Time as the Time Range.

```kusto
ApimRequests
| distinct api
| sort by api asc
```

The New Parameter screen should look like this.

![Add Parameter Api](../../../../../images/azure-workbook-tips-and-tricks/add-parameter-api.png)

Click Save to add the parameter.

##### Success parameter

You can also use a static list to populate a drop down filter. We'll add another parameter to filter on successful and/or failed requests.

Click on the 'Add Parameter' button. Enter the parameter name 'Success', select 'Drop down' as the parameter type and select 'JSON' as the source of the data.

In the JSON Input we need to add an array of values and labels. See the example below.

```json
[
    { "value": "true", "label": "yes"},
    { "value": "false", "label": "no"}
]
```

The New Parameter screen should look like this.

![Add Parameter Success](../../../../../images/azure-workbook-tips-and-tricks/add-parameter-success.png)

Click Save to add the parameter.

Now that we've added our parameters, click the 'Done Editing' button in the 'Editing parameters item' section. The result should look something like this.

![Workbook Parameters](../../../../../images/azure-workbook-tips-and-tricks/workbook-parameters.png)


#### Table


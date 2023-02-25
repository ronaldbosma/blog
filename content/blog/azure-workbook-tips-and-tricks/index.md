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
    - [Subscription Parameter (drop down from logs)](#subscription-parameter-drop-down-from-logs)
    - [Api Parameter (drop down from logs)](#api-parameter-drop-down-from-logs)
    - [Success Parameter (drop down from JSON)](#success-parameter-drop-down-from-json)
  - [Table](#table)
    - [Request Details in Context Pane](#request-details-in-context-pane)
    - [End-to-end Transaction Details](#end-to-end-transaction-details)
  - [Totals (tiles)](#totals-tiles)
  - [Master-detail Table](#master-detail-table)
    - [Export Selection from Master Table](#export-selection-from-master-table)
    - [Add Detail Table](#add-detail-table)
    - [Show Detail Table on Selection](#show-detail-table-on-selection)
  

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

![Query Results](../../../../../images/azure-workbook-tips-and-tricks/query-results.png)

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

##### Subscription Parameter (drop down from logs)

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

##### Api Parameter (drop down from logs)

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

##### Success parameter (drop down from JSON)

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

The next step is to add a table that shows the requests. Choose 'Add > Add query'.

To filter the results in the table based on the selected time range of the previously created Time parameter, we can select the Time parameter in the Time Range drop down. And with Grid as the Visualization, the results will be shown as a table.

![Grid Time Range and Visualization](../../../../../images/azure-workbook-tips-and-tricks/grid-time-range-and-visualization.png)

Now add the following query.

```kusto
let subscriptionFilter = dynamic([{Subscription}]);
let apiFilter = dynamic([{Api}]);
let successFilter = '{Success}';

ApimRequests
| where array_length(subscriptionFilter) == 0 or subscription in (subscriptionFilter)
| where array_length(apiFilter) == 0 or api in (apiFilter)
| where isempty(successFilter) or success == tobool(successFilter)
| project timestamp
    , subscription
    , api
    , name
    , success
    , resultCode
    , duration = strcat(round(duration, 1), " ms")
    , details = itemId
    , transaction = itemId
    , sessionCorrelationId
| order by timestamp desc
```

The `let subscriptionFilter = dynamic([{Subscription}]);` line will create an array of selected subscriptions based on the Subscription parameter. If no subscription was selected, the array is empty. The filter `| where array_length(subscriptionFilter) == 0 or subscription in (subscriptionFilter)` will show all requests if no subscription was filtered or it will show requests that have a subscription specified in the Subscription parameter.

The Success parameter was not multi select, so `let successFilter = '{Success}';` will be empty if nothing is selected, `true` if yes is selected and `false` if no is selected. With the filter `| where isempty(successFilter) or success == tobool(successFilter)` we either show all request or the requests that were (un)successful.

The `itemId` is displayed twice in the column `details` and `transaction`. We'll use these further on to create links to extra data.

The query is executed when you click the Run Query button. You can now also filter the data by changing the values of the parameters. For example, select no in the Success parameter to show all failed requests.

In the Advanced Settings tab you can configure more settings. I've set the chart title to 'Requests'. I also liked to check the 'Show filter field above grid or tiles' box. This will show a filter input field above the table that can be used to furter filter the results as shown below.

![Table Filter Field](../../../../../images/azure-workbook-tips-and-tricks/table-filter-field.png)

When you click the 'Column Settings' on the Settings tab you can further customize the way columns are show. For example setting a fixed with.

##### Request Details in Context Pane

To show more information about a request, we can change the details column to show a link that opens the request details to the side.

Follow these steps:
- Click on the Column Settings button and select the details column
- Select Link in the Column renderer drop down
- Enter '11ch' as the Custom Column Width
- Select Request Details in the View to open drop down
- Enter 'details' as the Link label
- Check the 'Open link in Context pane' box

![Table Column Details](../../../../../images/azure-workbook-tips-and-tricks/table-column-details.png)

Choose Save and Close to see the results. When you click on a details link, a context pane opens on the right of the screen showing the request properties. See the example below.

![Request Details](../../../../../images/azure-workbook-tips-and-tricks/request-details.png)

##### End-to-end Transaction Details

To show the end-to-end transaction details of a request, we can change the transaction column to show a link that opens the end-to-end-transaction details.

Follow these steps:
- Click on the Column Settings button and select the transaction column
- Select Link in the Column renderer drop down
- Enter '15ch' as the Custom Column Width
- Select Request Details in the View to open drop down
- Enter 'transaction' as the Link label
- Keep the 'Open link in Context pane' unchecked

![Table Column Transaction](../../../../../images/azure-workbook-tips-and-tricks/table-column-transaction.png)

Choose Save and Close to see the results. When you click on a transaction link, the end-to-end transaction screen is shown. See the example below.

![End-to-end Transaction Details](../../../../../images/azure-workbook-tips-and-tricks/end-to-end-transaction-details.png)


#### Totals (Tiles)

Besides tables you can also use other visualizations to display your query results. One I like to use is tiles. You can use these to for instance show the total number of requests, failures and errors per API. See the example below.

![Total Tiles](../../../../../images/azure-workbook-tips-and-tricks/tiles-totals.png)

Start by adding another query to the workbook. Select Time as the Time Range, Tiles as the Visualization and Tiny as the Size.

Add the following query.

```
ApimRequests
| summarize 
        requests=strcat('Total # of requests: ', count()), 
        failures=strcat('Total # of failures: ', countif(success==false)),
        errors=countif(toint(resultCode)>=500)
    by api
```

This query groups the results by api and counts all requests, all failed requests and all requests with result code >= 500. To clarify what the different numbers are, I add a bit of text to the results.

If you run the query, you'll notice that it doesn't quite look the same as the example above. We need to customize the tile.

Choose Tile Settings. The api is already the title and the errors are displayed as the larger number on the left.

To add the total number of requests and failures. Select the Subtitle field and select requests as the column to use. Select the Bottom field and select failures as the column to use.

You can also configure on what property to order the results. Select api as the Sort Criteria under Sort Settings and Ascending as the Sort Order.

![Tiles Settings](../../../../../images/azure-workbook-tips-and-tricks/tiles-settings.png)

Choose Save and Close.

We can add a title to the chart to clarify what is displayed. Go to Advanced Settings and set the chart title to `Total # of errors per API (status code >=500)`.

I usually display the totals above a table. You can move the Tiles section above the table by choosing 'Move > Move up'.


#### Master-detail Table

Tables and other items provide the option to select data. We can use that selection as a filter in other items. 

As an example, we'll create a master-detail table. When a request in the master table is selected, all requests that have the same session correlation id will be displayed in the detail table.

##### Export Selection from Master Table

To start Edit the current Requests table. Go to Advanced Settings and check the 'When items are selected, export parameters' box.

Clik on Add parameter. Enter sessionCorrelationId as the Field to Export. Enter SelectedSessionCorrelationId as the Parameter name.

![Export Parameter Settings](../../../../../images/azure-workbook-tips-and-tricks/export-parameter-settings.png)

Choose Save. It should look like this.

![Exported Parameter](../../../../../images/azure-workbook-tips-and-tricks/exported-parameter.png)

Choose Done Editing on the Editing query item.

##### Add Detail Table

Choose 'Add > Add query' to add another table. Select Time as the Time Range and Grid as Visualization.

Add the following query.

```kusto
ApimRequests
| where sessionCorrelationId == '{SelectedSessionCorrelationId}'
| project timestamp
    , subscription
    , api
    , name
    , success
    , resultCode
    , duration = strcat(round(duration, 1), " ms")
    , details = itemId
    , transaction = itemId
| order by timestamp desc
```

This query look similar to the previous one, but only filters on the `sessionCorrelationId` column using the exported parameter of the master table. 

You can customize the columns again, similar to the master table. I also like to add a chart title in which I display the selected value. You can update the chart title in the Advanced Settings with: `Requests for session: {SelectedSessionCorrelationId}`.

##### Show Detail Table on Selection

If you don't select an item in the master table. You'll see the message below.

![Master-detail Table No Selected Item](../../../../../images/azure-workbook-tips-and-tricks/master-detail-table-no-selected-item.png)

If you don't like this, you can make the detail table hide when no row is selected in the master table. 

Open the Advanced Settings and check the 'Make this item conditionally visible'. Choose Add Condition. Enter SelectedSessionCorrelationId as the Parameter name and select 'is not equal to' in the Comparison drop down. Leave the Parameter value input empty.

![Visibility Condition](../../../../../images/azure-workbook-tips-and-tricks/visibility-condition.png)

With this the details table is only shown when the SelectedSessionCorrelationId has a value, which it will have if a row is selected in the master table.

#### Save Workbook

'Done Editing' 

Choose Save, enter a title and select the correct subscription, resource group & location.
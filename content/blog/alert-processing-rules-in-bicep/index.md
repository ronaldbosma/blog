---
title: "Alert Processing Rules in Bicep: Add Action Groups or Suppress Notifications"
date: 2026-02-02T17:45:00+01:00
publishdate: 2026-02-02T17:45:00+01:00
lastmod: 2026-02-02T17:45:00+01:00
tags: [ "Azure", "Application Insights", "Azure Monitor", "Bicep" ]
summary: "Alert processing rules let you add action groups or suppress notifications without changing alert rules. In this post I explain the actionRules resource in Bicep and show two scenarios: adding an action group and suppressing notifications on a schedule for failed availability tests."
---

In my last series of blog posts [Track Availability in App Insights](/series/track-availability-in-app-insights/), I created availability tests to check the availability of systems. I also showed how to create alerts so you can be notified when a system is down or back up again. I've set this up for various clients and several had systems that were unavailable on a regular basis for various reasons. For example every night at the same time to perform a backup. Now, nothing is more annoying than to be notified of this every single day, because you have to check if the notifications are 'expected' or if something else is going on. That's where alert processing rules can help.

The [official documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-processing-rules?tabs=portal) defines alert processing rules:  
> _"Alert processing rules allow you to apply processing on fired alerts. Alert processing rules are different from alert rules. Alert rules generate new alerts that notify you when something happens, while alert processing rules modify the fired alerts as they're being fired to change the usual alert behavior._
> 
> _You can use alert processing rules to add [action groups](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/action-groups) or remove (suppress) action groups from your fired alerts. You can apply alert processing rules to different resource scopes, from a single resource, or to an entire subscription, as long as they are within the same subscription as the alert processing rule. You can also use them to apply various filters or have the rule work on a predefined schedule._"

The official documentation already covers how to create these alert processing rules through the portal and CLI. In this post I explain how to create them using Bicep. I'll also show two scenarios based on availability tests: adding an action group for specific tests and suppressing notifications on a schedule for specific tests.

### Table of Contents

- [Understanding Microsoft.AlertsManagement/actionRules](#understanding-microsoftalertsmanagementactionrules)
  - [Scope](#scope)
  - [Actions](#actions)
  - [Scheduling](#scheduling)
- [Alert Processing Rule Samples](#alert-processing-rule-samples)
  - [Scenario 1: Send an Alert to an Action Group for Specific Availability Tests](#scenario-1-send-an-alert-to-an-action-group-for-specific-availability-tests)
  - [Scenario 2: Suppress Notifications When a Specific Availability Test Fails During a Certain Time Window](#scenario-2-suppress-notifications-when-a-specific-availability-test-fails-during-a-certain-time-window)
- [Conclusion](#conclusion)

### Understanding Microsoft.AlertsManagement/actionRules

The [Microsoft.AlertsManagement/actionRules](https://learn.microsoft.com/en-us/azure/templates/microsoft.alertsmanagement/actionrules?pivots=deployment-language-bicep) resource in Bicep lets you configure alert processing rules to modify how fired alerts behave. There are three main things to configure: scope, actions and scheduling.

#### Scope

First, you need to define one or more scopes. All alerts fired for the scope or one of its child resources will be considered by the processing rule. You can specify:
- A subscription
- A resource group
- A specific resource

When you want to apply an alert processing rule to alerts fired by an alert rule, there's an important detail to note. If you specify an alert rule ID as the scope, this will affect alerts that are triggered *about* the alert rule. For example, an alert on the activity log of the alert rule. This is probably not what you want. In our availability test example, the affected resource is actually Application Insights. So you need to specify the App Insights ID as the scope and add a filter on the alert rule ID or name.

Filters (conditions) can be used to further narrow down which alerts the processing rule applies to. When multiple filters are defined, they all apply because there's a logical AND between the filters. Each filter can have up to 5 values and there's a logical OR between the values.

For example, let's say you want to scope the processing rule on subscription `12345678-abcd-abcd-abcd-1234567890ab` with the following filters:
- The resource group name contains the text 'integration'
- And the resource type is Application Insights or API Management or App Service
- And the severity is Critical (0) or Error (1)
- And the alert condition is 'Fired'

You can use the following scopes and conditions block:

```bicep
scopes: [
  '/subscriptions/12345678-abcd-abcd-abcd-1234567890ab'
]

conditions: [
  {
    field: 'TargetResourceGroup'
    operator: 'Contains'
    values: [
      'integration'
    ]
  }
  {
    field: 'TargetResourceType'
    operator: 'Equals'
    values: [
      'microsoft.insights/components'
      'microsoft.apimanagement/service'
      'microsoft.web/sites'
    ]
  }
  {
    field: 'Severity'
    operator: 'Equals'
    values: [
      'Sev1'
      'Sev0'
    ]
  }
  {
    field: 'MonitorCondition'
    operator: 'Equals'
    values: [
      'Fired'
    ]
  }
]
```

Note that you can't specify multiple conditions for the same field to create a logical AND. 

See the [condition documentation](https://learn.microsoft.com/en-us/azure/templates/microsoft.alertsmanagement/actionrules?pivots=deployment-language-bicep#condition) for the possible values for `field` and `operator`.

#### Actions

There are two types of actions you can configure in an alert processing rule.

The first option is to suppress notifications. The alert will still fire, but the action groups won't be invoked so you won't receive any notifications when it fires.

```bicep
actions: [
  {
    actionType: 'RemoveAllActionGroups'
  }
]
```

The second option is to apply an action group. An action group invokes a defined set of notifications and actions when an alert is triggered.

```bicep
actions: [
  {
    actionType: 'AddActionGroups'
    actionGroupIds: [
      actionGroup.id
    ]
  }
]
```

You can configure multiple action groups in a single processing rule.

Note that you can't specify both an `AddActionGroups` and `RemoveAllActionGroups` action on the same processing rule.

When you have conflicting processing rules, suppression takes priority. For example, if you have an alert with action group A, a processing rule that adds action group B and another processing rule that suppresses all notifications, all alerts are suppressed for both action group A and B. 

#### Scheduling

You have three options for scheduling when an alert processing rule is active.

The first option is to have it active all the time. Simply don't specify a schedule property on the resource.

The second option is to activate the rule at a specific time. You can specify a start date and time, end date and time and a time zone:

```bicep
schedule: {
  effectiveFrom: '2026-01-20T00:00:00'
  effectiveUntil: '2026-01-21T23:59:59'
  timeZone: 'W. Europe Standard Time'
}
```

The third option is to create a recurring schedule. You can repeat every day, week or month. When repeating every day, the rule applies to all days. For weekly recurrence, you need to specify at least one day of the week. With monthly recurrence, you need to specify which days of the month.

Optionally, you can specify the time when the rule should be active. You can set a start time and end time.

Here's an example of a rule that's active every week on Saturday and Sunday:

```bicep
schedule: {
  recurrences: [
    {
      recurrenceType: 'Weekly'
      daysOfWeek: [
        'Saturday'
        'Sunday'
      ]
    }
  ]
}
```

And here's an example of a rule that's active every month on the first day of the month from 00:00 to 01:00 UTC:

```bicep
schedule: {
  timeZone: 'UTC'
  recurrences: [
    {
      recurrenceType: 'Monthly'
      daysOfMonth: [
        1
      ]
      startTime: '00:00:00'
      endTime: '01:00:00'
    }
  ]
}
```

The schedule's `effectiveFrom` and `effectiveUntil` properties can also be used in combination with recurrences to limit the overall time window when the recurring schedule is active.

If no time zone is specified, it defaults to UTC. The [Microsoft.AlertsManagement/actionRules](https://learn.microsoft.com/en-us/azure/templates/microsoft.alertsmanagement/actionrules?pivots=deployment-language-bicep) documentation doesn't specify a list with possible time zones, but [this time zone list](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/default-time-zones#time-zones) seems to match. Use the value in the Time zone column.

> If you specify an invalid time zone, you'll get this error: "TimeZone should match System.TimeZoneInfo.Id property". Unfortunately, the [System.TimeZoneInfo.Id](https://learn.microsoft.com/en-us/dotnet/api/system.timezoneinfo.id) documentation also doesn't specify a list of possible values.

### Alert Processing Rule Samples

Now let's look at two practical scenarios based on availability tests. I'm using the alert I describe in [Track Availability in Application Insights using .NET (Azure Function)](/blog/2026/01/19/track-availability-in-application-insights-using-.net/#setting-up-alerts). For both scenarios, we want to filter on specific availability tests. We can do this by adding a filter on the alert context field.

Here's an example of the alert context of an alert that fired when the availability test `Sample Availability Test 1` failed:

```json
"alertContext": {
  "properties": null,
  "conditionType": "SingleResourceMultipleMetricCriteria",
  "condition": {
    "windowSize": "PT5M",
    "allOf": [
      {
        "metricName": "availabilityResults/availabilityPercentage",
        "metricNamespace": "microsoft.insights/components",
        "operator": "LessThan",
        "threshold": "100",
        "timeAggregation": "Average",
        "dimensions": [
          {
            "name": "availabilityResult/name",
            "value": "Sample Availability Test 1",
            "type": null,
            "values": null,
            "operator": null
          }
        ],
        "metricValue": 80.0,
        "webTestName": null
      }
    ],
    "staticThresholdFailingPeriods": {
      "numberOfEvaluationPeriods": 0,
      "minFailingPeriodsToAlert": 0
    },
    "windowStartTime": "2026-01-20T10:32:12.006Z",
    "windowEndTime": "2026-01-20T10:37:12.006Z"
  }
}
```

Because we've specified the availability test name as a dimension in the alert, it's included in the alert context and we can filter on it in our processing rule.

> Tip: If you want to see the alert context of an alert that fired in your environment, create an HTTP POST endpoint that logs the incoming request body. Then create an action group with a webhook action that points to your endpoint and attach it to the alert rule. When the alert fires, check the logged request body for the alert context.

#### Scenario 1: Send an Alert to an Action Group for Specific Availability Tests

In this scenario, we want to send a notification to an action group if an alert fires or is resolved for the failed availability test alert where the test name is 'Sample Availability Test 1' or 'Sample Availability Test 2'.

```bicep
resource notifyActionGroupOnSpecificFailedAvailabilityTests 'Microsoft.AlertsManagement/actionRules@2021-08-08' = {
  name: 'apr-notify-action-group-on-specific-failed-availability-tests'
  location: 'Global'

  properties: {
    enabled: true
    
    scopes: [
      appInsights.id
    ]
    
    conditions: [
      {
        field: 'AlertRuleId'
        operator: 'Equals'
        values: [
          failedAvailabilityTestAlert.id
        ]
      }
      {
        field: 'AlertContext'
        operator: 'Contains'
        values: [
          'Sample Availability Test 1'
          'Sample Availability Test 2'
        ]
      }
    ]
    
    actions: [
      {
        actionType: 'AddActionGroups'
        actionGroupIds: [
          actionGroup.id
        ]
      }
    ]
  }
}
```

The key parts of this configuration are the scope set to the Application Insights resource and the conditions that filter on both the alert rule ID and the alert context. The alert context filter uses the `Contains` operator to match on the availability test names. 

The location property must be set to 'Global' for alert processing rules.

Because we haven't specified a schedule, this processing rule will be active all the time and add the action group to any alerts that match the conditions.

#### Scenario 2: Suppress Notifications When a Specific Availability Test Fails During a Certain Time Window

Let's assume the availability tests 'Sample Availability Test 1' and 'Sample Availability Test 2' fail every night starting at 01:00 and they succeed again before 01:30. We don't want to be notified of this every day, so we can add an alert processing rule that suppresses notifications for these specific tests:

```bicep
resource suppressNotificationsForSpecificFailedAvailabilityTests 'Microsoft.AlertsManagement/actionRules@2021-08-08' = {
  name: 'apr-suppress-notifications-for-specific-failed-availability-tests'
  location: 'Global'

  properties: {
    enabled: true

    scopes: [
      appInsights.id
    ]
    
    conditions: [
      {
        field: 'AlertRuleId'
        operator: 'Equals'
        values: [
          failedAvailabilityTestAlert.id
        ]
      }
      {
        field: 'AlertContext'
        operator: 'Contains'
        values: [
          'Sample Availability Test 1'
          'Sample Availability Test 2'
        ]
      }
    ]
    
    actions: [
      {
        actionType: 'RemoveAllActionGroups'
      }
    ]

    schedule: {
      timeZone: 'W. Europe Standard Time'
      recurrences: [
        {
          recurrenceType: 'Daily'
          startTime: '01:00:00'
          endTime: '01:30:00'
        }
      ]
    }
  }
}
```

This configuration is similar to the first scenario, but instead of adding an action group, we're removing all action groups to suppress notifications. The schedule is set to recur daily from 01:00 to 01:30 in the W. Europe Standard Time zone.

There's one thing to note here. Our availability test alert is stateful, meaning that once it fires, it will not fire again or trigger any more actions until it's resolved. If the alert fires within the specified schedule of the alert processing rule but isn't resolved within the specified time window, you won't be notified that the availability test is still failing. If this is a concern, you can create an additional alert that checks for this situation.

### Conclusion

Alert processing rules give you fine-grained control over how Azure Monitor alerts behave without modifying the alert rules themselves. You can use them to add action groups to specific alerts or suppress notifications during maintenance windows or other expected downtime.

The `Microsoft.AlertsManagement/actionRules` resource in Bicep provides a declarative way to manage these rules alongside your other Azure infrastructure. The ability to filter on alert context is particularly useful.

For more information on alert processing rules, check out the [official Microsoft documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-processing-rules). You can also refer to my [Track Availability in App Insights](/series/track-availability-in-app-insights/) series for more context on setting up availability tests and alerts.


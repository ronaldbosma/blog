---
title: "Alert Processing Rules in Bicep: Suppress and Route Azure Monitor Alerts"
date: 2026-02-02T16:00:00+01:00
publishdate: 2026-01-20T14:00:00+01:00
lastmod: 2026-01-20T14:00:00+01:00
tags: [ "Azure", "Application Insights", "Azure Monitor", "Bicep" ]
summary: "Alert processing rules let you suppress or reroute Azure Monitor alerts without changing alert rules. In this post I explain the actionRules resource in Bicep and show two availability-test scenarios: adding an action group and suppressing notifications on a schedule."
draft: true
---

I've been extending the availability monitoring setup I use in Azure Application Insights and wanted to manage alert processing rules alongside the rest of my infrastructure. The official documentation covers the portal and CLI, but not the Infrastructure as Code workflow. In this post I show how to define alert processing rules with Bicep so you can keep suppression windows and dynamic routing in source control.

> "Alert processing rules allow you to apply processing on fired alerts. Alert processing rules are different from alert rules. Alert rules generate new alerts that notify you when something happens, while alert processing rules modify the fired alerts as they're being fired to change the usual alert behavior." — [Alert processing rules](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-processing-rules?tabs=portal)

### Table of Contents
- [Overview](#overview)
- [Understanding Microsoft.AlertsManagement/actionRules](#understanding-microsoftalertsmanagementactionrules)
- [Scope and conditions](#scope-and-conditions)
- [Actions](#actions)
- [Scheduling](#scheduling)
- [Sample scenarios with Bicep](#sample-scenarios-with-bicep)
- [Tips and troubleshooting](#tips-and-troubleshooting)
- [Conclusion](#conclusion)

### Overview
Alert processing rules sit between alert rules and notifications. They do two main things: suppress notifications (ideal during maintenance) and add action groups dynamically when an alert fires or resolves. I focus on Bicep so the rules travel with the rest of your Azure Monitor configuration. The samples build on my availability tracking series and show how to target specific availability tests.

### Understanding Microsoft.AlertsManagement/actionRules
The [Microsoft.AlertsManagement/actionRules](https://learn.microsoft.com/en-us/azure/templates/microsoft.alertsmanagement/actionrules?pivots=deployment-language-bicep) resource has three pillars: scope, action and scheduling. The resource must be deployed to the Global location and needs a name unique within the subscription.

### Scope and conditions
First define one or more scopes. All alerts fired for the scope or its child resources are candidates. You can target a subscription, resource group or resource. If you want to affect alerts produced by an alert rule, scope the resource the alert rule monitors instead of the alert rule resource itself. For Application Insights availability tests, that means using the Application Insights component ID and then filtering on the alert rule.

Filters narrow down the alerts further. Multiple filters are combined with a logical AND. Within a filter, up to five values are allowed and they are combined with OR. You cannot create a logical AND by repeating the same field.

This example scopes to a subscription and adds filters for resource group name, resource type, severity and monitor condition:

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

See the [condition reference](https://learn.microsoft.com/en-us/azure/templates/microsoft.alertsmanagement/actionrules?pivots=deployment-language-bicep#condition) for all fields and operators.

### Actions
Actions define how the alert is processed after filters match.

1. Suppress notifications: the alert still fires, but action groups are removed so nothing is sent.

```bicep
actions: [
	{
		actionType: 'RemoveAllActionGroups'
	}
]
```

2. Add action groups: append one or more action groups when the alert fires or resolves.

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

You cannot mix `AddActionGroups` and `RemoveAllActionGroups` in the same rule. If two rules match and one removes all action groups while another adds an action group, suppression wins and nothing is sent.

### Scheduling
Leave the schedule empty for an always-on rule. Use a fixed window or recurrence to control when the rule is active.

Fixed window:

```bicep
schedule: {
	effectiveFrom: '2026-01-20T00:00:00'
	effectiveUntil: '2026-01-21T23:59:59'
	timeZone: 'W. Europe Standard Time'
}
```

Recurring example, every weekend:

```bicep
schedule: {
	timeZone: 'W. Europe Standard Time'
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

If no time zone is set, UTC is used. When a time zone ID is wrong, deployment fails with: `TimeZone should match System.TimeZoneInfo.Id property`. The Windows time zone list is a good reference for valid IDs.

### Sample scenarios with Bicep
The availability alert includes the test name as a dimension, which is surfaced in the alert context. That allows filtering on specific tests. This is a simplified alert context excerpt for an availability test named "Standard Test - Backend API Status":

```json
{
	"alertContext": {
		"condition": {
			"allOf": [
				{
					"metricName": "availabilityResults/availabilityPercentage",
					"dimensions": [
						{
							"name": "availabilityResult/name",
							"value": "Standard Test - Backend API Status"
						}
					]
				}
			]
		}
	}
}
```

#### Scenario 1: Send an alert to an action group for specific availability tests
When the failed-availability alert fires or resolves for specific tests, add an action group.

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

The scope is the Application Insights resource so all availability alerts are eligible. The first condition matches the specific alert rule, the second checks the alert context for the availability test names. Location must be Global for alert processing rules.

#### Scenario 2: Suppress notifications when a specific availability test fails during a certain time window
If two availability tests always fail between 01:00 and 01:30, suppress notifications during that window.

```bicep
resource suppressLogicAppWorkflowTests 'Microsoft.AlertsManagement/actionRules@2021-08-08' = {
	name: 'apr-suppress-on-specific-failed-logic-app-workflow-tests'
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

This rule runs every day in the specified time zone and removes action groups while it is active. If the alert fires inside the window and stays active afterward, the stateful alert will not send new notifications when the window ends because it is already in a fired state. Add a separate alert if you need to detect prolonged failures beyond the window.

### Tips and troubleshooting
- Export a processing rule created in the portal and switch to the Bicep tab to quickly see the schema.
- When scopes and conditions overlap, expect suppression to take precedence over added action groups because removed groups leave nothing to invoke.
- If notifications are suppressed during a window and the alert remains fired after the window, new notifications resume only when the alert changes state (for example, resolves and fires again).
- Use Windows time zone IDs such as `W. Europe Standard Time`; invalid IDs fail deployment with the `System.TimeZoneInfo.Id` message.

### Conclusion
Alert processing rules in Bicep let you keep alert routing and maintenance windows in code alongside your alert rules. By scoping carefully, filtering on alert context and combining add or suppress actions with schedules, you can make availability alerts actionable without manual tweaks in the portal.

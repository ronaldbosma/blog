---
title: "Transform SpecFlow Table Column"
date: 2022-10-28T07:30:00+02:00
publishdate: 2022-10-28T07:30:00+02:00
lastmod: 2022-10-28T07:30:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
draft: true
---
 
In my blog post [Handling technical ids in Gherkin with SpecFlow](https://ronaldbosma.github.io/blog/2020/08/08/handling-technical-ids-in-gherkin-with-specflow/) I wrote about a trick on how to remove technical ids from Gherkin scenarios while still using technical ids in the step definitions. The proposed solution worked good for the given scenario, but not for other cases.

I've been working on a demo app that displays weather forecast information for different locations. The weather forecast class has a `LocationId` property that is a reference to a location. See the class below.

```csharp
public class WeatherForecast : IWeatherForecast
{
    public DateTime Date { get; set; }
    public int LocationId { get; set; }
    public int Temperature { get; set; }
}
```

In my Gherkin scenario I ofcourse don't want to use the technical Location Id but a user-friendly location description. See the example below.

```gherkin
Given the weather forecasts
    | Date            | Location  | Temperature |
    | 28 October 2022 | Amsterdam | 22          |
    | 28 October 2022 | London    | 8           |
    | 28 October 2022 | Madrid    | 31          |
When the weather forecast for 'London' on '28 October 2022' is retrieved
Then the following weather forecast is returned
    | Date            | Location | Temperature |
    | 28 October 2022 | London   | 8           |
```


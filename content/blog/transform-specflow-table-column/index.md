---
title: "Transform SpecFlow Table Column"
date: 2022-10-28T07:30:00+02:00
publishdate: 2022-10-28T07:30:00+02:00
lastmod: 2022-10-28T07:30:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
draft: true
---
 
In my blog post [Handling technical ids in Gherkin with SpecFlow](https://ronaldbosma.github.io/blog/2020/08/08/handling-technical-ids-in-gherkin-with-specflow/) I wrote about a trick on how to remove technical ids from Gherkin scenarios while still using technical ids in the step definitions. The proposed solution worked good for the given scenario, but not for other cases.


### Table of contents

- [Intro](#intro)
- [Use a Test Model](#use-a-test-model)


### Intro

I've been working on a demo app that displays weather forecast information for different locations. The weather forecast class has a `LocationId` property that is a reference to a location. See the class below.

```csharp
public class WeatherForecast : IWeatherForecast
{
    public DateTime Date { get; set; }
    public int LocationId { get; set; }
    public int Temperature { get; set; }
}
```

In my Gherkin scenario I don't want to use the technical Location Id. I want a user-friendly description like the example below.

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

The implemented step definition class uses the `CreateSet` extension method on `Table` to create a collection of weather forecasts. The `CompareToInstance` extension method is used when asserting that the correct weather forecast is returned. There's also a simple method to generate a location id based on the name of a location (similar to what is used in [Handling technical ids in Gherkin with SpecFlow](https://ronaldbosma.github.io/blog/2020/08/08/handling-technical-ids-in-gherkin-with-specflow/)). See the code below. The full example can be found in [this project](https://github.com/ronaldbosma/blog-code-examples/tree/master/TransformSpecFlowTableColumn/01-Init).

```csharp
[Binding]
internal class Steps
{
    private readonly WeatherForecastRepository _repository = new ();
    private IWeatherForecast? _actualWeatherForecast;

    [Given(@"the weather forecasts")]
    public void GivenTheWeatherForecasts(Table table)
    {
        var weatherForecasts = table.CreateSet<WeatherForecast>();
        _repository.Register(weatherForecasts);
    }

    [When(@"the weather forecast for '([^']*)' on '([^']*)' is retrieved")]
    public void WhenTheWeatherForecastForOnIsRetrieved(string location, DateTime date)
    {
        int locationId = location.LocationToId();
        _actualWeatherForecast = _repository.GetByDateAndLocation(date, locationId);
    }

    [Then(@"the following weather forecast is returned")]
    public void ThenTheFollowingWeatherForecastIsReturned(Table table)
    {
        table.CompareToInstance(_actualWeatherForecast);
    }
}
```

We haven't done anything to convert the location names in the tables to the location id. They location ids will be 0 by default and the scenario will fail. There are a couple of ways to deal with this issue.

### Use a Test Model

Introducing a 'test model' is a common solution when the table doesn't matched the object that is created or compared. This test model is created in the SpecFlow project. In our example it would look like the class below where we have a `Location` property of type `string` instead of a location id.

```csharp
internal class WeatherForecastTestModel
{
    public DateTime Date { get; set; }

    public string Location { get; set; } = null!;

    public int Temperature { get; set; }
}
```

The `Given` step definition is changed to convert the table into a collection of `WeatherForecastTestModel` first. It is then mapped to a collection `WeatherForecast` where the location name is also converted into a location id. See the code below.

```csharp
[Given(@"the weather forecasts")]
public void GivenTheWeatherForecasts(Table table)
{
    var weatherForecasts = table.CreateSet<WeatherForecastTestModel>()
        .Select(t => new WeatherForecast
        {
            Date = t.Date,
            LocationId = t.Location.LocationToId(),
            Temperature = t.Temperature
        });

    _repository.Register(weatherForecasts);
}
```

A similar approach can be taken in the `Then` step definition. After we have the `WeatherForecast` instance, a tool like `FluentAssertions` can be used to perform the comparison. 

```csharp
[Then(@"the following weather forecast is returned")]
public void ThenTheFollowingWeatherForecastIsReturned(Table table)
{
    var testModel = table.CreateInstance<WeatherForecastTestModel>();
    var expectedWeatherForecast = new WeatherForecast
    {
        Date = testModel.Date,
        LocationId = testModel.Location.LocationToId(),
        Temperature = testModel.Temperature
    };

    _actualWeatherForecast.Should().BeEquivalentTo(expectedWeatherForecast);
}
```

As you can see, manual mapping from the test model to the actual model is required. A tool like AutoMapper can help with this, but it's not great.

There is another downside. The following scenario will fail because the Temperature column has been removed in the `Then` step. This would be fine when using the `CompareToInstance` or `CompareToSet` because it only compares the specified columns. A tool like `FluentAssertions` compares all properties though and the temperature of the expected weather forecast defaults to 0.

```gherkin
Given the weather forecasts
    | Date            | Location  | Temperature |
    | 28 October 2022 | Amsterdam | 22          |
    | 28 October 2022 | London    | 8           |
    | 28 October 2022 | Madrid    | 31          |
When the weather forecast for 'London' on '28 October 2022' is retrieved
Then the following weather forecast is returned
    | Date            | Location |
    | 28 October 2022 | London   |
```

The full example of this solution can be found in [this project](https://github.com/ronaldbosma/blog-code-examples/tree/master/TransformSpecFlowTableColumn/02-UseTestModel). I've removed the duplicate mapping code by using a couple of `StepArgumentTransformation` methods.


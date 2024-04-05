---
title: "Transform SpecFlow Table Column"
date: 2022-10-29T12:30:00+02:00
publishdate: 2022-10-29T12:30:00+02:00
lastmod: 2024-04-05T00:00:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code", "Reqnroll" ]
summary: "In a previous blog post I wrote about a trick on how to remove technical ids from Gherkin scenarios while still using technical ids in the step definitions. The proposed solution worked well for the given scenario, but not for other cases. In this post I look at several approaches on how to solve this issue."
draft: false
---
 
In my blog post [Handling technical ids in Gherkin with SpecFlow](https://ronaldbosma.github.io/blog/2020/08/08/handling-technical-ids-in-gherkin-with-specflow/) I wrote about a trick on how to remove technical ids from Gherkin scenarios while still using technical ids in the step definitions. The proposed solution worked well for the given scenario, but not for other cases.


### Table of contents

- [Problem](#problem)
- [Use a Test Model](#use-a-test-model)
- [Use Value Retriever and Table Alias](#use-value-retriever-and-table-alias)
- [Use Custom Type with Value Retriever and Comparer](#use-custom-type-with-value-retriever-and-comparer)
- [Transform Table Column](#transform-table-column)
- [Conclusion](#conclusion)

### Problem

I've been working on a demo app that displays weather forecast information for different locations. The weather forecast is represented by a class that has a `LocationId` property that is a reference to a location entity. See the class below.

```csharp
internal class WeatherForecast
{
    public DateTime Date { get; set; }
    public int LocationId { get; set; }
    public int Temperature { get; set; }
}
```

In my Gherkin scenario I don't want to use the technical location id. I want a user-friendly description like in the example below.

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

The `Given` step definition uses the `CreateSet` extension method on `Table` to create a collection of weather forecasts. The `CompareToInstance` extension method is used in the `Then` step definition to assert that the correct weather forecast is returned. There's also a simple method to generate a location id based on the name of a location (similar to what is used in [Handling technical ids in Gherkin with SpecFlow](https://ronaldbosma.github.io/blog/2020/08/08/handling-technical-ids-in-gherkin-with-specflow/)).

See the full code below. A working example can be found in [this project](https://github.com/ronaldbosma/blog-code-examples/tree/master/TransformSpecFlowTableColumn/01-Init).

```csharp
[Binding]
internal class Steps
{
    private readonly WeatherForecastRepository _repository = new ();
    private WeatherForecast? _actualWeatherForecast;

    [Given(@"the weather forecasts")]
    public void GivenTheWeatherForecasts(Table table)
    {
        var weatherForecasts = table.CreateSet<WeatherForecast>();
        _repository.Register(weatherForecasts);
    }

    [When(@"the weather forecast for '([^']*)' on '([^']*)' is retrieved")]
    public void WhenTheWeatherForecastForLocationOnDateIsRetrieved(string location, DateTime date)
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

We haven't done anything yet to convert the location names in the tables to the location id. The location ids will be defaulted to `0` and the scenario will fail.

There are a couple of ways to deal with this situation, which I describe in the rest of this blog post.

### Use a Test Model

Introducing a 'test model' is a common solution when the table doesn't match the object that is created or compared. This test model is created in the SpecFlow project. In our example it would look like the class below, where we have a `Location` property of type `string` instead of a location id.

```csharp
internal class WeatherForecastTestModel
{
    public DateTime Date { get; set; }

    public string Location { get; set; } = null!;

    public int Temperature { get; set; }
}
```

The `Given` step definition will first convert the table into a collection of `WeatherForecastTestModel`. Which is then mapped to a collection of `WeatherForecast`. We also convert the location name into a location id. See the code below.

```csharp
[Given(@"the weather forecasts")]
public void GivenTheWeatherForecasts(Table table)
{
    var weatherForecasts = table
        .CreateSet<WeatherForecastTestModel>()
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

There is another downside. The following scenario will fail because the `Temperature` column has been removed from the `Then` step. 

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

This scenario would succeed when using the `CompareToInstance` method, because that method only compares the specified columns. A tool like `FluentAssertions` compares all properties though and the temperature of the expected weather forecast defaults to `0` while the actual weather forecast has a temperature of `8`.

> NOTE: because I'm generating the location id based on the location name with the `GetHashCode` method, I can't map the location id back to the location name. Which means, I'm also unable to map the actual weather forecast to a type of `WeatherForecastTestModel` and then use `CompareToInstance`. If you can map from id back to the name, this issue can be avoided.

The full example of this solution can be found in [this project](https://github.com/ronaldbosma/blog-code-examples/tree/master/TransformSpecFlowTableColumn/02-UseTestModel). I've removed the duplicate mapping code by using a couple of [Step Argument Transformation](https://docs.specflow.org/projects/specflow/en/latest/Bindings/Step-Argument-Conversions.html) methods.

### Use Value Retriever and Table Alias

When using the `CreateSet` and `CreateInstance` methods, SpecFlow supports conversion of table cells with [Value Retrievers](https://docs.specflow.org/projects/specflow/en/latest/Extend/Value-Retriever.html). To convert the location name into an id, the following value retriever can be used.

```csharp
internal class LocationIdValueRetriever : IValueRetriever
{
    public bool CanRetrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return keyValuePair.Key == "Location" && propertyType == typeof(int);
    }

    public object Retrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return keyValuePair.Value.LocationToId();
    }
}
```

This value retriever will convert a cell's value when the column name is `Location` and the type to convert to is an `int` (which is the type of the location id). Because we still use `Location` as the column name, we also need to add a table alias to the `LocationId` property as shown below.

```csharp
internal class WeatherForecast
{
    public DateTime Date { get; set; }

    [TableAliases("Location")]
    public int LocationId { get; set; }

    public int Temperature { get; set; }
}
```

This approach has 2 disadvantages. First, we need to add the `TableAliases` attribute to our model. You probably don't want to do that in a class of your actual production code, because it requires a dependency on SpecFlow.

The second disadvantage is that we can't really use this approach for the `Then` step. For comparisons SpecFlow has the notion of Value Comparers. Unfortunately, the `IValueComparer` interface is limited compared to the `IValueRetriever` interface, as you can see below.

```csharp
public interface IValueComparer
{
    bool CanCompare(object actualValue);
    bool Compare(string expectedValue, object actualValue);
}
```

Since we don't know which column we're comparing, it's not really a viable option. We could convert any string to an `int` and perform the comparison, but this might result in unexpected behaviour further down the road when we have a larger code base.

See [this project](https://github.com/ronaldbosma/blog-code-examples/tree/master/TransformSpecFlowTableColumn/03-UseValueRetriever) for a full implementation of this solution.

### Use Custom Type with Value Retriever and Comparer

To improve on the previous solution, we can introduce a custom `LocationId` type and use it in the weather forecast. See the example below.

```csharp
internal record struct LocationId(int locationId);

internal class WeatherForecast
{
    public DateTime Date { get; set; }

    [TableAliases("Location")]
    public LocationId LocationId { get; set; }

    public int Temperature { get; set; }
}
```

The value retriever is changed to convert to a `LocationId` instead of an `int`. Now we don't really need to check the column name anymore.

```csharp
internal class LocationIdValueRetriever : IValueRetriever
{
    public bool CanRetrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return propertyType == typeof(LocationId);
    }

    public object Retrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return new LocationId(keyValuePair.Value.LocationToId());
    }
}
```

For the comparison, we can implement a value comparer like the one below.

```csharp
internal class LocationIdValueComparer : IValueComparer
{
    public bool CanCompare(object actualValue)
    {
        return actualValue is LocationId;
    }

    public bool Compare(string expectedValue, object actualValue)
    {
        var expected = new LocationId(expectedValue.LocationToId());
        var actual = (LocationId)actualValue;

        return expected == actual;
    }
}
```

In projects where using these custom types is common, this can be a good approach. The only downside is that we still need to add a table alias on the `LocationId` property if we want to use `Location` as the column name.

A full example of this solution can be found in [this project](https://github.com/ronaldbosma/blog-code-examples/tree/master/TransformSpecFlowTableColumn/04-UseCustomTypeWithValueRetrieverAndComparer).

### Transform Table Column

Because of the mentioned downsides, lately I've been using a different approach to solve the issue at hand. With this approach, I transform the column in the table before using the `Create...` and `Compare...` extension methods. So, the location column with location names is transformed into a location id column with location ids.

I've created a generic extension method for this as shown in the following code sample.

```csharp
public static Table TransformColumn(this Table table, string oldColumn, string newColum, Func<string, string> transform)
{
    if (table.ContainsColumn(oldColumn))
    {
        table.RenameColumn(oldColumn, newColum);

        foreach (var row in table.Rows)
        {
            row[newColum] = transform(row[newColum]);
        }
    }

    return table;
}
```

The transformation is a 2-step process. First the column is renamed from `Location` to `LocationId` with the `RenameColumn` method (provided by SpecFlow). Then we iterate over the rows and update the cell in each row using the provided `transform` function.

No changes are needed to the original `WeatherForecast` class. We also don't need to create a value retriever and comparer. Simply call the `TransformColumn` and then execute the `Create...` or `Compare...` extension method. See the code below for the new implementation of the `Given` and `Then` step definitions.

```csharp
[Given(@"the weather forecasts")]
public void GivenTheWeatherForecasts(Table table)
{
    var weatherForecasts = table.TransformColumn("Location", "LocationId", (s) => s.LocationToId().ToString())
                                .CreateSet<WeatherForecast>();

    _repository.Register(weatherForecasts);
}

[Then(@"the following weather forecast is returned")]
public void ThenTheFollowingWeatherForecastIsReturned(Table table)
{
    table.TransformColumn("Location", "LocationId", (s) => s.LocationToId().ToString())
         .CompareToInstance(_actualWeatherForecast);
}
```

I think this is a nice and clean approach that will help keep our Gherkin scenarios readable and our test automation code simple. There is however 1 downside. When the comparison fails because the location is wrong, you don't get the error message: `Location: Expected <Madrid>, Actual <London>`. Instead, you get: `LocationId: Expected <3>, Actual <2>`. This could be confusing if you don't know what's happening under the hood.

[This project](https://github.com/ronaldbosma/blog-code-examples/tree/master/TransformSpecFlowTableColumn/05-TransformColumn) has a full working example. In this project, I've moved the `TransformColumn("Location", "LocationId", (s) => s.LocationToId().ToString())` call into another extension method to reduce duplication.

### Conclusion

I've described several approaches on how to remove technical ids from your Gherkin scenario's tables while still using ids in your code. Each has its pros and cons. Transforming a table column is a new approach for me that has worked well. I hope it can be another tool in your toolbox. If you have any other / better solutions, I hope to hear from you.
---
title: "Reqnroll Parsable Value Retriever and Comparer"
date: 2024-05-17T12:30:00+02:00
publishdate: 2024-05-17T12:30:00+02:00
lastmod: 2024-05-17T12:30:00+02:00
tags: [ "Reqnroll", "SpecFlow", "Test Automation" ]
summary: "In this blog post we'll look at how to use the `IParsable<T>` interface to build a generic Reqnroll Value Retriever and Comparer. This solution also works for it's predecessor SpecFlow when using .NET 7 or higher."
draft: true
---

The introduction of .NET 7 has brought us the `IParsable<T>` interface. It's a generic interface that defines a static `Parse` and `TryParse` method. This interface is used to parse a string into an instance of the implementing type. Common types like `DateTime`, `Int32` and `Guid` all implement this interface.

If you have a custom type that needs to be parsed from a string, you can implement this interface yourself. This is useful because it allows for reusable parsing logic. In this blog post we'll see how to use the `IParsable<T>` interface to build a generic [Reqnroll](https://reqnroll.net/) Value Retriever and Comparer.

As you might already know, when working with tables in Gherkin scenarios, you can use the Reqnroll [DataTable Helper](https://docs.reqnroll.net/latest/automation/datatable-helpers.html) extension methods `CreateInstance<T>` and `CreateSet<T>` to convert a table into a single object or list of objects. Similarly, the `CompareToInstance<T>` and `CompareToSet<T>` extension methods can be used to compare objects to a `DataTable` with expected data.

These extension methods work great when your properties are only simple types like `string`, `int`, `DateTime`, etc. But what if you have a custom type that needs to be converted or compared? This is where [Value Retrievers and Value Comparers](https://docs.reqnroll.net/latest/extend/value-retrievers.html) come in. They allow you to define custom logic for converting and comparing custom types.

> When you're unfamiliar with the Reqnroll DataTable Helper extension methods or Value Retrievers & Comparers, I recommend reading the [DataTable Helpers documentation](https://docs.reqnroll.net/latest/automation/datatable-helpers.html) and [Value Retrievers documentation](https://docs.reqnroll.net/latest/extend/value-retrievers.html) first.


In this blog post we'll be using the following scenario to convert a table into a list of `WeatherForecast` objects and compare them with another table:

```gherkin
Scenario: Create weather forecasts from a table and compare them with another table

When the following table is converted into weather forecasts
    | Date          | Minimum Temperature | Maximum Temperature |
    | 13 April 2024 | 13 °C               | 23 °C               |
    | 14 April 2024 | 10 °C               | 15 °C               |
    | 15 April 2024 | 7 °C                |                     |
Then the following weather forecasts are created
    | Date          | Minimum Temperature | Maximum Temperature |
    | 13 April 2024 | 13 °C               | 23 °C               |
    | 14 April 2024 | 50 °F               | 59 °F               |
    | 15 April 2024 | 7 °C                |                     |
```

In the `When` step, we'll use the `CreateSet` DataTable helper to convert the `DataTable` into a list of `WeatherForecast` objects. In the `Then` step, we'll use the `CompareToSet` DataTable helper to compare the expected weather forecasts with the actual weather forecasts. The implemented step definitions are shown below:

```csharp
private IEnumerable<WeatherForecast>? _actualWeatherForecasts;

[When("the following table is converted into weather forecasts")]
public void WhenTheFollowingTableIsConvertedIntoWeatherForecasts(DataTable dataTable)
{
    _actualWeatherForecasts = dataTable.CreateSet<WeatherForecast>();
}

[Then("the following weather forecasts are created")]
public void ThenTheFollowingWeatherForecastsAreCreated(DataTable dataTable)
{
    dataTable.CompareToSet(_actualWeatherForecasts);
}
```

The `WeatherForecast` class is defined as follows:

```csharp
public class WeatherForecast
{
    public DateOnly Date { get; set; }
    public Temperature MinimumTemperature { get; set; } = null!;
    public Temperature? MaximumTemperature { get; set; }
}
```

As you can see, the `WeatherForecast` class has a `DateOnly` property and two `Temperature` properties. The `DateOnly` type was introduced in .NET 6 to represent a date without time and is currently not supported by Reqnroll. The `Temperature` type is a custom type that represents a temperature in both Celsius and Fahrenheit. 

The `Temperature` is a record that implements the `IParsable<T>` interface and is defined as follows:

```csharp
public record Temperature : IParsable<Temperature>
{
    private readonly static Regex TemperatureRegex = new(@"^(-?\d+) (°C|°F)$");

    public int DegreesCelsius { get; init; }
    public int DegreesFahrenheit { get; init; }

    public static Temperature FromDegreesCelsius(int degreesCelsius)
    {
        decimal degreesFahrenheit = (decimal)degreesCelsius * 9 / 5 + 32;
        return new Temperature
        {
            DegreesCelsius = degreesCelsius,
            DegreesFahrenheit = (int)Math.Round(degreesFahrenheit, 0, MidpointRounding.AwayFromZero)
        };
    }

    public static Temperature FromDegreesFahrenheit(int degreesFahrenheit)
    {
        decimal degreesCelsius = ((decimal)degreesFahrenheit - 32) * 5 / 9;
        return new Temperature
        {
            DegreesCelsius = (int)Math.Round(degreesCelsius, 0, MidpointRounding.AwayFromZero),
            DegreesFahrenheit = degreesFahrenheit
        };
    }

    public static Temperature Parse(string s, IFormatProvider? provider)
    {
        var isValidTemperature = TryParse(s, provider, out var result);
        if (isValidTemperature && result is not null)
        {
            return result;
        }
        else
        {
            throw new FormatException($"The value '{s}' is not in the correct format.");
        }
    }

    public static bool TryParse([NotNullWhen(true)] string? s, IFormatProvider? provider, [MaybeNullWhen(false)] out Temperature result)
    {
        if (s != null)
        {
            var regexMatches = TemperatureRegex.Matches(s);

            if (regexMatches.Count == 1)
            {
                var temperatureValue = int.Parse(regexMatches[0].Groups[1].Value);
                var temperatureUnit = regexMatches[0].Groups[2].Value;

                result = temperatureUnit == "°C" ? FromDegreesCelsius(temperatureValue) : FromDegreesFahrenheit(temperatureValue);
                return true;
            }
        }

        result = null;
        return false;
    }
}
```

The `FromDegreesCelsius` and `FromDegreesFahrenheit` methods can be used to create a `Temperature` instance based on and `integer` value of degrees Celsius or Fahrenheit.

The `Parse` and `TryParse` methods implement the `IParsable<T>` interface and are used to parse a string to a `Temperature` instance. They use a regular expression to extract the digits and the unit, which is either `°C` or `°F`.  

For example, the strings `10 °C` and `50 °F` will both be parsed to a `Temperature` instance where `DegreesCelsius` is `10` and `DegreesFahrenheit` is `50` respectively.


Now, if we would run our scenario as is, we would get the following error:

```
Test method ReqnrollParsableValueRetrieverAndComparer.Init.InitFeature.CreateWeatherForecastsFromATableAndCompareThemWithAnotherTable threw exception: 
Reqnroll.ComparisonException: 
  | Date          | Minimum Temperature | Maximum Temperature |
- | 13 April 2024 | 13 °C               | 23 °C               |
- | 14 April 2024 | 50 °F               | 59 °F               |
- | 15 April 2024 | 7 °C                |                     |
+ | 1/1/0001      |                     |                     |
+ | 1/1/0001      |                     |                     |
+ | 1/1/0001      |                     |                     |
```

This error occurs because Reqnroll was unable to properly create the `WeatherForecast` objects from the table. Instead, the date has a value of `1/1/0001` and the temperature values are empty. This is because Reqnroll doesn't know how to parse the `DateOnly` and `Temperature` types from the table.


### Implementing custom Value Retrievers and Value Comparers

To solve this issue, we need to implement custom Value Retrievers and Value Comparers for the `DateOnly` and `Temperature` types. We'll start by implementing the `DateOnlyValueRetriever` class:

```csharp
internal class DateOnlyValueRetriever : IValueRetriever
{
    public bool CanRetrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return propertyType == typeof(DateOnly) && DateOnly.TryParse(keyValuePair.Value, out _);
    }

    public object Retrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return DateOnly.Parse(keyValuePair.Value);
    }
}
```

Reqnroll will call the `CanRetrieve` method to determine if the `DateOnlyValueRetriever` can retrieve the value. If the property type is `DateOnly` and the value can be parsed to a `DateOnly` instance, the `CanRetrieve` method will return `true`. The `Retrieve` method is then called to parse the value to a `DateOnly` instance.

The `DateOnlyValueComparer` class is implemented as follows:

```csharp
internal class DateOnlyValueComparer : IValueComparer
{
    public bool CanCompare(object actualValue)
    {
        return actualValue is DateOnly;
    }

    public bool Compare(string expectedValue, object actualValue)
    {
        var isExpectedDate = DateOnly.TryParse(expectedValue, out DateOnly expectedDate);
        return isExpectedDate && actualValue.Equals(expectedDate);
    }
}
```

Similar to the value retriever, Reqnroll will call the `CanCompare` method to determine if the `DateOnlyValueComparer` can compare the value. If the actual value is of type `DateOnly`, the `CanCompare` method will return `true`. The `Compare` method is then called to compare the expected value with the actual value. If the expected value cannot be parse to a `DateOnly`, `false` will be returned. Otherwise, the actual value will be compared with the expected value.

And here are the implementations for the `TemperatureValueRetriever` and `TemperatureValueComparer` classes:

```csharp
internal class TemperatureValueRetriever : IValueRetriever
{
    public bool CanRetrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return propertyType == typeof(Temperature) && Temperature.TryParse(keyValuePair.Value, null, out _);
    }

    public object Retrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return Temperature.Parse(keyValuePair.Value, null);
    }
}


internal class TemperatureValueComparer : IValueComparer
{
    public bool CanCompare(object actualValue)
    {
        return actualValue is Temperature;
    }

    public bool Compare(string expectedValue, object actualValue)
    {
        var isExpectedTemperature = Temperature.TryParse(expectedValue, null, out Temperature? expectedTemperature);
        return isExpectedTemperature && actualValue.Equals(expectedTemperature);
    }
}
```

As you can see, the implementations are exactly the same as for the `DateOnlyValueRetriever` and `DateOnlyValueComparer` classes, but now for the `Temperature` type.

The last step is to register the custom value retrievers and value comparers. We can use a `BeforeTestRun` hook as shown in the following code snippet:

```csharp
[BeforeTestRun]
public static void BeforeTestRun()
{
    Service.Instance.ValueRetrievers.Register(new DateOnlyValueRetriever());
    Service.Instance.ValueRetrievers.Register(new TemperatureValueRetriever());

    Service.Instance.ValueComparers.Register(new DateOnlyValueComparer());
    Service.Instance.ValueComparers.Register(new TemperatureValueComparer());
}
```

With these changes, the scenario will now run successfully and the expected and actual weather forecasts will be compared correctly. You can find a working sample in the `01-Init` project of [this solution](https://github.com/ronaldbosma/blog-code-examples/tree/master/reqnroll-parsable-value-retriever-and-comparer).


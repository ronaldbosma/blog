---
title: "Reqnroll Parsable Value Retriever and Comparer"
date: 2024-05-17T12:30:00+02:00
publishdate: 2024-05-17T12:30:00+02:00
lastmod: 2024-05-17T12:30:00+02:00
tags: [ "Reqnroll", "SpecFlow", "Test Automation" ]
summary: "In this blog post, we'll explore how to use the `IParsable<T>` interface to build a generic Reqnroll value retriever and comparer. We'll start by creating custom value retrievers and comparers, then develop a reusable solution with generics, and finally, we'll use reflection to make it even more generic. (This solution also works for its predecessor, SpecFlow, when using .NET 7 or higher.)"
draft: true
---

The introduction of .NET 7 has brought us the [IParsable<T>](https://learn.microsoft.com/en-us/dotnet/api/system.iparsable-1?view=net-8.0) interface, a generic interface that defines static `Parse` and `TryParse` methods. This interface is used to parse a string into an instance of the implementing type. Common types like `string`, `int` and `DateTime` all implement this interface.

If you have a custom type that needs to be parsed from a string, you can implement this interface yourself. This is useful because it allows for reusable parsing logic. In this blog post, we'll see how to use the `IParsable<T>` interface to build a generic [Reqnroll](https://reqnroll.net/) value retriever and comparer.

> Reqnroll is the successor to SpecFlow, designed for automating Gherkin scenarios in .NET with C#. The solution provided in this blog post can also work with SpecFlow when using .NET 7 or higher.

As you might already know, when working with tables in Gherkin scenarios, you can use the [DataTable Helper](https://docs.reqnroll.net/latest/automation/datatable-helpers.html) extension methods `CreateInstance<T>` and `CreateSet<T>` to convert a table into a single object or a list of objects. Similarly, the `CompareToInstance<T>` and `CompareToSet<T>` extension methods can be used to compare objects to a table with expected data.

These extension methods work great when your properties are only simple types like `string`, `int` and `DateTime`. But what if you have a custom type that needs to be converted or compared? This is where [Value Retrievers and Value Comparers](https://docs.reqnroll.net/latest/extend/value-retrievers.html) come in. They allow you to define custom logic for converting and comparing custom types.

> If you're unfamiliar with the Reqnroll DataTable Helper extension methods or Value Retrievers and Comparers, I recommend reading the [DataTable Helpers documentation](https://docs.reqnroll.net/latest/automation/datatable-helpers.html) and [Value Retrievers documentation](https://docs.reqnroll.net/latest/extend/value-retrievers.html) first.

As you'll see, the combination of the `IParsable<T>` interface and Reqnroll's value retrievers and value comparers can be a powerful tool for creating generic parsing logic. In this blog post, we'll start by creating a custom type that implements the `IParsable<T>` interface. We'll then use this type in a Gherkin scenario to convert and compare it with a table. Finally, we'll create a generic solution to handle any type that implements the `IParsable<T>` interface.

### Table of Contents

- [Intro](#intro)
- [Custom Value Retrievers and Comparers](#custom-value-retrievers-and-comparers)
- [Generic Parsable Value Retriever and Comparer](#generic-parsable-value-retriever-and-comparer)
- [Parsable Value Retriever and Comparer with Reflection](#parsable-value-retriever-and-comparer-with-reflection)
- [Conclusion](#conclusion)


### Intro

Let's start with some Gherkin first. We'll be using the following scenario to convert a table into a list of `WeatherForecast` objects and compare them with another table:

```gherkin
Scenario: Create weather forecasts from a table and compare them with another table

When the following table is converted into weather forecasts
    | Date          | Minimum Temperature | Maximum Temperature |
    | 13 April 2024 | 13 °C               | 23 °C               |
    | 14 April 2024 | 10 °C               | 59 °F               |
    | 15 April 2024 | 7 °C                |                     |
Then the following weather forecasts are created
    | Date          | Minimum Temperature | Maximum Temperature |
    | 13 April 2024 | 13 °C               | 23 °C               |
    | 14 April 2024 | 10 °C               | 59 °F               |
    | 15 April 2024 | 7 °C                |                     |
```

In the `When` step, we'll use the `CreateSet<T>` method to convert the `DataTable` into a list of `WeatherForecast` objects. In the `Then` step, we'll use the `CompareToSet<T>` method to compare the expected weather forecasts with the actual weather forecasts. The implemented step definitions are shown below:

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

As you can see, the `WeatherForecast` class has a `DateOnly` property and two `Temperature` properties. The `MaximumTemperature` property is nullable to check if our solution can handle `null` values.

The [DateOnly](https://learn.microsoft.com/en-us/dotnet/api/system.dateonly?view=net-8.0) type was introduced in .NET 6 to represent a date without time. Currently, Reqnroll cannot convert it out-of-the-box. 

The `Temperature` type is a custom type that can represent a temperature in both Celsius and Fahrenheit. It is a record that implements the `IParsable<T>` interface and is defined as follows:

```csharp
public enum TemperatureUnit
{
    Celsius,
    Fahrenheit
}

public record Temperature : IParsable<Temperature>
{
    // Regex to parse a temperature string
    private readonly static Regex TemperatureRegex = new(@"^(-?\d+) (°C|°F)$");

    public int Degrees { get; init; }
    public TemperatureUnit Unit { get; init; }

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
        result = null;

        if (string.IsNullOrWhiteSpace(s))
        {
            return false;
        }
        
        var regexMatches = TemperatureRegex.Matches(s);
        if (regexMatches.Count != 1)
        {
            return false;
        }

        var degrees = int.Parse(regexMatches[0].Groups[1].Value);
        var unit = regexMatches[0].Groups[2].Value;

        result = new Temperature
        {
            Degrees = degrees,
            Unit = unit == "°C" ? TemperatureUnit.Celsius : TemperatureUnit.Fahrenheit
        };
        return true;
    }
}
```

The `Temperature` record has a `Degrees` property that represents the temperature in degrees and a `Unit` property that represents the unit of the temperature, which is Celsius or Fahrenheit.

The `Parse` and `TryParse` methods implement the `IParsable<T>` interface and are used to parse a string into a `Temperature` instance. They use a regular expression to extract the degrees and the unit, which is represented by `°C` or `°F`. Example include are `10 °C` and `59 °F`.

Now, if we were to run our scenario as is, we would get the following error:

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

This error occurs because Reqnroll is unable to properly create and compare the `WeatherForecast` objects from the table. Instead, the date has a value of `1/1/0001` and the temperature values are empty. This is because Reqnroll doesn't know how to parse the `DateOnly` and `Temperature` types from the table.


### Custom Value Retrievers and Comparers

To solve this issue, we can implement custom value retrievers and comparers for the `DateOnly` and `Temperature` types. We'll start by implementing the `DateOnlyValueRetriever` class:

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

Every value retriever implements the `IValueRetriever` interface. Reqnroll will call the `CanRetrieve` method to determine if the `DateOnlyValueRetriever` can retrieve the value. If the property type is `DateOnly` and the value can be parsed to a `DateOnly` instance, the `CanRetrieve` method will return `true`. The `Retrieve` method is then called to parse the value to a `DateOnly` instance.

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

Similar to the value retriever, the value comparer needs to implement the `IValueComparer` interface. Reqnroll will call the `CanCompare` method to determine if the `DateOnlyValueComparer` can compare the value. If the actual value is of type `DateOnly`, the `CanCompare` method will return `true`. The `Compare` method is then called to compare the expected value with the actual value. If the expected value cannot be parse to a `DateOnly`, `false` will be returned. Otherwise, the actual value will be compared with the expected value.

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

The last step is to register the custom value retrievers and comparers. We can use a `BeforeTestRun` hook as shown in the following code snippet:

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

With these changes, the scenario will now run successfully and the expected and actual weather forecasts will be created and compared correctly. You can find a working sample in the `01-Init` project of [this solution](https://github.com/ronaldbosma/blog-code-examples/tree/master/reqnroll-parsable-value-retriever-and-comparer).


### Generic Parsable Value Retriever and Comparer

As you've seen, the implementations of the `DateOnlyValueRetriever` and `TemperatureValueRetriever` are very similar. The same goes for the `DateOnlyValueComparer` and `TemperatureValueComparer`. Because both the `DateOnly` and `Temperature` types implement the `IParsable<T>` interface, we can create a generic `ParsableValueRetriever<T>` and `ParsableValueComparer<T>` class to reduce the amount of code.

Here's the implementation of the `ParsableValueRetriever<T>` class:

```csharp
internal class ParsableValueRetriever<T> : IValueRetriever where T : IParsable<T>
{
    public bool CanRetrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return typeof(IParsable<T>).IsAssignableFrom(propertyType) &&
                T.TryParse(keyValuePair.Value, CultureInfo.CurrentCulture, out _);
    }

    public object Retrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return T.Parse(keyValuePair.Value, CultureInfo.CurrentCulture);
    }
}
```

In the `CanRetrieve` method we check if the property type implements `IParsable<T>` and if the value can be parsed to a `T` instance. If true, the `Retrieve` method is called to parse the value to a `T` instance.

And here's the implementation of the `ParsableValueComparer<T>` class:

```csharp
internal class ParsableValueComparer<T> : IValueComparer where T : IParsable<T>
{
    public bool CanCompare(object actualValue)
    {
        return actualValue is IParsable<T>;
    }

    public bool Compare(string expectedValue, object actualValue)
    {
        var isParsed = T.TryParse(expectedValue, CultureInfo.CurrentCulture, out T? expectedObject);
        return isParsed && actualValue.Equals(expectedObject);
    }
}
```

In the `CanCompare` method we check if the actual value implements `IParsable<T>`. If true, the `Compare` method is called to compare the expected value with the actual value.

With these generic implementations, we can now register the `ParsableValueRetriever<T>` and `ParsableValueComparer<T>` classes for the `DateOnly` and `Temperature` types in the `BeforeTestRun` hook as shown below:

```csharp
[BeforeTestRun]
public static void BeforeTestRun()
{
    Service.Instance.ValueRetrievers.Register(new ParsableValueRetriever<DateOnly>());
    Service.Instance.ValueRetrievers.Register(new ParsableValueRetriever<Temperature>());

    Service.Instance.ValueComparers.Register(new ParsableValueComparer<DateOnly>());
    Service.Instance.ValueComparers.Register(new ParsableValueComparer<Temperature>());
}
```

With these two generic classes, we can now convert and compare every type that implements the `IParsable<T>` interface, reducing the amount of code and making it easier to add new types in the future. The only downside to this solution is that we have to register the value retriever and comparer for each type separately.

You can find a working sample in the `02-GenericTypes` project of [this solution](https://github.com/ronaldbosma/blog-code-examples/tree/master/reqnroll-parsable-value-retriever-and-comparer).

### Parsable Value Retriever and Comparer with Reflection

We can go one step further. In the previous solution we had to register the value retriever and comparer for each type separately. Instead, we can use reflection to implement the value retriever and comparer so it can handle any type that implements the `IParsable<T>` interface.

Here's the implementation for the `ParsableValueRetriever` class:

```csharp
internal class ParsableValueRetriever : IValueRetriever
{
    public bool CanRetrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return GenericParsableParser.ImplementsSupportedIParsable(propertyType) &&
               GenericParsableParser.TryParse(propertyType, keyValuePair.Value, null, out _);
    }

    public object Retrieve(KeyValuePair<string, string> keyValuePair, Type targetType, Type propertyType)
    {
        return GenericParsableParser.Parse(propertyType, keyValuePair.Value, CultureInfo.CurrentCulture);
    }
}
```

The logic remains the same as before. It checks if the property type implements the `IParsable<T>` interface and if the value can be parsed to a `T` instance. If `true`, the `Retrieve` method is called to parse the value to a `T` instance.

And here's the implementation for the `ParsableValueComparer` class:

```csharp
internal class ParsableValueComparer : IValueComparer
{
    public bool CanCompare(object actualValue)
    {
        return actualValue != null && GenericParsableParser.ImplementsSupportedIParsable(actualValue.GetType());
    }

    public bool Compare(string expectedValue, object actualValue)
    {
        var isParsed = GenericParsableParser.TryParse(actualValue.GetType(), expectedValue, CultureInfo.CurrentCulture, out object? expectedObject);
        return isParsed && actualValue.Equals(expectedObject);
    }
}
```

Once again, the logic is very similar to before. An additional check is included in the `CanCompare` method to ensure that the actual value is not `null`, as we need to determine the type of the actual value. If the actual value implements the `IParsable<T>` interface, the `Compare` method is called to compare the expected value with the actual value.

Both classes use the `GenericParsableParser` class, which contains a couple of handy helper methods. First, the `ImplementsSupportedIParsable` method is used to check if the type implements the `IParsable<T>` interface. The implementation is shown below:

```csharp
public static bool ImplementsSupportedIParsable(Type type)
{
    return type.GetInterfaces().Any(i =>
        i.IsGenericType &&
        i.GetGenericTypeDefinition() == typeof(IParsable<>) &&
        // IParsable<string> is exluded because we can't dynamically create an instance of string
        i.GetGenericArguments()[0] != typeof(string)
    );
}
```

Since `ImplementsSupportedIParsable` will return `true` for all types that implement the `IParsable<T>` interface, it also returns `true` for common types like `string`, `int` and `DateTime`. However, I found that the parsing logic doesn't work well with strings, so these are excluded.

Next is the `Parse` method, which is used to parse a string to an instance of the implementing type. It relies on the `TryParse` method to perform the actual parsing.

```csharp
public static object Parse(Type targetType, string s, IFormatProvider? formatProvider)
{
    if (TryParse(targetType, s, formatProvider, out object? result))
    {
        return result;
    }
    else
    {
        throw new ArgumentException($"Unable to parse '{s}' to type {targetType}");
    }
}
```

The `TryParse` function is where the real reflection magic happens.

```csharp
public static bool TryParse(Type targetType, [NotNullWhen(true)] string? s, IFormatProvider? formatProvider, [MaybeNullWhen(false)] out object result)
{
    // Check if the target type implements IParsable<TSelf>
    if (!ImplementsSupportedIParsable(targetType))
    {
        result = null;
        return false;
    }

    // Get the IParsable<TSelf> interface implemented by the target type
    var parsableInterface = targetType
        .GetInterfaces()
        .FirstOrDefault(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IParsable<>));

    if (parsableInterface == null)
    {
        throw new ArgumentException($"Type {targetType} does not implement IParsable<TSelf>");
    }

    // Get the type parameter TSelf of IParsable<TSelf>
    var parsableType = parsableInterface.GetGenericArguments().Single();

    // Create an instance of TSelf
    var parsableInstance = Activator.CreateInstance(parsableType);
    if (parsableInstance == null)
    {
        throw new Exception($"Unable to create instance of type {parsableType}");
    }

    // Get the TryParse method of TSelf with signature: TryParse(String, IFormatProvider, out TSelf)
    var parseMethod = parsableType.GetMethod("TryParse", [typeof(string), typeof(CultureInfo), parsableType.MakeByRefType()]);
    if (parseMethod == null)
    {
        throw new Exception($"Unable to get method with signature TryParse(String, IFormatProvider, out TSelf) from type {parsableType}");
    }

    // Invoke the TryParse method
    object?[] parameters = [s, formatProvider, null];
    var tryParseResult = (bool?)parseMethod.Invoke(parsableInstance, parameters);
    if (tryParseResult == null)
    {
        throw new Exception($"TryParse method on type {parsableType} unexpectedly returned null for value: {s}");
    }

    // Set result to the parsed result if TryParse was successful
    result = (bool)tryParseResult ? parameters[2] : null;

    return (bool)tryParseResult;
}
```

The `TryParse` method executes the following steps:
1. It checks if the target type implements a supported version of the `IParsable<T>` interface.
1. It gets the `IParsable<T>` interface implemented by the target type.
1. From the `IParsable<T>` interface, it retrieves the type parameter `T`.
1. It creates an instance of `T`.
1. It gets the `TryParse` method of `T`.
1. It invokes the `TryParse` method.
1. If the `TryParse` was successful, it sets the result to the parsed value and returns `true`.

The last step is to register the `ParsableValueRetriever` and `ParsableValueComparer` classes in the `BeforeTestRun` hook as shown below:

```csharp
[BeforeTestRun]
public static void BeforeTestRun()
{
    Service.Instance.ValueRetrievers.Register(new ParsableValueRetriever());
    Service.Instance.ValueComparers.Register(new ParsableValueComparer());
}
```

With this, the `ParsableValueRetriever` and `ParsableValueComparer` classes can now handle any type that implements the `IParsable<T>` interface. You can find a working sample in the `03-Reflection` project of [this solution](https://github.com/ronaldbosma/blog-code-examples/tree/master/reqnroll-parsable-value-retriever-and-comparer).

> As an alternative to using reflection inside the value retriever and comparer, you could also scan your assemblies for all types implementing `IParsable<T>` and register an instance of `ParsableValueRetriever<T>` and `ParsableValueComparer<T>` for each of them.


### Conclusion

With the introduction of the `IParsable<T>` interface in .NET 7, it has become much easier to create generic parsing logic. By combining this interface with Reqnroll's value retrievers and comparers, we can create a generic solution to convert and compare any type that implements the `IParsable<T>` interface. Using reflection, we can make this solution more generic and handle any type that implements the `IParsable<T>` interface. However, because not everybody is a fan of reflection, I'll let you decide which solution you prefer.
---
title: "Cleaning Up Your Test Data Builders"
date: 2019-03-16T13:24:49+01:00
publishdate: 2019-03-16T13:24:49+01:00
lastmod: 2019-03-17T00:00:00+01:00
image: "images/blog/cleaning-up-your-test-data-builders.jpg"
tags: [ "Cleaner Code", "Test Automation" ]
comments: true
draft: true
---

I still come across a lot of automated tests with many lines of code just to create an object. Even when most data is not relevant for the scenario being tested. Making the tests harder to read and maintain.

Using a [Test Data Builder](http://www.natpryce.com/articles/000714.html) can minimize the lines of code in your test to what's relevant. By default the builder will create all necessary data for you. Using a Fluent API you can call methods on the builder to tweak the data to fit your test scenario.

Using test data builders has really improved the readability of my test automation code. I've always had the nagging feeling though that the readability could be improved. Even when using a fairly simple builder, the code seems clunky to me most of the time.

Here's my initial take on a builder to create a simple `Person` object. It creates _**a man called Sherlock Holmes living at 221B Baker Street, London**_. Although I only specify a name, gender and address it's still a lot of code for just three properties.

```csharp
Person sherlock = new PersonBuilder()
    .WithName("Sherlock Holmes")
    .IsMan()
    .WithAddress(
        new AddressBuilder()
            .WithAddressLine1("221B Baker Street")
            .WithAddressLine2("London")
            .Build()
    )
    .Build();
```

Inspired by a talk I attended a couple of months ago I decided to refactor some of my test data builders. In the rest of this post I'll go through some of the steps I've taken using the example above as the starting point.

The code examples in this post are focussed on the use of the test data builder. More details on how the builder and other parts are implemented can be found [here](https://github.com/ronaldbosma/blog/tree/master/examples/CleaningUpYourTestDataBuilders).

### Introducing the Object Mother

Step one is to move the instantiation of the `PersonBuilder`. In the test I'm not really interested in the fact that I'm using a builder. I want 'A Person'. We can combine the [Object Mother](https://martinfowler.com/bliki/ObjectMother.html) pattern with the Test Data Builder pattern to make this happen.

An object mother is a factory class. Containing one or more methods/properties to create test data. It will create an object with default data just like a test data builder. The downside of the object mother is that it's harder to tweak your test data. Which can result in a lot of different factory methods all doing almost the same thing. That's why I prefer test data builders.

I've created an object mother class called `A`. It has a static `Person` property that returns a new instance of the `PersonBuilder`.  

```csharp
Person sherlock = A.Person
    .WithName("Sherlock Holmes")
    .IsMan()
    .WithAddress(
        new AddressBuilder()
            .WithAddressLine1("221B Baker Street")
            .WithAddressLine2("London")
            .Build()
    )
    .Build();
```

### Moving a build method to the Object Mother

We can take this one step further and create a `Man` property in the object mother. Combining `A.Person` and the `IsMan` method into one.

```csharp
Person sherlock = A.Man
    .WithName("Sherlock Holmes")
    .WithAddress(
        new AddressBuilder()
            .WithAddressLine1("221B Baker Street")
            .WithAddressLine2("London")
            .Build()
    )
    .Build();
```

Be cautious with this. Don't use more than one (business) concept like `A.ManWithName("Sherlock Holmes")`. This could create an explosion of methods & properties in your object mother class. Making it harder to maintain. Besides, combining multiple build steps is what the test data builder is for.

### Rename methods to improve flow

The next step is to improve the flow of the code. In the `PersonBuilder` I've renamed `WithName` to `Called` and `WithAddress` to `LivingAt`. Making the code read more like a normal sentence.

```csharp
Person sherlock = A.Man.Called("Sherlock Holmes")
    .LivingAt(
        new AddressBuilder()
            .WithAddressLine1("221B Baker Street")
            .WithAddressLine2("London")
            .Build()
    )
    .Build();
```

### Simplifying address creation

The code to create the address still looks a bit ugly. So I've refactored the `LivingAt` method to take the first and second address line in one string, separated by a comma. The `AddressBuilder` is used inside `LivingAt` to parse the string and create the address.  

```csharp
Person sherlock = A.Man.Called("Sherlock Holmes")
    .LivingAt("221B Baker Street, London")
    .Build();
```

Keep this kind of logic simple or you'll have to test your builders too.

### Finishing touch

If you're using explicit types instead of the `var` keyword there's one more step to take. You can remove the call to `Build` by introducing an [implicit type conversion operator](https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/implicit) in the `PersonBuilder`. This will convert a `PersonBuilder` to a `Person` by calling the `Build` method.

```csharp
Person sherlock = A.Man.Called("Sherlock Holmes")
    .LivingAt("221B Baker Street, London");
```

The example at the start of the blog still needed the explanation that the code creates _**a man called Sherlock Holmes living at 221B Baker Street, London**_. Now the code is self explanatory.

### Conclusion

By combining the [Object Mother](https://martinfowler.com/bliki/ObjectMother.html) and [Test Data Builder](http://www.natpryce.com/articles/000714.html) patterns and refactoring your build methods to flow more like natural language, your code can read more like a sentence. Almost like a Given step in a Gherkin scenario. This will improve the readability of your tests and makes them easier to maintain.

The full C# code example with intermediate refactoring steps can be found [here](https://github.com/ronaldbosma/blog/tree/master/examples/CleaningUpYourTestDataBuilders).
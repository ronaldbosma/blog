---
title: "Cleaning Up Your Test Data Builders"
date: 2019-03-16T13:24:49+01:00
publishdate: 2019-03-16T13:24:49+01:00
image: "images/hal-gatewood-484469-unsplash.jpg"
tags: [ "Cleaner Code", "Test Automation" ]
comments: false
draft: false
---

I've been using the [Test Data Builder](http://www.natpryce.com/articles/000714.html) pattern for quite a while now. It's really improved the readability of my test automation code. I've always had the nagging feeling though that it could be better.

Inspired by a talk I attended a couple of months ago I decided to refactor some of my test data builders. In this post I'll go through some of the steps I've taken.

The code example below is my initial take on a builder to create a simple Person object. It has a name, gender and address.

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

### Introducing the Object Mother

Step one is to move the instantiation of the `PersonBuilder`. In the test I'm not really interested in the fact that I'm using a builder. I want 'A Person'. We can combine the [Object Mother](https://martinfowler.com/bliki/ObjectMother.html) pattern with the Test Data Builder pattern to make this happen.

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

Be cautious with this. Don't use more than one (business) concept like `A.ManWithName("Sherlock Holmes")`. Combining multiple build steps is what the builder is for.

### Rename methods to improve flow

The next step is to improve the flow of the code. I've renamed `WithName` to `Called` and `WithAddress` to `LivingAt`. Making the code read more like a normal sentence.

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

The `AddressBuilder` is still a bit ugly. So I've refactored the `LivingAt` method to take the first and second address line in one string, separated by a comma. The `AddressBuilder` is used inside `LivingAt` to parse the string.  

```csharp
Person sherlock = A.Man.Called("Sherlock Holmes")
    .LivingAt("221B Baker Street, London")
    .Build();
```

Keep this kind of logic simple or you'll have to test your builders too.

### Finishing touch

If your using explicit types instead of the `var` keyword there's one more step to take. You can remove the call to `Build` by introducing an [implicit type conversion operator](https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/implicit) in the `PersonBuilder`. This will convert a `PersonBuilder` to a `Person` by calling the `Build` method.

```csharp
Person sherlock = A.Man.Called("Sherlock Holmes")
    .LivingAt("221B Baker Street, London");
```

### Conclusion

By combining the [Object Mother](https://martinfowler.com/bliki/ObjectMother.html) and [Test Data Builder](http://www.natpryce.com/articles/000714.html) patterns and refactoring your build methods to flow more like natural language, your code can read more like a sentence. Almost like a Given step in a Gherkin scenario.

The full C# code example with intermediate refactoring steps can be found [here](https://github.com/ronaldbosma/ronaldbosma.github.io/examples/CleaningUpYourTestDataBuilders).
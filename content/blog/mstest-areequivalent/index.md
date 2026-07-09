---
title: "Deep Object Comparison in MSTest with Assert.AreEquivalent"
date: 2026-06-01T20:00:00+02:00
publishdate: 2026-06-01T20:00:00+02:00
lastmod: 2026-06-01T20:00:00+02:00
tags: [ "MSTest", "Test Automation", ".NET", "Testing" ]
summary: "MSTest v4.3.0 introduces the Assert.AreEquivalent<T> method that performs a deep equality comparison of two objects, checking that all properties have the same value. In this post, I'll show you what it can do and how it compares to AwesomeAssertions and Shouldly."
draft: true
---

I've used [FluentAssertions](https://fluentassertions.com/) in many test projects over the years. The fluent API is great, but the feature I relied on most was the `Should().BeEquivalentTo` extension method. It performs a deep equality comparison of two objects by checking that all properties have the same value. Using it means you don't have to write code to check each property yourself, keeping tests clean and easy to write.

When FluentAssertions changed its license, I looked at alternatives. [AwesomeAssertions](https://awesomeassertions.org/) is a fork of FluentAssertions before the license change and has the same interface. [Shouldly](https://docs.shouldly.org/) is a popular alternative that has gained traction as well.

I also noticed that [xUnit introduced its own implementation](https://xunit.net/releases/v2/2.4.2.html) back in August 2022. Because I regularly use MSTest, I thought it would be a nice addition to MSTest too. So, I registered [this issue](https://github.com/microsoft/testfx/issues/4776) a while back. 

In July 2026, MSTest v4.3.0 was released which introduced the `Assert.AreEquivalent<T>` method. In this post I'll walk you through what it can do and how it compares to AwesomeAssertions and Shouldly. I've created a small [sample solution](https://github.com/ronaldbosma/blog-code-examples/tree/master/MSTest.AreEquivalent) that shows the three frameworks side by side.

### Table of Contents

- [Test Setup](#test-setup)
- [Assert.AreEqual vs Assert.AreEquivalent<T>](#assertareequal-vs-assertareequivalent)
- [Cross-Type Comparison](#cross-type-comparison)
- [Nested Objects](#nested-objects)
- [Collection Comparison](#collection-comparison)
- [Types with Extra Properties](#types-with-extra-properties)
- [Limitations](#limitations)
- [Conclusion](#conclusion)

### Test Setup

I'm using an `AddressInternal` class as test data throughout the examples:

```csharp
internal class AddressInternal
{
    public AddressInternal(string street, string city, string state, string zipCode)
    {
        Street = street;
        City = city;
        State = state;
        ZipCode = zipCode;
    }

    public string Street { get; set; }
    public string City { get; set; }
    public string State { get; set; }
    public string ZipCode { get; set; }
}
```

I've also created an `AddressExternal` class that has the exact same properties. Having external and internal versions of a model is a common scenario in projects. This will let us check whether a library can handle comparing different types.

### Assert.AreEqual vs Assert.AreEquivalent<T>

Before MSTest v4.3.0, `Assert.AreEqual` was the method you could use for comparison. It relies on the `Equals` method of the objects being compared. This works great for structs and records, but for other classes this means comparing object references rather than property values.

Here are three tests that demonstrate the behaviour:

```csharp
[TestMethod]
public void AreEqual_ExpectedAndActualAreSameObject_Success()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    var actual = expected;

    Assert.AreEqual(expected, actual);
}

[TestMethod]
public void AreEqual_ExpectedAndActualAreDifferentObjectsWithSameValues_AssertionFails()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    var actual = new AddressInternal("456 Elm St", "Othertown", "NY", "67890");

    var act = () => Assert.AreEqual(expected, actual);

    Assert.ThrowsExactly<AssertFailedException>(act);
}

[TestMethod]
public void AreEqual_ExpectedAndActualAreDifferentTypesWithSameValues_TestFailsAlthoughObjectsAreEquivalent()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    var actual = new AddressExternal("123 Main St", "Anytown", "CA", "12345");

    Assert.AreEqual<object>(expected, actual);
}
```

The first test passes because `expected` and `actual` point to the same object. The second test shows the expected failure when property values differ. The third test is the interesting one: even though both objects have identical properties and values, the assertion fails because `AreEqual` uses `Equals`, which compares object references for classes that don't have a custom equality implementation.

The new `Assert.AreEquivalent<T>` method solves this by comparing properties by value:

```csharp
[TestMethod]
public void AreEquivalent_ExpectedAndActualAreSameObject_Success()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    var actual = expected;

    Assert.AreEquivalent(expected, actual);
}

[TestMethod]
public void AreEquivalent_ExpectedAndActualAreDifferentObjectsWithDifferentValues_AssertionFails()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    var actual = new AddressInternal("456 Elm St", "Othertown", "NY", "67890");

    var act = () => Assert.AreEquivalent(expected, actual);

    Assert.ThrowsExactly<AssertFailedException>(act);
}

[TestMethod]
public void AreEquivalent_ExpectedAndActualAreDifferentTypesWithSameValues_Success()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    var actual = new AddressExternal("123 Main St", "Anytown", "CA", "12345");

    Assert.AreEquivalent<object>(expected, actual);
}
```

The third test now passes as well because `AreEquivalent` checks the properties of both objects and compares their values rather than relying on `Equals`. 

Note that there is only a generic implementation of `Assert.AreEquivalent`. So, we need to specify `<object>` to compare different objects. To verify that `Assert.AreEquivalent` actually performs the comparison, here's a test that checks that the assertion fails because the street has a different value.

```csharp
[TestMethod]
public void AreEquivalent_ExpectedAndActualAreDifferentTypesWithDifferentValues_AssertionFails()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    // actual has different street
    var actual = new AddressExternal("456 Elm St", "Anytown", "CA", "12345");

    var act = () => Assert.AreEquivalent<object>(expected, actual);

    var ex = Assert.ThrowsExactly<AssertFailedException>(act);
    StringAssert.Contains(ex.Message, "Street");
}
```

### Cross-Type Comparison

As shown in the previous section, `Assert.AreEquivalent<T>` can compare objects of different types as long as they share the same property names and values. AwesomeAssertions handles this the same way. Shouldly, however, doesn't support comparing different types, so that's something to keep in mind if you're considering it as an alternative.

### Nested Objects

Complex child objects are also supported. For example, a `PersonInternal` object with an `AddressInternal` property is compared correctly:

```csharp
[TestMethod]
public void AreEquivalent_EquivalentNestedObjectsOfDifferentTypes_Success()
{
    var expected = new PersonInternal("John", "Doe", 30,
        new AddressInternal("123 Main St", "Anytown", "CA", "12345"));
    var actual = new PersonExternal("John", "Doe", 30,
        new AddressExternal("123 Main St", "Anytown", "CA", "12345"));

    Assert.AreEquivalent<object>(expected, actual);
}

[TestMethod]
public void AreEquivalent_NestedObjectsOfDifferentTypesWithDifferentValues_AssertionFails()
{
    var expected = new PersonInternal("John", "Doe", 30,
        new AddressInternal("123 Main St", "Anytown", "CA", "12345"));
    // actual has different street
    var actual = new PersonExternal("John", "Doe", 30,
        new AddressExternal("456 Elm St", "Anytown", "CA", "12345"));

    var act = () => Assert.AreEquivalent<object>(expected, actual);

    var ex = Assert.ThrowsExactly<AssertFailedException>(act);
    StringAssert.Contains(ex.Message, "Street");
}
```

### Collection Comparison

Comparing collections also works with `Assert.AreEquivalent<T>`. Here's an example using a list of addresses:

```csharp
[TestMethod]
public void AreEquivalent_CollectionsWithSameObjects_Success()
{
    var expected = new List<AddressInternal>
    {
        new AddressInternal("123 Main St", "Anytown", "CA", "12345"),
        new AddressInternal("456 Elm St", "Othertown", "NY", "67890")
    };
    var actual = new List<AddressInternal>
    {
        new AddressInternal("123 Main St", "Anytown", "CA", "12345"),
        new AddressInternal("456 Elm St", "Othertown", "NY", "67890")
    };

    Assert.AreEquivalent(expected, actual);
}

[TestMethod]
public void AreEquivalent_DifferentListOfObjects_AssertionFails()
{
    var expected = new List<AddressInternal>
    {
        new AddressInternal("123 Main St", "Anytown", "CA", "12345"),
        new AddressInternal("456 Elm St", "Othertown", "NY", "67890")
    };
    var actual = new List<AddressInternal>
    {
        new AddressInternal("123 Main St", "Anytown", "CA", "12345"),
        // actual has different street
        new AddressInternal("789 Oak St", "Othertown", "NY", "67890")
    };

    var act = () => Assert.AreEquivalent(expected, actual);

    var ex = Assert.ThrowsExactly<AssertFailedException>(act);
    StringAssert.Contains(ex.Message, "Street");
}
```

This works well for straightforward cases where you want to verify that two collections contain objects with the same property values.

### Types with Extra Properties

Sometimes you might need to compare two similar types where one of them has additional properties. Consider an `AddressWithExtraProperty` type that has an extra `Country` property. Here's an example:

```csharp
[TestMethod]
public void AreEquivalent_ActualHasExtraProperty_Success()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    var actual = new AddressWithExtraProperty("123 Main St", "Anytown", "CA", "12345", "The Country");

    Assert.AreEquivalent<object>(expected, actual);
}

[TestMethod]
public void AreEquivalent_ExpectedHasExtraProperty_AssertionFails()
{
    var expected = new AddressWithExtraProperty("123 Main St", "Anytown", "CA", "12345", "The Country");
    var actual = new AddressInternal("123 Main St", "Anytown", "CA", "12345");

    var act = () => Assert.AreEquivalent<object>(expected, actual);

    var ex = Assert.ThrowsExactly<AssertFailedException>(act);
    StringAssert.Contains(ex.Message, "Country");
}
```

Similar to AwesomeAssertions, the objects are considered equivalent when the actual object has the extra property and different when the expected property has the extra property.

### Limitations

The current implementation is a solid first step, but it's not feature-complete yet. One noticeable gap is the lack of support for ignoring specific properties during comparison. AwesomeAssertions supports this through its options parameter:

```csharp
[TestMethod]
public void ShouldBeEquivalentTo_ExpectedAndActualHaveDifferentValueButPropertyIsIgnored_Success()
{
    var expected = new AddressInternal("123 Main St", "Anytown", "CA", "12345");
    var actual = new AddressInternal("456 Elm St", "Anytown", "CA", "12345");

    actual.Should().BeEquivalentTo(expected, options => options.Excluding(x => x.Street));
}
```

This test passes with AwesomeAssertions even though `Street` differs between the two objects because we're explicitly excluding it from the comparison. MSTest doesn't support this yet, and neither does Shouldly, so it's a known limitation to be aware of for now.

### Conclusion

The new `Assert.AreEquivalent<T>` method in MSTest v4.3.0 fills a gap that previously required a third-party library. It handles deep property comparison, works across different types with the same shape and supports collections. If you're already using MSTest and want to reduce dependencies, this is a welcome addition.

The implementation isn't complete though. Ignoring properties during comparison is a common need that isn't supported at the time of writing. 

If you want to try it yourself, the [sample solution](https://github.com/ronaldbosma/blog-code-examples/tree/master/MSTest.AreEquivalent) on GitHub contains all the examples from this post for AwesomeAssertions, Shouldly and MSTest side by side, along with additional scenarios.

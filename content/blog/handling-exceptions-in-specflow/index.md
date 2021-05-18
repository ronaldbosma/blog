---
title: "Handling exceptions in SpecFlow"
date: 2021-04-21T00:00:00+02:00
publishdate: 2021-04-21T00:00:00+02:00
lastmod: 2021-04-21T00:00:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
summary: "I commonly use Gherkin scenarios to describe the functional specifications of my software and SpecFlow to automate these scenarios. Usually there will be a couple of scenarios describing the happy paths of the feature I'm building but also some scenarios concerning failures. In this post I'll show my solution how to handle failures in the form of exceptions with the Driver pattern."
---

I commonly use Gherkin scenarios to describe the functional specifications of my software and SpecFlow to automate these scenarios. Usually there will be a couple of scenarios describing the happy paths of the feature I'm building but also some scenarios concerning failures. Depending on how the application code works, these failures are represented by exceptions being thrown. In this post I explain how I handle these exceptions.

### Table of contents

- [Retrieve existing person successfully](#retrieve-existing-person-successfully)
- [Retrieve unknown person and expect an error](#retrieve-unknown-person-and-expect-an-error)
- [Expected error was not raised](#expected-error-was-not-raised)
- [Check for unexpected errors](#check-for-unexpected-errors)
- [Refactor to reusable code](#refactor-to-reusable-code)
  - [Refactored PersonsSteps class](#refactored-personssteps-class)
  - [New generic ErrorSteps](#new-generic-errorsteps)
  - [The ErrorDriver class](#the-errordriver-class)
- [Conclusion](#conclusion)

### Retrieve existing person successfully

Let's start with the following happy path scenario to retrieve a person.

```gherkin
Scenario: Retrieve existing person successfully

Given the person 'Buffy Summers' is registered
When I retrieve 'Buffy Summers'
Then the person 'Buffy Summers' is returned
```

In the `Given` step we make sure the person exists in our system. We then retrieve the person and verify that the retrieval is successful.

The following step definition class implements this scenario.

```csharp
[Binding]
class PersonPersonsSteps
{
    private readonly PersonRepository _people = new PersonRepository();
    private string _actualName;

    [Given(@"the person '(.*)' is registered")]
    public void GivenThePersonLivingAtIsRegistered(string name)
    {
        _people.AddPerson(name);
    }
        
    [When(@"I retrieve '(.*)'")]
    public void WhenIRetrieve(string name)
    {
        _actualName = _people.GetPersonByName(name);
    }

    [Then(@"the person '(.*)' is returned")]
    public void ThenThePersonLivingAtIsReturned(string expectedName)
    {
        Assert.IsNotNull(_actualName, "No person retrieved");
        Assert.AreEqual(expectedName, _actualName);
    }
}
```

It uses a simple in-memory `PersonRepository` to store people. The `_actualName` field is used to store the person that is retrieved so we can check if the retrieval was successful in the `Then` step. For demo purposes we only store and retrieve the name of the person.

Here's the implementation of the `PersonRepository` class.

```csharp
class PersonRepository
{
    private readonly HashSet<string> _people = new HashSet<string>();

    public void AddPerson(string name)
    {
        _people.Add(name);
    }

    public string GetPersonByName(string name)
    {
        if (_people.Contains(name))
        {
            return name;
        }
        throw new PersonNotFoundException(name);
    }
}
```

As you can see a `PersonNotFoundException` is raised when the person can not be found.

### Retrieve unknown person and expect an error

To verify that an error is raised when a person can not be found, I've added a second scenario.

```gherkin
Scenario: Retrieve unknown person and expect an error

Given no person is registered
When I retrieve 'Buffy Summers'
Then the error 'Person with name Buffy Summers not found' should be raised
```

This scenario makes sure no person is registered. It then tries to retrieve a person and validates that an error has occured with the correct error message.

If you execute this scenario with the current implementation of our step definitions the scenario will fail on the `When` step because we're not handling the exception. As the code below shows, you can fix this by adding a `try catch` block in the `When` step that stores the raised exception in a field called `_actualException` and check the exception message in the `Then` step.

```csharp
private Exception _actualException;

[When(@"I retrieve '(.*)'")]
public void WhenIRetrieve(string name)
{
    try
    {
        _actualName = _people.GetPersonByName(name);
    }
    catch (Exception ex)
    {
        _actualException = ex;
    }
}

[Then(@"the error '(.*)' should be raised")]
public void ThenTheErrorShouldBeRaised(string expectedErrorMessage)
{
    Assert.IsNotNull(_actualException, "No error was raised");
    Assert.AreEqual(expectedErrorMessage, _actualException.Message);
}
```

With this implementation both scenarios will succeed.

### Expected error was not raised

It's also important that my scenarios fail when something goes wrong. Either because my implementation is wrong or the scenario has an error. Take the following two scenarios for example. I expect a certain error to be raised but this does not happen.

```gherkin
Scenario: Should fail: retrieve person that exists but expect error

Given the person 'Buffy Summers' is registered
When I retrieve 'Buffy Summers'
Then the error 'Person with name Buffy Summers not found' should be raised


Scenario: Should fail: different error message expected

Given no person is registered
When I retrieve 'Buffy Summers'
Then the error 'Something went wrong' should be raised
```

Both scenarios should and will fail. The first fails because I'm retrieving a person that exists but I expect the error that the person does not exist. The second scenario fails because I'm expecting an error with the wrong error message.

### Check for unexpected errors

One case that is often forgotten is to check for unexpected errors. Take the following scenario for example.

```gherkin
Scenario: Should fail: retrieve unknown person but don't check error

Given no person is registered
When I retrieve 'Buffy Summers'
```

I'm retrieving a person that is not registered. In the first implementation of our `When` step definition without the `try catch` block this scenario would fail because an exception is raised in the `When` step. But now that I catch this exception the scenario succeeds where it should fail.

> Note that this scenario is missing a `Then` step so it's not the greatest real life example. I have seen this issue however in past projects with scenarios that succeeded even with a `Then` step but an unexpected error was raised. So a bug in the production code or test automation code was flying under the radar.

To fix this issue we can use an `AfterScenario` hook to check if any unexpected error has occured. I've altered the `Then` step that checks for expected errors to clear the `_actualException` field if an expected error occurs.

```csharp
[Then(@"the error '(.*)' should be raised")]
public void ThenTheErrorShouldBeRaised(string expectedErrorMessage)
{
    Assert.IsNotNull(_actualException, "No error was raised");
    Assert.AreEqual(expectedErrorMessage, _actualException.Message);

    // Clear the caught exception so it's not marked as unexpected in the AfterScenario hook
    _actualException = null;
}

[AfterScenario]
public void CheckForUnexpectedExceptionsAfterEachScenario()
{
    Assert.IsNull(_actualException, $"No exception was expected to be raised but found exception: {_actualException}");
}
```

### Refactor to reusable code

A full example of the implementation so far can be found in [this project](https://github.com/ronaldbosma/blog-code-examples/tree/master/HandlingExceptionsInSpecFlow/HandlingExceptionsInSpecFlow.WithoutErrorDriver). It works great when I'm retrieving a person but usually I have more features and `When` steps that need this kind of implementation. Also the `Then the error '<message>' should be raised` step is really generic but can't be reused over multiple step definition classes because of the use of the `_actualException` private field.

To fix this I've introduced a generic `ErrorDriver` class following the [Driver pattern](https://docs.specflow.org/projects/specflow/en/latest/Guides/DriverPattern.html) described in the SpecFlow documentation. This class can catch and track exceptions and has a few helper methods for validation.

#### Refactored PersonsSteps class

Before showing the `ErrorDriver` implementation I'll first show how it's used in the refactored `PersonsSteps` class.

```csharp
[Binding]
internal class PersonsSteps
{
    private readonly PersonRepository _people = new PersonRepository();
    private string _actualName;

    private readonly ErrorDriver _errorDriver;

    public PersonsSteps(ErrorDriver errorDriver)
    {
        _errorDriver = errorDriver;
    }

    /* Given steps omitted */

    [When(@"I retrieve '(.*)'")]
    public void WhenIRetrieve(string name)
    {
        _errorDriver.TryExecute(() =>
            _actualName = _people.GetPersonByName(name)
        );
    }

    /* Then step omitted */
}
```

As you can see the new `ErrorDriver` class is injected into the `PersonsSteps` class via [context injection](https://docs.specflow.org/projects/specflow/en/latest/Bindings/Context-Injection.html). The person specific `Given` and `Then` steps are unaltered. The `When` step no longer has a `try catch` block. Instead the action of retrieving a person is passed into the `TryExecute` method of the `ErrorDriver` class as a lambda. The `TryExecute` method will catch any exception as you'll see in moment. The `_actualException` private field is no longer used and has been removed.

#### New generic ErrorSteps

The `Then the error '<message>' should be raised` step and the `AfterScenario` hook are generic methods that can be reused for other features. I've moved these to an `ErrorSteps` class as shown below.

```csharp
[Binding]
internal class ErrorSteps
{
    private readonly ErrorDriver _errorDriver;

    public ErrorSteps(ErrorDriver errorDriver)
    {
        _errorDriver = errorDriver;
    }

    [Then(@"the error '(.*)' should be raised")]
    public void ThenTheErrorShouldBeRaised(string expectedErrorMessage)
    {
        _errorDriver.AssertExceptionWasRaisedWithMessage(expectedErrorMessage);
    }

    [AfterScenario]
    public void CheckForUnexpectedExceptionsAfterEachScenario()
    {
        _errorDriver.AssertNoUnexpectedExceptionsRaised();
    }
}
```

This class also receives the `ErrorDriver` class via context injection. It uses the available `Assert` methods to verify if an expected or unexpected error has occured.

#### The ErrorDriver class

Now that you've seen how to use the `ErrorDriver` class here's the implementation.

```csharp
internal class ErrorDriver
{
    private readonly Queue<Exception> _exceptions = new Queue<Exception>();

    public void TryExecute(Action act)
    {
        try
        {
            act();
        }
        catch (Exception ex)
        {
            Trace.WriteLine($"The following exception was caught while executing {act.Method.Name}: {ex}");
            _exceptions.Enqueue(ex);
        }
    }

    public void AssertExceptionWasRaisedWithMessage(string expectedErrorMessage)
    {
        Assert.IsTrue(_exceptions.Any(), $"No exception was raised but expected exception with message: {expectedErrorMessage}");

        var actualException = _exceptions.Dequeue();
        Assert.AreEqual(expectedErrorMessage, actualException.Message);
    }

    public void AssertNoUnexpectedExceptionsRaised()
    {
        if (_exceptions.Any())
        {
            var unexpectedException = _exceptions.Dequeue();
            Assert.IsNull(unexpectedException, $"No exception was expected to be raised but found exception: {unexpectedException}"); 
        }
    }
}
```

As mentioned earlier the `TryExecute` method contains the `try catch` block and catches any exception raised by the action. When an exception is caught it will be written to a trace for troubleshooting and added to the `_exceptions` queue. I'm using a queue so I'm able to handle the exceptions in the order they have occured. Although there will usually only be 0 or 1 exception in the queue.

The `AssertExceptionWasRaisedWithMessage` method is used in the `ErrorSteps` class to verify if an expected error has occured. As you can see I'm only checking the message of the exception and not the type. This is on purpose because the business is not familiar with or interested in exception types and I want to keep my scenarios as functional as possible. A unit test can be used to check the actual exception type.

Lastly, the `AssertNoUnexpectedExceptionsRaised` method is used in the `AfterScenario` hook to check for any unexpected errors.

### Conclusion

With the generic `ErrorDriver` and `ErrorSteps` classes I can quickly create scenario's that both support the happy flow and also failures. This solution also protects against unexpected errors that have occured but are not checked. I case that is often forgotten when using this solution.

A full code example can be found [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/HandlingExceptionsInSpecFlow).
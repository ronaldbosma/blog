---
title: "Handling exceptions in SpecFlow"
date: 2021-04-21T00:00:00+02:00
publishdate: 2021-04-21T00:00:00+02:00
lastmod: 2021-04-21T00:00:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
---

I commonly use Gherkin scenarios to describe the functional specifications of my software and SpecFlow to automate these scenarios. Usually there will be a couple of scenarios describing the happy paths of the feature I'm building but also some scenarios concerning failures. Depending on how the application code works, these failures are represented by exceptions being thrown. In this post I explain how I handle these exceptions.

### Table of contents

- [Retrieve existing person successfully](#retrieve-existing-person-successfully)
- [Retrieve unknown person and expect an error](#retrieve-unknown-person-and-expect-an-error)
- [Expected error was not raised](#expected-error-was-not-raised)

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

With this implementation both scenario's will succeed.

### Expected error was not raised

It's also important that my scenario's fail when something goes wrong. Either because my implementation is wrong or the scenario has an error. Take the following two scenario's for example. I expect a certain error to be raised but this does not happen.

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

Both scenario's should and will fail. The first fails because I'm retrieving a person that exists but I expect the error that the person does not exist. The second scenario fails because I'm expecting an error with the wrong error message.

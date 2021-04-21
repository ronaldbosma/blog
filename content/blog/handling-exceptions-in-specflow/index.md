---
title: "Handling exceptions in SpecFlow"
date: 2021-04-21T00:00:00+02:00
publishdate: 2021-04-21T00:00:00+02:00
lastmod: 2021-04-21T00:00:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
---

I commonly use Gherkin scenarios to describe the functional specifications of my software and SpecFlow to automate these scenarios. Usually there will be a couple of scenarios describing the happy paths of the feature I'm building but also some scenarios concerning failures. Depending on how the application code works, these failures are represented by exceptions being thrown. In this post I explain how I handle these exceptions.

Let's start with the following happy path scenario to retrieve a person.

```gherkin
Scenario: Retrieve existing person

Given the person 'Buffy Summers' is registered
When I retrieve 'Buffy Summers'
Then the person 'Buffy Summers' is returned
```

In the `Given` step we make sure the person exists in our system. We then retrieve the person and verify that the retrieval was successful.

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

It uses a simple in-memory `PersonRepository` to store the people. The `_actualName` field is used to store the person so we can check if the retrieval was successful in the `Then` step. For demo purposes we only store and retrieve the name of the person.

And here's the `PersonRepository` class.

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
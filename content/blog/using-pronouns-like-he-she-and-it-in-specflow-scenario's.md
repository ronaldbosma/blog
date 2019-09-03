---
title: "Using Pronouns Like He She and It in Specflow Scenario's"
date: 2019-09-03T00:00:00+01:00
image: "images/using-pronouns-like-he-she-and-it-in-specflow-scenarios.jpg"
tags: [ "Gherkin", "SpecFlow", ".NET", "Cleaner Code", "Test Automation" ]
comments: true
draft: true
---

Using pronouns like he and she in Gherkin scenario's can improve readability. Automating these can be challenging however.

In this post I'll describe an approach to automating Gherking scenario's with pronouns in which the goal is to not only improve the readability of your scenario's but also keep your SpecFlow code clean and readable.

I'll start with a simple scenario of two people moving in together without using pronouns.

```Gherkin
Given a man called 'John H. Watson'
    And 'John H. Watson' lives at '221B Baker Street, London'
    And a woman called 'Mary Morstan'
    And 'Mary Morstan' lives at '123 Couldn't Find It, London'
When 'John H. Watson' and 'Mary Morstan' move in together at '221B Baker Street, London'
Then 'Mary Morstan' her address is '221B Baker Street, London'
    And 'John H. Watson' his address is '221B Baker Street, London'
```

Because we have multiple persons in the scenario I've chosen to use a dictionary to keep track of the persons across the step definitions using their name as identifier. In the first step I'm creating the person and adding it to the dictionary. In all other steps I'm retrieving the person by name and executing the code related to the specific step. Below is an example implementation of the step definitions.

```C#
[Binding]
class PersonStepDefinitions
{
    private Dictionary<string, Person> _persons = new Dictionary<string, Person>();

    [Given(@"a (.*) called '(.*)'")]
    public void GivenAPersonCalled(Gender gender, string name)
    {
        _persons.Add(name, new Person
        {
            Name = name,
            Gender = gender
        });
    }

    [Given(@"'(.*)' lives at '(.*)'")]
    public void GivenPersonLivesAt(string name, string address)
    {
        var person = _persons[name];
        person.Address = address;
    }
    
    [When(@"'(.*)' and '(.*)' move in together at '(.*)'")]
    public void WhenPerson1AndPerson2MoveInTogetherAt(string name1, string name2, string newAddress)
    {
        var person1 = _persons[name1];
        var person2 = _persons[name2];

        Person.MoveInTogether(person1, person2, newAddress);
    }

    [Then(@"'(.*)' his address is '(.*)'")]
    [Then(@"'(.*)' her address is '(.*)'")]
    public void ThenHisOrHerAddressIs(string name, string expectedAddress)
    {
        var person = _persons[name];
        Assert.AreEqual(expectedAddress, person.Address, $"Unexpected address for {name}");
    }
}
```

This looks pretty straightforward but has a couple of problems.

First off, this solution isn't very robust. If I have a scenario that doesn't start with the `Given a <gender> called '<name>'`, no person is created and steps will start failing. A solution would be to add code to every step definition to create a person if it doesn't already exist and add it to the dictionary. Repeating this in every step would be a bad idea. A helper method could be introduced to fix this issue.

```c#
[Given(@"a (.*) called '(.*)'")]
public void GivenAPersonCalled(Gender gender, string name)
{
    Person person = CreateOrGetPersonByName(name);
    person.Gender = gender;
}

private Person CreateOrGetPersonByName(string name)
{
    if (!_persons.ContainsKey(name))
    {
        _persons.Add(name, new Person { Name = name });
    }

    return _persons[name];
}
```

I'm currently tracking the persons in an instance field of my binding class. So this solution doesn't work well when using multiple binding files to contain my step definitions. We can fix this by creating a context class that keeps track of the persons and sharing this between the binding files using [context injection](https://specflow.org/documentation/Context-Injection/). The binding file could then look something like this.

```c#
private readonly PersonsContext _personsContext;

public PersonSteps(PersonsContext personsContext)
{
    _personsContext = personsContext;
}

[Given(@"a (.*) called '(.*)'")]
public void GivenAPersonCalled(Gender gender, string name)
{
    Person person = _personsContext.CreateOrGetPersonByName(name);
    person.Gender = gender;
}
```

However when introducing pronouns like the example below, things start to get more complicated. Now not only do we have to keep track of the persons but also know who's _he_ and who's _she_. Step definitions can also receive either a name or pronoun making the signature of step definitions weird. Should we rename the `name` parameter to `nameOrPronoun`? Also we're using ' around our name but not around our pronouns.

```Gherkin
Given a man called 'John H. Watson'
    And he lives at '221B Baker Street, London'
    And a woman called 'Mary Morstan'
    And she lives at '123 Couldn't Find It, London'
When they move in together at '221B Baker Street, London'
Then her address is '221B Baker Street, London'
    And his address is '221B Baker Street, London'
```

I've listed the signature of the step definitions I used in the first code example below. You might notice that we're receiving a name in every method. The first step of every step definition method is to convert this name into a `Person` before executing the code that's actually relevant. SpecFlow just happens to have a solution for this in the form of [Step Argument Transformations](https://specflow.org/documentation/Step-Argument-Transformations/).

```c#
void GivenAPersonCalled(Gender gender, string name)
void GivenPersonLivesAt(string name, string address)
void WhenPerson1AndPerson2MoveInTogetherAt(string name1, string name2, string newAddress)
void ThenHisOrHerAddressIs(string name, string expectedAddress)
```

You can find a full code example [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/UsingPronounsInSpecFlowScenarios).
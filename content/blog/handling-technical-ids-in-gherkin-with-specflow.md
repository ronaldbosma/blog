---
title: "Handling technical ids in Gherkin with SpecFlow"
date: 2020-06-27T00:00:00+02:00
image: "images/handling-technical-ids-in-gherkin-with-specflow.jpg"
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
summary: "Gherkin scenarios in Specification by Example are used to describe the functional requirements of your software. They should be readable for the team and also for the business that uses the software. Technical ids don't have a place here. They're usually included in scenarios for test automation purposes but make the them harder to read. So what to do when your code requires a technical id?"
draft: true
---

When you use Specification by Example with the Gherkin syntax and automate your scenarios with SpecFlow, you're bound to encounter situations where you'll need a technical id. For example, to stub data that's retrieved from a repository or external service.

Gherkin scenarios are used to describe the functional requirements of your software. They should be readable for the team and also for the business that uses the software. Technical ids don't have a place here. They're usually included in scenarios for test automation purposes but make them harder to read. So, what to do when your code requires a technical id?

Let start with an example scenario:

```Gherkin
Given the following people
    | Id                                   | Address                           |
    | 9A9EE974-9062-4AB3-98C8-E83B0A5A3BAA | 221B Baker Street, London, UK     |
    | 70EC5DE6-F569-4092-AF58-DA857F44279E | 1630 Revello Drive, Sunnydale, US |
    | 0545383F-28E7-4968-9525-11829915ED89 | 31 Spooner Street, Quahog, US     |
    | EF03C690-6F29-43F0-931F-546938F2869F | 12 Grimmauld Place, London, UK    |
When person '0545383F-28E7-4968-9525-11829915ED89' moves to '742 Evergreen Terrace, Springfield, US'
Then the new address of person '0545383F-28E7-4968-9525-11829915ED89' is '742 Evergreen Terrace, Springfield, US'
```

This scenario describes functionality for moving a person from one address to another. The technical id is used to identify the specific person that is moving.

The `MovingService` class that implements the functionality has a simple `MovePerson` method that retrieves a person by its id from a repository and sets the new address.

```csharp
public class MovingService
{
    private readonly IPeopleRepository _peopleRepository;

    public MovingService(IPeopleRepository peopleRepository)
    {
        _peopleRepository = peopleRepository ?? throw new ArgumentNullException(nameof(peopleRepository));
    }

    public void MovePerson(Guid personId, string newAddress)
    {
        var person = _peopleRepository.GetById(personId);
        person.Address = newAddress;
    }
}
```

The corresponding SpecFlow glue code that automates the scenario:
- injects a simple in-memory stub into `MovingService`
- adds the people specified in the `Given` step
- calls the `MovingService.MovePerson` method 
- and verifies that the specified person has the new address.

```csharp
[Binding]
class InitialScenarioSteps
{
    private readonly PeopleRepositoryStub _peopleRepositoryStub = new PeopleRepositoryStub();
    private readonly MovingService _movingService;

    public InitialScenarioSteps()
    {
        _movingService = new MovingService(_peopleRepositoryStub);
    }

    [Given(@"the following people")]
    public void GivenTheFollowingPeople(Table table)
    {
        var people = table.CreateSet<Person>();
        _peopleRepositoryStub.AddRange(people);
    }

    [When(@"person '(.*)' moves to '(.*)'")]
    public void WhenPersonMovesTo(Guid personId, string newAddress)
    {
        _movingService.MovePerson(personId, newAddress);
    }

    [Then(@"the new address of person '(.*)' is '(.*)'")]
    public void ThenTheNewAddressOfPersonIs(Guid personId, string expectedAddress)
    {
        var person = _peopleRepositoryStub.GetById(personId);
        Assert.AreEqual(expectedAddress, person.Address);
    }
}
```

## Refactoring our scenario

If we look at the scenario again you can see that a technical `Guid` is used as the id to identify a person.

```Gherkin
Given the following people
    | Id                                   | Address                           |
    | 9A9EE974-9062-4AB3-98C8-E83B0A5A3BAA | 221B Baker Street, London, UK     |
    | 70EC5DE6-F569-4092-AF58-DA857F44279E | 1630 Revello Drive, Sunnydale, US |
    | 0545383F-28E7-4968-9525-11829915ED89 | 31 Spooner Street, Quahog, US     |
    | EF03C690-6F29-43F0-931F-546938F2869F | 12 Grimmauld Place, London, UK    |
When person '0545383F-28E7-4968-9525-11829915ED89' moves to '742 Evergreen Terrace, Springfield, US'
Then the new address of person '0545383F-28E7-4968-9525-11829915ED89' is '742 Evergreen Terrace, Springfield, US'
```

For our test automation code, the id is super helpful because we can just pass it into to the `MovingService.MovePerson` method. For the business, requirements engineers, and others who might be less technical, this scenario is probably more difficult to read.

Also, the user interface that would implement this feature would most likely not show this id to the user at all. Making it even harder for users to understand what to expect.

It's better to look for a functional id to identify our person in this example. Preferably one that is commonly used by the business. Usually one property or a combination of properties of an object can be used to uniquely identify that object. 

The name of a person is ideal for our specific scenario because it's often used in real life to identify a person. So, we replace the technical id with the name of the person in our scenario.

```Gherkin
Given the following people
    | Name            | Address                           |
    | Sherlock Holmes | 221B Baker Street, London, UK     |
    | Buffy Summers   | 1630 Revello Drive, Sunnydale, US |
    | Peter Griffin   | 31 Spooner Street, Quahog, US     |
    | Sirius Black    | 12 Grimmauld Place, London, UK    |
When 'Peter Griffin' moves to '742 Evergreen Terrace, Springfield, US'
Then the new address of 'Peter Griffin' is '742 Evergreen Terrace, Springfield, US'
```

> Note that the functional id that you've chosen does not have to be a field that is unique within your system or database. Multiple people might have the same name in our system. However, as long as the name is unique within our scenarios, there is no problem.

This scenario looks a lot more readable to me and is more aligned with our business in terms of language. The only problem is that our code expects a technical id. So, we need to convert our functional id in the glue code to the technical id expected by our software.

I've created a simple helper method to convert a person's name to an id. It takes a `string` as parameter and returns a `Guid`. See the code snippet below.

```Gherkin
private static Guid NameToId(string name)
{
    // Convert the name to an integer value and make sure it's always a positive number
    int personId = Math.Abs(name.GetHashCode());
    // Convert the integer personId to a string of 32 numbers so we can create a valid Guid
    string personIdGuid = personId.ToString().PadLeft(32, '0');
    
    return Guid.ParseExact(personIdGuid, "N");
}
```

> Since a `Guid` must be 32 characters long and is limited to numbers and the letters 'A' through 'F', I'm converting the name to a number first with `GetHashCode`. This will result in a number with a maximum length of 10. The number is then padded with zeros to create a 32-character long string of numbers that can be converted to a valid `Guid`.

If we need the id of a person, but only have the name, we simply call `NameToId` and use the result as the person's id. See the following example for the `When` step of our scenario.

```csharp
[When(@"'(.*)' moves to '(.*)'")]
public void WhenMovesTo(string name, string newAddress)
{
    Guid personId = NameToId(name);
    _movingService.MovePerson(personId, newAddress);
}
```

With this little trick we have scenarios that are easy to read for all parties involved and we can automate them too.

You can find a working code example [here](https://github.com/ronaldbosma/blog-code-examples/tree/master/HandlingTechnicalIdsInGherkinWithSpecFlow).
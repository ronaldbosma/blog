---
title: "Where to position SpecFlow in the Test Pyramid"
date: 2023-02-03T00:00:00+02:00
publishdate: 2023-02-03T00:00:00+02:00
lastmod: 2023-02-03T00:00:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
draft: true
---

In my software development projects I prefer to use Specification by Example to explore and document the specifications of the applications to build. I use Gherkin to describe the specifications and [SpecFlow](https://specflow.org) to execute them. Resulting in a suite of automated (acceptance) tests.

As with all tests, there are different levels on which a Gherkin scenario can be automated using SpecFlow (or Cucumber for that matter). In this blog post I consider the different levels of the test pyramid and describe my preferred level for SpecFlow tests. 

The insights I share are based on my own experience and inspired other sources like [Martin Fowler's Blog](https://martinfowler.com/tags/testing.html).

### Table of Contents

- [Test Pyramid](#test-pyramid)
  - [UI Tests](#ui-tests)
  - [Service Tests](#service-tests)
  - [Unit Tests](#unit-tests)
- [Test Pyramid Extended](#test-pyramid-extended)
  - [Component Tests](#component-tests)
- [SpecFlow in the Test Pyramid](#specflow-in-the-test-pyramid)
  - [Why I skip the Controller](#why-i-skip-the-controller)
  - [Why I include the repository and database](#why-i-include-the-repository-and-database)
- [Conclusion](#conclusion)

### Test Pyramid

The classis test pyramid, as show in the image below, has 3 levels: UI, Service and Unit.

![Test Pyramid](../../../../../images/where-to-position-specflow-in-the-test-pyramid/test-pyramid.png)

The higher the level in the pyramid, the higher the integration and coverage of your tests is. But tests will also be slower and more fragile. The lower you get in the pyramid, the higher the isolation, speed and stability of your tests. The coverage per test will be lower though.

Considering these factors, it is preferred to have automated tests covering all levels. Most tests will be automated on the lowest level. Fewer test will be automated on the Service and UI level, mainly focusing on the happy flow of important user capabilities and core processes.

In the next part I'll go throught he different levels and describe their pros and cons.

#### UI Tests

UI tests are end-to-end tests that interact with the system under test through the UI. 

See the following context diagram to illustrate the scope of what UI tests cover.

![UI Tests Scope](../../../../../images/where-to-position-specflow-in-the-test-pyramid/ui-tests-scope.png)

In our example we have a separate UI that interacts with two internal API's that we own. Both API's have their own database. The UI and the Order API also communicatie with a Zip Code API of an external 3rd party.

When automating tests on the UI level, all these parts are part of the scope that is covered.

Pros:
- Initially easy to setup with 'record & playback' tools.
- Coverage per test is high because it covers the UI, underlying services, databases, etc.

Cons:
- Slow, resulting in long build and release times.
- Fragile. These tests often break due to environment related issues. Like a database that is temporary timing out or an external API that is unavailable.
- The UI and underlying services must be deployed. Meaning that these test can only be performed in a release pipeline after deployment on an environment.
- Difficult to maintain, because there is a lot to take into account. You have to not only consider the UI, but also the available data in the database and external services for instance.

Because of the disadvantages, I usually keep the number of UI tests to a minimum. I use them as smoke tests to check if the deployment of the UI was successful and test if the integration with underlying services works. I do this by automating the most important user capabilities and core processes.

> NOTE: these tests should not be confused with unit tests that test a small part of the code in the UI. When performing unit tests, all external dependencies are replaced by doubles. See [Unit Tests](#unit-tests) for more info.

#### Service Tests

Service tests skip the UI and talk directly to the underlying services. The interact with a REST API or send messages to an Azure Service Bus for example.

The scope of these tests can cover a single service or a combination of multiple services.

![Service Test Scope](../../../../../images/where-to-position-specflow-in-the-test-pyramid/service-tests-scope.png)

When testing the Product API in our example, the scope would only be the Product API and its database. The Order API has more dependencies, so a test interacting with the Order API would also cover parts of the Product and Zip Code API.

Pros:
- Avoids dealing with the complexity that comes with UI test automation.
- Still coverages a large part of the application per test.

Cons:
- Still slow, albeit generally faster then UI tests.
- Can be fragile when the service under test has dependencies to other services.
- Because of the external dependencies, the services must be deployed on an environment. Meaning that these test can only be performed in a release pipeline.

I like to use service test when UI tests are to difficult to setup or to test smaller parts of larger processes. They are also great as a smoke test on a service after deployment. 

#### Unit Tests

A unit test tests a single method or class. External dependencies are replaced by test doubles.

Pros:
- Easy to create because of the small scope, making them easy to understand and maintain.
- Quick. They run in-process.
- Can be run in an automated build pipeline and on a local development machine. No deployment required.

Cons:
- Does not test integration between parts of an application.
- Sensitive to change when the code under test is refactored.

As the classic test pyramid suggest, the bulk of your tests should be on this level. Keep in mind though that you can have a test coverage of 100% with only unit tests, but still have application that does not work because the parts don't integrate together.

### Test Pyramid Extended

When you look at the 3 levels of the classic test pyramid in regards to automating Gherkin scenarios, the scope of a unit test is almost always to small. A Gherkin scenario usually describe functionality that is implemented by a combination of classes and methods working together. When applying a good focus they tend to cover functionality that resides inside a single service or API, meaning that the scope of UI tests is to high and usually also of service tests. That's why I often introduce an extra level in the test pyramid as shown below.

![Test Pyramid Extended](../../../../../images/where-to-position-specflow-in-the-test-pyramid/test-pyramid-extended.png)

#### Component Tests

As Martin Fowler explains on [ComponentTest](https://martinfowler.com/bliki/ComponentTest.html), a component test is a test that limits the scope to a portion of the system under test. They can be as large or small as you define your components and will replace external dependencies with test doubles.

For me a component test is executed in-process, similar to a unit test, but it covers a larger scope where several classes work together. 

The image below shows the general overview of the structure inside a (.NET) Web API. The entry point is a _Controller_ that defines operations on the API. It communicates with application logic through a _Service_ class. Interactions with the database are done through an ORM like Entity Framework and abstracted away with the _Repository_ pattern.

![Component Test Scope](../../../../../images/where-to-position-specflow-in-the-test-pyramid/component-tests-scope.png)

Because a component test can be as large or small as you define your components, it can cover all parts shown in the image above or subset.

Pros:
- Quick. They run in-process.
- Can be run in an automated build pipeline and on a local development machine. No deployment required.
- Less sensitive to change during refactoring than unit tests.

Cons:
- The scope they test is larger than that of unit tests. Making it a bit more difficult to maintain, but still al ot easier in comparison to Service and UUI tests.




> Include image of test 'tree' and mention that coverage is high with component tests so the need for unit tests is lower.




### SpecFlow in the Test Pyramid

I find the component test level ideal for automating Gherkin scenarios with SpecFlow. Their scope is not to small as it usually is with unit tests, but I still get the advantages of in-process tests that can run in an automated build pipeline and on my local development machine without requiring a deployment.

When I automate scenarios with SpecFlow I use the following scope. As you can see, I tend to skip the Controller and include the database.

![SpecFlow Component Test Scope](../../../../../images/where-to-position-specflow-in-the-test-pyramid/specflow-component-tests-scope.png)

#### Why I skip the Controller

It is not uncommon for an API to support multiple versions of a contract or even different protocols, like REST and gRPC. This would mean multiple controllers, that all use the same application/business logic, as shown below.

![Multiple Controllers](../../../../../images/where-to-position-specflow-in-the-test-pyramid/multiple-controllers.png)

Which controller would you use to automate a Gherkin scenario? Or would you duplicate the scenarios and implement them on every controller?

Controllers are focused on technology specific concerns, like what status code to return from a REST API if a resource can't be found. It is the application/business logic working together with the other classes that actually implement a Gherkin scenario. That's why I skip the Controllers in my SpecFlow tests.

#### Why I include the repository and database

Most of the logic that is described in a Gherkin scenario will reside in the application/business logic and in the aggregates/entities. With that consideration in mind, in the pas I did not include the repository or database in my SpecFlow tests. Instead I stubbed the repository with a test double.

There are two reasons why I've found this approach to be bad.

##### Reason 1: stubbing can be difficult and the number of different situations to support tend to get out of hand

One of the advantages of Gherkin is that you can define `Given` steps that can be reused across scenarios and features. It can for instance makes sure that books are available in the system when executing the scenario. See the following snippet.

```gherkin
Given the books
    | EAN           | Name                                    |
    | 9781617290084 | Specification by Example                |
    | 9781801815710 | Infrastructure as Code with Azure Bicep |
    | 9781680504989 | The Cucumber for Java Book              |
When ...
```

In the first scenario we might retrieve all books. A call to `respository.GetAllBooks()` will performed which we have to stub in the step definition of the `Given` step. In a second scenario we might want to retrieve a single book by its EAN (European Article Number). A call to `respository.GetBookByEAN(ean)` is performed which we also have to stub in the step definition of the `Given` step.

As the functionality of the application grows, so will the number of methods on our repository to retrieve books. Resulting in more and more configuration on our stub. And to make it generic, the stubbing logic will tend to mimic the implementation of the repository.

By including the repository and database in the scope of the component test, it becomes much easier to setup the data specified in a `Given` step. You can simply insert it in the database. 

##### Reason 2: filter logic is part of the scenario

The second reason why a include the repository and database is that it's not uncommon that code in for instance the repository is part of the scenario.

Take the following scenario for example. We're searching for a book. This is implement in the repository by executing a query with filter on the database. If we had mocked the repository, we would not be able to test the specified logic.

```gherkin
Given the books
    | EAN           | Name                                    |
    | 9781801815710 | Infrastructure as Code with Azure Bicep |
    | 9781617290084 | Specification by Example                |
    | 9781680504989 | The Cucumber for Java Book              |
When I search books for the phrase 'Specification'
Then I expect the following book to be found
    | EAN           | Name                                    |
    | 9781617290084 | Specification by Example                |
```

To keep my component tests fast I tend to use an in-memory version of a database. Entity Framework for example not only supports SQL Server, but also has an in-memory provider and a SQLite provider that are designed for test automation. See [Testing without your production database system](https://learn.microsoft.com/en-us/ef/core/testing/testing-without-the-database) for more information.

### Conclusion


>TODO: conclusion
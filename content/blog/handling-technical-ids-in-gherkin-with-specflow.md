---
title: "Handling technical id's in Gherkin with SpecFlow"
date: 2020-06-27T00:00:00+02:00
image: "images/handling-technical-ids-in-gherkin-with-specflow.jpg"
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
summary: "In this post I'll show a simple trick on how to handle technical id's in Gherkin using SpecFlow."
draft: true
---

When you use Specification by Example with the Gherkin syntax and automate your scenario's with SpecFlow, you're bound to encounter situations where you'll need a technical id. For example to stub data retrieved by the id from a repository or external service.

Gherkin scenario's in Specification by Example are used to describe the functional requirements of your software. They should be readable for the team, but also for the business people that use the software. Technical id's don't have a place here. So what to do when your code requires a technical id.

Let start with an example scenario:

```Gherkin

Given the following people
    | Id | Name            | Address                           |
    | 1  | Sherlock Holmes | 221B Baker Street, London, UK     |
    | 2  | Buffy Summers   | 1630 Revello Drive, Sunnydale, US |
    | 3  | Peter Griffin   | 31 Spooner Street, Quahog, US     |
    | 4  | Sirius Black    | 12 Grimmauld Place, London, UK    |
When person 2 moves to '742 Evergreen Terrace, Springfield, US'
Then the new address of person 2 is '742 Evergreen Terrace, Springfield, US'
```


---
title: "Handling exceptions in SpecFlow"
date: 2021-04-21T00:00:00+02:00
publishdate: 2021-04-21T00:00:00+02:00
lastmod: 2021-04-21T00:00:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
---

I commonly use Gherkin scenarios to describe the functional specifications of my software and SpecFlow to automate these scenarios. Usually there will be a couple of scenarios describing the happy paths of the feature I'm building but also some scenarios concerning failures. Depending on how the application code works, these failures are represented by exceptions being thrown. In this post I explain how I handle these exceptions.

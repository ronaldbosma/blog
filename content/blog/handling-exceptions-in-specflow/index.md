---
title: "Handling exceptions in SpecFlow"
date: 2021-04-21T00:00:00+02:00
publishdate: 2021-04-21T00:00:00+02:00
lastmod: 2021-04-21T00:00:00+02:00
tags: [ "Gherkin", "SpecFlow", "Specification by Example", "ATDD", "BDD", "Test Automation", "Cleaner Code" ]
---

I commonly use Gherkin scenarios to describe the functional specifictions of my software and SpecFlow to automate these scenarios. Usually there will be a couple of scenarios describing the happy paths of the feature I'm building but also some scenarios about failures. Depending on how the application code works, these failures can be represented by exceptions. In this post I explain how I handle these exceptions.

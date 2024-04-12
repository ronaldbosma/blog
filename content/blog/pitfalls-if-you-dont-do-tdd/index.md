---
title: "Pitfalls if you don't do TDD"
date: 2024-04-12T00:00:00+01:00
publishdate: 2024-04-12T00:00:00+01:00
lastmod: 2024-04-12T00:00:00+01:00
tags: [ "TDD", "Test Automation" ]
summary: "Automated testing has become increasingly standard practice. Companies need to deliver new software to production faster, necessitating extensive automation. We observe two major approaches: developers writing their tests after implementing new features and developers doing so beforehand. Writing tests before coding is a technique known as Test Driven Development (TDD). This approach enables you to write high-quality code. What are the pitfalls of not applying TDD? In this post I shares some of practical insights."
---

Automated testing has become increasingly standard practice. Companies need to deliver new software to production faster, necessitating extensive automation. We observe two major approaches: developers writing their tests after implementing new features and developers doing so beforehand. Writing tests before coding is a technique known as Test Driven Development (TDD). This approach enables you to write high-quality code. What are the pitfalls of not applying TDD? In this post I shares some of practical insights.


### Benefit of TDD: Focus on Code

The idea behind TDD is to write a test before writing the corresponding piece of code that the test will validate. You run the test, and it fails because the associated code hasn't been implemented yet. The test is then red. After the test fails, you write the corresponding code. When you rerun the test, it should pass, turning green. 

Now that the test is green, you have the opportunity to refactor and improve the code quality. With the test, you can continually verify that the code still works as expected. This cycle is known as the Red-Green-Refactor cycle.

The cycle repeats until the full functionality is implemented. The result is a working piece of software that is automatically tested and has nearly 100 percent test coverage. 

I've been writing software this way for years. It helps me stay focused on the code I need to write. Each test is a requirement the code must meet. This allows me to incrementally write new features, and in the end, I have code that I'm sure does what it's supposed to do.


### Pitfall 1: Testing Nothing

One of the biggest pitfalls of writing tests afterward is writing tests that test nothing. I've often written a test that immediately passed even though the code to be tested wasn't there yet: a good indication that there's something wrong with your test! By writing and executing the test first, you get quick feedback if you've made a mistake. 

When writing tests afterward, the step where the test fails first is skipped. The test can always be green, even if there's a mistake in it. 

Take the following test as an example. I've written a function `GetFullName` that combines a first name, infix, and last name into a full name. In my test, I want to verify that this function returns the correct result.

```csharp
[TestMethod]
public void Test()
{
    string firstName = "Jan";
    string infix = "de";
    string lastName = "Boer";

    string result = GetFullName(firstName, infix, lastName);

    Assert.AreEqual(result, result);
}
```

You probably see the mistake already. On the last line, I compare 'result' with 'result'. This will never produce an error. The test will always pass, even if `GetFullName` returns an invalid result. 

Although this is a simple example that you might think never happens in practice, a colleague recently encountered this mistake. When TDD is applied, such errors would not be made.


### Pitfall 2: Code is Poorly Testable

When tests are written afterwards, the focus is first on the functionality of the new code. Often, no thought is given to the testability of the code. Only when the code is complete do you realize how difficult it is to test the code automatically, and you'll have to refactor. Because you don't have automated tests yet to check that your refactoring changes don't break anything, this is much riskier. 

A situation I often encounter in practice is the use of code from libraries that are not set up for testing. An example of this in older versions of ASP.NET is the `HttpContext` object. It is populated by the ASP.NET runtime and often used as a singleton in code. However, it's difficult to populate the object from unit tests in the same way ASP.NET would. 

With TDD, you're testing the code you write from the beginning. You immediately encounter any problems and can quickly fix them. This saves time, and all tests and code you write afterwards benefit from it.

> Insufficient Test Coverage  
> 
> In addition to focusing on implementing functionality step by step through tests, one of the other major advantages of TDD is the high level of test coverage (also known as code coverage). Because you write a test first and then the corresponding code, it's relatively simple to achieve a code coverage percentage above 95 percent. Now, code coverage isn't a goal in itself, but the higher the percentage, the more confidence you can have that changes won't introduce bugs. It's important to note that the quality of your tests is crucial.
> 
> The example test in pitfall 1 probably has a code coverage of 100 percent but tests nothing. As a result, you won't discover any bugs when modifying this function. The test gives a false sense of confidence in this case.
>
> To validate the quality of your tests, you can use a mutation testing tool. Mutation testing is a topic in itself that I won't delve into now, but it's definitely worth looking into. For more information, you can visit https://stryker-mutator.io/, an open-source tool written by colleagues.


### Pitfall 3: Writing Tests Based on Already Implemented Code

One of the most common pitfalls regarding insufficient test coverage is writing tests based on existing code. An analysis is made of the written code, and scenarios are chosen based on that to be automated. This often overlooks requirements that may also be relevant but haven't been implemented.

A recent production outage at one of my clients is a good example. Code was written to apply the circuit breaker pattern in response to specific errors. A test was written to check this behavior. Unfortunately, there was no test to check that for other types of errors, the circuit breaker pattern would not apply. The result was a bug in the production environment. 

With TDD, you work through the various requirements that you need to implement test by test. As a result, many more requirements are checked by a test because you're more aware of them. This ultimately results in better test coverage.


### Pitfall 4: Rushing Test Writing

One of the most unpleasant tasks I've had to do as a developer in the past is writing tests for code someone else wrote. I see writing new software as a creative process, and few tasks in software development are less creative than writing tests afterward. The creative process of writing software is over, and all that's left is to check that it works.

As a result, you often see the minimum set of tests being written that's needed to meet the code coverage guidelines. This often doesn't provide sufficient test coverage of the relevant scenarios, increasing the risk of bugs in future changes. With TDD, writing tests is part of the creative process. This keeps the work continuously interesting and not a tedious task to be performed afterward.


### Pitfall 5: Not Writing Tests at All

When there's pressure and tests need to be written afterwards, they're often the first casualties; they're postponed to be picked up in the next sprint or maybe never written at all. The risk of bugs in future releases is much higher. 

Some people also sometimes have the illusion that writing automated tests only takes time. However, my experience is that TDD actually saves time. While building the functionality, code is not only tested immediately but also frequently and quickly. If you were to do this manually, it would take much more time.


### Conclusion

TDD is a technique that every developer should master. Because the thought process is slightly different, it can be difficult to start with. But once you master this technique, it can offer you many benefits and help you avoid the pitfalls mentioned above.

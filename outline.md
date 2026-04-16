![](media/image1.png){width="2.3969542869641294in"
height="1.3962259405074366in"}

**Developing on AWS**

**Course Length:** 3 Days

**Course Description:**

This course teaches experienced developers how to programmatically
interact with AWS services to build web solutions. It guides you through
a high-level architectural discussion on resource selection and dives
deep into using the AWS Software Development Kits (AWS SDKs) and Command
Line Interface (AWS CLI) to build and deploy your cloud applications.
You will build a sample application during this course, learning how to
set up permissions to the development environment, adding business logic
to process data using AWS core services, configure user authentications,
deploy to AWS cloud, and debug to resolve application issues. The course
includes code examples to help you implement the design patterns and
solutions discussed in the course. The labs reinforce key course content
and help you to implement solutions using the AWS SDK for Python, .Net,
and Java, the AWS CLI, and the AWS Management Console.

**Course Objectives:**

- Build a simple end-to-end cloud application using AWS Software
  Development Kits (AWS SDKs), Command Line Interface (AWS CLI), and
  IDEs.

- Configure AWS Identity and Access Management (IAM) permissions to
  support a development environment.

- Use multiple programming patterns in your applications to access AWS
  services.

- Use AWS SDKs to perform CRUD (create, read, update, delete) operations
  on Amazon Simple Storage Service (Amazon S3) and Amazon DynamoDB
  resources.

- Build AWS Lambda functions with other service integrations for your
  web applications.

- Understand the benefits of microservices architectures and serverless
  applications to design.

- Develop API Gateway components and integrate with other AWS services.

- Explain how Amazon Cognito controls user access to AWS resources.

- Build a web application using Cognito to provide and control user
  access.

- Use DevOps methodology to reduce the risks associated with traditional
  application releases and identify AWS services that help in
  implementing DevOps practices.

- Use AWS Serverless Application Model (AWS SAM) to deploy an
  application.

- Observe your application build using Amazon X-Ray

> **This course is intended for:**

- Software developers

- Solution architects

- IT workers who want to improve their developing skills using AWS
  Services

> **Prerequisites:**

- AWS Technical Essentials

- Working knowledge of AWS core services

- Programming experience in any one of the following languages:

  - Python

  - .NET

  - Java

**Course Outline:**

> **Module 1: Course Overview**

- Logistics

- Student resources

- Agenda

- Introductions

> **Module 2: Building a Web Application on AWS**

- Discuss the architecture of the application you are going to build
  during this course

- Explore the AWS services needed to build your web application

- Discover how to store, manage, and host your web application

> **Module 3: Getting Started with Development on AWS**

- Describe how to access AWS services programmatically

- List some programmatic patterns and how they provide efficiencies
  within AWS SDKs and AWS CLI

- Explain the value of AWS Cloud9

> **Module 4: Getting Started with Permissions**

- Review AWS Identity and Access Management (IAM) features and
  components permissions to support a development environment

- Demonstrate how to test AWS IAM permissions

- Configure your IDEs and SDKs to support a development environment

- Demonstrate accessing AWS services using SDKs and AWS Cloud9

> **Lab 1: Configure the Developer Environment**

- Connect to a developer environment

- Verify that the IDE and the AWS CLI are installed and configured to
  use the application profile

- Verify that the necessary permissions have been granted to run AWS CLI
  commands

- Assign an AWS IAM policy to a role to delete an Amazon S3 bucket

> **Module 5: Getting Started with Storage**

- Describe the basic concepts of Amazon S3

- List the options for securing data using Amazon S3

- Define SDK dependencies for your code

- Explain how to connect to the Amazon S3 service

- Describe request and response objects

> **Module 6: Processing Your Storage Operations**

- Perform key bucket and object operations

- Explain how to handle multiple and large objects

- Create and configure an Amazon S3 bucket to host a static website

- Grant temporary access to your objects

- Demonstrate performing Amazon S3 operations using SDKs

> **Lab 2: Develop Solutions Using Amazon S3**

- Interact with Amazon S3 programmatically using AWS SDKs and the AWS
  CLI

- Create a bucket using waiters and verify service exceptions codes

- Build the needed requests to upload an Amazon S3 object with metadata
  attached Build requests to download an object from the bucket, process
  data, and upload the object back to the bucket

- Configure a bucket to host the website and sync the source files using
  the AWS CLI

- Add IAM bucket policies to access the S3 website.

> **Module 7: Getting Started with Databases**

- Describe the key components of DynamoDB

- Explain how to connect to DynamoDB

- Describe how to build a request object

- Explain how to read a response object

- List the most common troubleshooting exceptions

> **Module 8: Processing Your Database Operations**

- Develop programs to interact with DynamoDB using AWS SDKs

- Perform CRUD operations to access tables, indexes, and data

- Describe developer best practices when accessing DynamoDB

- Review caching options for DynamoDB to improve performance

- Perform DynamoDB operations using SDK

> **Lab 3: Develop Solutions Using Amazon DynamoDB**

- Interact with Amazon DynamoDB programmatically using low-level,
  document, and highlevel APIs in your programs

- Retrieve items from a table using key attributes, filters,
  expressions, and paginations

- Load a table by reading JSON objects from a file

- Search items from a table based on key attributes, filters,
  expressions, and paginations

- Update items by adding new attributes and changing data conditionally

- Access DynamoDB data using PartiQL and object-persistence models where
  applicable

> **Module 9: Processing Your Application Logic**

- Develop a Lambda function using SDKs

- Configure triggers and permissions for Lambda functions

- Test, deploy, and monitor Lambda functions

> **Lab 4: Develop Solutions Using AWS Lambda Functions**

- Create AWS Lambda functions and interact programmatically using AWS
  SDKs and AWS CLI

- Configure AWS Lambda functions to use the environment variables and to
  integrate with other services

- Generate Amazon S3 pre-signed URLs using AWS SDKs and verify the
  access to bucket objects

- Deploy the AWS Lambda functions with .zip file archives through your
  IDE and test as needed

- Invoke AWS Lambda functions using the AWS Console and AWS CLI

> **Module 10: Managing the APIs**

- Describe the key components of API Gateway

- Develop API Gateway resources to integrate with AWS services

- Configure API request and response calls for your application
  endpoints

- Test API resources and deploy your application API endpoint

- Demonstrate creating API Gateway resources to interact with your
  application APIs

> **Lab 5: Develop Solutions Using Amazon API Gateway**

- Create RESTful API Gateway resources and configure CORS for your
  application

- Integrate API methods with AWS Lambda functions to process application
  data

- Configure mapping templates to transform the pass-through data during
  method integration

- Create a request model for API methods to ensure that the pass-through
  data format complies with application rules

- Deploy the API Gateway to a stage and validate the results using the
  API endpoint

> **Module 11: Building a Modern Application**

- Describe the challenges with traditional architectures

- Describe the microservice architecture and benefits

- Explain various approaches for designing microservice applications

- Explain steps involved in decoupling monolithic applications

- Demonstrate the orchestration of Lambda Functions using AWS Step
  Functions

> **Module 12: Granting Access to Your Application Users**

- Analyze the evolution of security protocols

- Explore the authentication process using Amazon Cognito

- Manage user access and authorize serverless APIs

- Observe best practices for implementing Amazon Cognito

- Demonstrate the integration of Amazon Cognito and review JWT tokens

> **Lab 6: Capstone -- Complete the Application Build**

- Create a Userpool and an Application Client for your web application
  using

- Add new users and confirm their ability to sign-in using the Amazon
  Cognito CLI

- Configure API Gateway methods to use Amazon Cognito as an authorizer

- Verify JWT authentication tokens are generated during API Gateway
  calls

- Develop API Gateway resources rapidly using a Swagger importing
  strategy

- Set up your web application frontend to use Amazon Cognito and API
  Gateway configurations and verify the entire application functionality

> **Module 13: Deploying Your Application**

- Identify risks associated with traditional software development
  practices

- Understand DevOps methodology

- Configure an AWS SAM template to deploy a serverless application

- Describe various application deployment strategies

- Demonstrate deploying a serverless application using AWS SAM

> **Module 14: Observing Your Application**

- Differentiate between monitoring and observability

- Evaluate why observability is necessary in modern development and key
  components

- Understand CloudWatch's part in configuring the observability

- Demonstrate using CloudWatch Application Insights to monitor
  applications

- Demonstrate using X-Ray to debug your applications

> **Lab 7: Observe the Application Using AWS X-Ray**

- Instrument your application code to use AWS X-Ray capabilities

- Enable your application deployment package to generate logs

- Understand the key components of an AWS SAM template and deploy your
  application

- Create AWS X-Ray service maps to observe end-to-end processing
  behavior of your application

- Analyze and debug application issues using AWS X-Ray traces and
  annotations

> **Module 15: Course Wrap-up**

# Amazon Transcribe Live Call Analytics (LCA) Sample Solution
*Companion AWS blog post: [Livecall analytics for your contact center with Amazon language AI services](http://www.amazon.com/live-call-analytics)*
## Overview
Your contact center connects your business to your constituents, enabling customers to order products, callers to request support, clients to make appointments, and much more. When calls go well, callers retain a positive image of your brand, and are likely to return and to recommend you to others. And the converse, of course, is also true.
So naturally you want to do what you can to ensure that your callers have a good experience. You see two aspects to this:
1.	Help supervisors to assess the quality of your caller’s experiences in real time. For example, your supervisors need to know if initially unhappy callers become happier as the call progresses? And if not, why?  What actions can be taken, before the call ends, to assist the agent to improve the customer experience for call that are not going well?
2.	Help agents to optimize the quality of your caller’s experiences. For example, can you deploy live call transcription removing the need for your agents to take notes during calls, freeing them to focus more attention on providing positive customer interactions.
You’ve heard that Contact Lens for Amazon Connect provides real time supervisor and agent assist features that sound like they are just what you need, but you are not yet using Amazon Connect. You need a solution that will work with your existing contact center.

Amazon machine learning services like Amazon Transcribe and Amazon Comprehend provide feature-rich APIs that you can use to transcribe and extract insights from your contact center audio at scale. Although you could build your own custom call analytics solution using these services, that requires time and resources. You figure that someone must have done this before, and that with luck you’ll find a solution that you can re-use. 

Live Call Analytics, or LCA, does most of the heavy lifting associated with providing an end-to-end sample solution that can plug into your contact center and provide the intelligent insights that you need. 

## Architecture
![lca-architecture](./images/architecture-diagram.png)
The demo Asterisk server is configured to use Amazon Chime Voice Connector which provides the phone number and SIP trunking needed to route inbound and outbound calls. When you configure LCA to integrate with your contact center instead of the demo Asterisk server, the Chime Voice Connector is configured to integrate instead with your existing contact center using SIP-based media recording (SIPREC) or network-based recording (NBR). In both cases, the Chime voice connector streams audio to Kinesis Video Streams (KVS) using 2 streams per call, one for the Caller and one for the Agent.

When a new KVS stream is initiated, an event is fired using Amazon EventBridge. This event triggers an AWS Lambda function which in turn uses an SQS queues to initiate a new call processing job in AWS Fargate, a serverless compute service for containers. A single container instance processes multiple calls simultaneously. AWS auto-scaling provisions and de-provisions additional containers dynamically as needed to handle changing call volumes.
The Fargate container immediately creates a streaming connection with Amazon Transcribe and starts consuming and relaying audio fragments from KVS to Transcribe. The container writes the streaming transcription results in real time to a DynamoDB table. 

An AWS Lambda function, the Call Event Stream Processor, fed by DynamoDB streams, processes and enriches call metadata and transcription segments. The event processor function interfaces with AWS AppSync to persist changes (mutations) in DynamoDB and to send real time updates to logged in web clients. 

The LCA web UI assets are hosted on Amazon S3 and served via Amazon CloudFront. Authentication is provided by Amazon Cognito. In demo mode, user identities are configured in an Amazon Cognito user pool; in a production setting you would likely configure Cognito to integrate with your existing identity provider (IdP) so authorized users can log in with their corporate credentials.

When the user is authenticated, the web application establishes a secure GraphQL connection to the AWS AppSync API, and subscribes to receive real time events such as new calls and call status changes for the Calls list page, and new or updated transcription segments and computed analytics for the Call Details page. 
The entire processing flow, from ingested speech to live web page updates, is event driven, and so the end to end latency is small - typically just a few seconds.


## Deployment instructions
### (optional) Build and Publish LCA CloudFormation artifacts
_Note: Perform this step only if you want to create deployment artifacts in your own account. Otherwise, we have hosted a CloudFormation template for 1-click deployment in the [deploy](#deploy) section_.

*Pre-requisite*: You must already have the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html) and the [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html) (version 1.33 or higher) installed and configured. You can use an AWS Cloud9 environment.

Use the [publish.sh](./publish.sh) bash script to build the project and deploy CloudFormation templates to your own deployment bucket.

Run the script with up to 4 parameters:
```
./publish.sh <cfn_bucket_basename> <cfn_prefix> <region> [public]

- <cfn_bucket_basename>: basename name of S3 bucket to deploy CloudFormation templates and code artifacts. Actual bucketname is determined by appending region to bucket basename. If bucket does not exist it will be created.
- <cfn_prefix>: artifacts will be copied to the path specified by this prefix (path/to/artifacts/)
- <region>: aws region to use for building and deploying artifacts.. artifacts must be installed in this same region.
- public: (optional) Adding the argument "public" will set public-read acl on all published artifacts, for sharing with any account.
```

It downloads package dependencies, builds code zipfiles, replaces local filesystem references in CloudFormation templates, and copies templates and zip files to the cfn_bucket.
When complete, it displays the URLS for the CloudFormation templates, 1-click URLs for launching the stack create in CloudFormation, and CLI deployment command , e.g.:
```
Outputs
Template URL: https://s3.us-east-1.amazonaws.com/bobs-lca-artifacts-us-east-1/LCA-public/0.1.0/lca-main.yaml
CF Launch URL: https://us-east-1.console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/create/review?templateURL=https://s3.us-east-1.amazonaws.com/bobs-lca-artifacts-us-east-1/LCA-public/0.1.0/lca-main.yaml&stackName=LiveCallAnalytics&param_installDemoAsteriskServer=true
CLI Deploy: aws cloudformation deploy --region us-east-1 --template-file /tmp/lca/lca-main.yaml --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND --stack-name LiveCallAnalytics --parameter-overrides AdminEmail='jdoe@example.com' installDemoAsteriskServer=true
```

### Deploy

Start your LCA experience by using AWS CloudFormation to deploy the sample solution with the built-in demo mode enabled. 
The demo mode downloads, builds, and installs a small virtual PBX server on an Amazon EC2 instance in your AWS account (using the free open source [Asterisk](https://www.asterisk.org/get-started/) project) so you can make test phone calls right away and see the solution in action. You can integrate it with your contact center later after evaluating the solution's functionality for your unique use case.

To get LCA up and running in your own AWS account, follow these steps (if you do not have an AWS account, please see [How do I create and activate a new Amazon Web Services account?](https://aws.amazon.com/premiumsupport/knowledge-center/create-and-activate-aws-account/)):

1. Log into the [AWS console](https://console.aws.amazon.com/) if you are not already.  
*Note: If you are logged in as an IAM user, ensure your account has permissions to create and manage the necessary resources and components for this application.* 
2. Choose one of the **Launch Stack** buttons below for your desired AWS region to open the AWS CloudFormation console and create a new stack. AWS Full-Stack Template is supported in the following regions:

Region name | Region code | Launch
--- | --- | ---
US East (N. Virginia) | us-east-1 | [![Launch Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://us-east-1.console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/create/review?templateURL=https://s3.us-east-1.amazonaws.com/aws-ml-blog-us-east-1/artifacts/lca/lca-main.yaml&stackName=LiveCallAnalytics&param_installDemoAsteriskServer=true)
US West (Oregon) |	us-west-2 | [![Launch Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://us-west-2.console.aws.amazon.com/cloudformation/home?region=us-west-2#/stacks/create/review?templateURL=https://s3.us-west-2.amazonaws.com/aws-ml-blog-us-west-2/artifacts/lca/lca-main.yaml&stackName=LiveCallAnalytics&param_installDemoAsteriskServer=true)

3. On the CloudFormation `Create Stack` page, click `Next`
4. Enter the following parameters:
    1. `Stack Name`: Name your stack, e.g. LiveCallAnalyticsStack
    2. `Install Demo Asterisk Server` - Set to true to automatically install a demo Asterisk server for testing Chime Voice Connector streaming
    3. `Allowed CIDR Block for Demo Softphone` - Ignored if `Install Demo Asterisk Server` is false. CIDR block allowed by demo Asterisk server for soft phone registration. Example: '10.1.1.0/24' 
    4. `Allowed CIDR List for Siprec Integration` - Ignored if `Install Demo Asterisk Server` is true. Comma delimited list of CIDR blocks allowed by Chime Voice Connector for SIPREC source hosts. Example: '10.1.1.0/24, 10.1.2.0/24' 
    5. `Admin Email Address` - Enter the email address of the admin user to be used to log into the web UI. An initial temporary password will be automatically sent via email. This email also includes the link to the web UI
    6. `Authorized Account Email Domain` - (Optional) Enter the email domain that is allowed to signup and signin using the web UI. Leave blank to disable signups via the web UI (users must be created using Cognito). If you configure a domain, **only** email addresses from that domain will be allowed to signup and signin via the web UI
    7. `Call Audio Recordings Bucket Name` - (Optional) Existing bucket where call recording files will be stored. Leave blank to automatically create new bucket
    8. `Audio File Prefix` - The Amazon S3 prefix where the audio files will be saved (must end in "/")
    9. `Enable Content Redaction for Transcripts` - Enable content redaction from Amazon Transcribe transcription output. **NOTE:** Content redaction is only available when using the English language (en-US). This parameter is ignored when not using the English language
    10. `Language for Transcription` - Language code to be used for Amazon Transcribe
    11. `Content Redaction Type for Transcription` - Type of content redaction from Amazon Transcribe transcription output
    12. `Transcription PII Redaction Entity Types` - Select the PII entity types you want to identify or redact. Remove the values that you don't want to redact from the default. *DO NOT ADD CUSTOM VALUES HERE*.
    13. `Transcription Custom Vocabulary Name` - The name of the vocabulary to use when processing the transcription job. Leave blank if no custom vocabulary to be used. If yes, the custom vocabulary must pre-exist in your account.
    14. `Enable Sentiment Analysis using Amazon Comprehend` - Enable sentiment analysis using Amazon Comprehend
    15. `CloudFront Price Class` - The CloudFront price class. See the [CloudFront Pricing](https://aws.amazon.com/cloudfront/pricing/) for a description of each price class.
    16. `CloudFront Allowed Geographies` - (Optional) Comma separated list of two letter country codes (uppercase ISO 3166-1) that are allowed to access the web user interface via CloudFront. For example: US,CA. Leave empty if you do not want geo restrictions to be applied. For details, see: [Restricting the Geographic Distribution of your Content](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/georestrictions.html).
5. After reviewing, check the blue box for creating IAM resources.
6. Choose **Create stack**.  This will take ~15 minutes to complete.
7. Once the CloudFormation deployment is complete,
    1. The admin user will receive a temporary password and the link to the CloudFront URL of the web UI (this can take a few minutes). The output of the CloudFormation stack creation will also provide a CloudFront URL (in the **Outputs** table of the stack details page). Click the link or copy and paste the CloudFront URL into your browser.
    2. You can sign into your application using the admin email address as the username and the temporary password you received via email. The web UI will prompt you to provide your permanent password. The user registration/login experience is run in your AWS account, and the supplied credentials are stored in Amazon Cognito. *Note: given that this is a demo application, we highly suggest that you do not use an email and password combination that you use for other purposes (such as an AWS account, email, or e-commerce site).*.
    3. Once you provide your credentials, you will be prompted to verify the email address. You can verify your account at a later time by clicking the Skip link. Otherwise, you will receive a verification code at the email address you provided (this can take a few minutes). Upon entering this verification code in the web UI, you will be signed into the application.

## Testing
You can test this solution if you installed the demo asterisk server during deployment. To test, perform the following steps:
1. Configure a Zoiper client as described in this [README](lca-chimevc-stack/README.md). This will allow you to receive phone calls from an external phone number to the Zoiper client on your computer.
2. Once installed, log in to the web app created in the [deploy](#deploy) section by opening the Cloudfront URL provided in you CloudFormation outputs (`CloudfrontEndpoint`)
3. Once logged in, place a phone call using an external phone to the number provided in the CloudFormation outputs (`DemoPBXPhoneNumber`)
4. You will see the phone call show up on the LCA web page as follows ![lca-demo](./images/demo.png)


## Conclusion
The Live Call Analytics (LCA) sample solution offers a scalable, cost-effective approach to provide live call analysis with features to assist supervisors and agents to improve focus on your callers’ experience. It uses Amazon machine learning services like Amazon Transcribe and Amazon Comprehend to transcribe and extract real time insights from your contact center audio.  
The sample LCA application is provided as open source—use it as a starting point for your own solution, and help us make it better by contributing back fixes and features via GitHub pull requests. For expert assistance, [AWS Professional Services](https://aws.amazon.com/professional-services/) and other [AWS Partners](https://aws.amazon.com/partners/) are here to help.

## Clean Up
Congratulations! :tada: You have completed all the steps for setting up your live call analytics sample solution using AWS services. 

**To make sure you are not charged for any unwanted services, you can clean up by deleting the stack created in the _Deploy_ section and its resources.**

When you’re finished experimenting with this sample solution, clean up your resources by using the AWS CloudFormation console to delete the LiveCallAnalytics stacks that you deployed. This deletes resources that were created by deploying the solution. The recording S3 buckets, the DynamoDB table and CloudWatch Log groups are retained after the stack is deleted to avoid deleting your data.

[(Back to top)](#overview)

## Contributing
Your contributions are always welcome! Please have a look at the [contribution guidelines](CONTRIBUTING.md) first. :tada:

[(Back to top)](#overview)

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

[(Back to top)](#overview)


## License Summary

This sample code is made available under the Apache-2.0 license. See the [LICENSE](LICENSE.txt) file.

[(Back to top)](#overview)

# AI Job Search Buddy

AI Job Search Buddy is a tool for aggregating job listings, filtering them for specific criteria using LLMs, and presenting them to the user in a daily (or whatever cadence is desired) email. It runs a daily CRON job which ingests updates from a list of RSS feeds containing job listings. Links to those listings are then fed to OpenAI's chat completion API with a prompt containing instructions to extract certain information and to filter the job listings based on customizable criteria. The results are then emailed to the recipient using the SendGrid API.

## How to use it
AI Job Search Buddy runs as a daily CRON job triggered by AWS EventBridge and run on AWS Lambda. The project includes a terraform file for configuring the necessary cloud infrastructure.

1. Clone the repository.
2. Replace the RSS feeds in the rss_urls constant in src/index.js with links to the RSS feeds you want processed. I recommend generating them with Google Alerts that target a specific job board site and the type of job you're looking for (i.e. "site:board.greenhouse.io software engineer")
3. Set up an AWS account if you don't already have one. Set up your AWS configuration and credential files in you .aws directory. This will be necessary to run Terraform.
4. Install the Terraform CLI. Follow these instruction on how to do it: [Terraform Documentation](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
5. Set up an OpenAI account and generate an API key.
6. Set up a SendGrid account and generate an API key.
7. Configure environment variables. Create a local.tf file and provide values for the following keys: OPENAI_API_KEY, SENDGRID_API_KEY, RECIPIENT (email address you'd like the results to be sent to), SENDER (email address you've configured as an authorized sender in SENDGRID that you would like the emails to appear to be coming from), PROMPT (custom instructions for OPENAI), and MODEL (the model you'd like OPENAI to use, I suggest gpt-4).
8. Run the following shell commands:
```bash
# initializes a terraform project
terraform init

# detects needed changes to the cloud infrastructure to deploy the changes to the project and reports them
terraform plan

# deploy changes
terraform apply
```

You're all done!

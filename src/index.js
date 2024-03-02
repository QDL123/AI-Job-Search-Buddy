const Promise = require('bluebird');
const _ = require('lodash');
const sgMail = require('@sendgrid/mail');
require('dotenv').config();
const OpenAI = require('openai');
const Parser = require('rss-parser');


// Set up API clients
const openai = new OpenAI({
    apiKey: process.env['OPENAI_API_KEY'],
});
sgMail.setApiKey(process.env['SENDGRID_API_KEY']);


const parser = new Parser();
const rss_urls = [
    "https://www.google.com/alerts/feeds/04534337928605833163/3244402253473668538"
];

async function handler() {
    console.log("Entered Lambda function");
    const feeds = await Promise.map(rss_urls, url => parser.parseURL(url));
    const links = _.map(_.flatMap(feeds, feed => feed.items), item => item.link);

    console.log(`Number of links from feeds: ${links.length}`);
    const linkString = links.join(',\n');

    const chatCompletion = await openai.chat.completions.create({
        messages: [
            {
                role: 'system',
                content: 'You are a job listing analyzer AI. You extract information from job listings, filter them down, and summarize your findings.',
            },
            {
                role: 'user',
                content: process.env.PROMPT + linkString,
            }
        ],
        model: process.env.MODEL,
    });

    console.log(`Got AI response: ${chatCompletion.choices[0].message.content}`);

    const msg = {
        to: process.env.RECIPIENT,
        from: process.env.SENDER,
        subject: "AI Job Search Buddy Report",
        text: chatCompletion.choices[0].message.content,
    };

    try {
        await sgMail.send(msg);
        console.log("SENT EMAIL");
    } catch (error) {
        console.error(error);
        if (error.response) {
            console.error(error.response.body);
        }
    }
}

module.exports = { handler };
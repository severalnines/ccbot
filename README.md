# ccbot
Repository for chatbot services with hubot, slack and others

### Installing DBBot

## Prerequisits

Firstly we need to have the node.js framework installed. This can easily be done by installing npm:

https://github.com/nodejs/node-v0.x-archive/wiki/Installing-Node.js-via-package-manager

This should install the necessary node.js packages as well and allow you to install additional modules via npm.


## Installing Hubot framework

To install the Hubot framework from scratch follow the following procedure:

- npm install -g yo generator-hubot
- mkdir <path to ccbot>
- cd <path to ccbot>
- yo hubot


## Installing additional Hubot and node.js packages

Hubot integration with Slack:
- npm install hubot-slack

## Installing ccbot scripts

Overwrite everything with the files from this repository in the ccbot directory
Also don't forget to edit the hubot.sh with the Slack ccbot API key and the CMON RPC token

Happy botting!


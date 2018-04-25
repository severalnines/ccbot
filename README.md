# ccbot
Repository for chatbot services with hubot, slack and others

## Installing CCBot

### Integrate CCBot on an existing Hubot framework

In principle this should be relatively easy as you already have a working Hubot chatbot, thus only copying the source files to your chatbot and add the CCBot parameters would be sufficient to make it work.

#### Installing CCBot scripts
Copy the following files from the to your existing Hubot instance in the respective directories:
- src/config/config.coffee
- src/scripts/clustercontrol.coffee
- src/utils/cmonrpc.coffee

Then add the following parameters in your Hubot startup script if necessary:
- export HUBOT_CMONRPC_HOST=’your clustercontrol host’
- export HUBOT_CMONRPC_PORT=9500
- export HUBOT_CMONRPC_MSGROOM=’General’

These variables will be picked up by the config.coffee file and used inside the cmonrpc calls.

For configuration of the HUBOT_CMONRPC_MSGROOM variable, see below in the standalone installation.
Bind ClusterControl to external ip addres
As of ClusterControl version 1.2.12 there is a change in binding address of the CMON RPC: by default it will bind to localhost (127.0.0.1) and if your existing Hubot chatbot is living on a different host you need to configure CMON to bind to another ip address as well. You can change this in the cmon default file (/etc/default/cmon):
- RPC_PORT=9500
- RPC_BIND_ADDRESSES="127.0.0.1,your.ip.address.here"


### Installing CCBot as a standalone chatbot

# Prerequisites
Firstly we need to have the node.js framework installed. This can best be done by installing npm. This should install the necessary node.js packages as well and allow you to install additional modules via npm.
Installing Hubot framework
For security we create a separate hubot user to ensure Hubot itself can’t do anything outside running Hubot and create the directory to run Hubot from.
- sudo useradd -m hubot
- sudo mkdir /var/lib/hubot
- sudo chown hubot /var/lib/hubot

To install the Hubot framework from scratch follow the following procedure where the adapter is the chat service you are using (e.g. slack, hipchat, flowdock):
- sudo npm install -g yo generator-hubot
- sudo npm install striptags
- sudo su - hubot
- cd /var/lib/hubot
- yo hubot --name CCBot --adapter adapter

So if you are using, for instance, Slack as your chat provider you would need to provide “slack” as your adapter. A complete list of all the Hubot adapters can be found here:
https://hubot.github.com/docs/adapters/
Don’t forget to configure your adapter accordingly in the hubot startup script.

Also if you choose to change CCBot’s name keep in mind not to name the bot to Hubot: the Hubot framework attempts to create a module named exactly the same as the name you give to the bot. Since the framework is already named Hubot this will cause a non-descriptive error.

#### Installing CCBot scripts
Copy the following files to the ccbot directory:
- src/config/config.coffee
- src/scripts/clustercontrol.coffee
- src/utils/cmonrpc.coffee

Installing Hubot startup scripts
Obviously you can run Hubot in the background or a Screen session, but it would be much better if we can daemonize Hubot using proper start up scripts. We supply three startup scripts for CCBot: a traditional Linux Standard Base init script (start, stop, status), a systemd wrapper for this init script and a supervisord script.

Linux Standard Base init script:
For Redhat/Centos 6.x (and lower):
- cp scripts/hubot.initd /etc/init.d/hubot
- cp scripts/hubot.env /var/lib/hubot
- chkconfig hubot on

For Debian/Ubuntu:
- cp scripts/hubot.initd /etc/init.d/hubot
- cp scripts/hubot.env /var/lib/hubot
- ln -s /etc/init.d/hubot /etc/rc3.d/S70hubot

Systemd:
For systemd based systems :
- sudo cp scripts/hubot.initd /sbin/hubot
- cp scripts/hubot.env /var/lib/hubot
- sudo cp scripts/hubot.systemd.conf /etc/systemd/hubot.conf
- sudo systemctl daemon-reload
- sudo systemctl enable hubot

Supervisord
For this step it is necessary to have supervisord installed on your system.
For Redhat/Centos:
- sudo yum install supervisord
- sudo cp scripts/hubot.initd /sbin/hubot
- sudo cp scripts/hubot.supervisord.conf /etc/supervisor/conf.d/hubot.conf
- sudo supervisorctl update

For Debian/Ubuntu:
- sudo apt-get install supervisord
- cp scripts/hubot.initd /sbin/hubot
- sudo cp scripts/hubot.supervisord.conf /etc/supervisor/conf.d/hubot.conf
- sudo supervisorctl update

### Hubot parameters
Then modify the following parameters in the Hubot environment script (/var/lib/hubot/hubot.env) or supervisord config if necessary:
- export HUBOT_CMONRPC_HOST=’localhost’
- export HUBOT_CMONRPC_PORT=9500
- export HUBOT_CMONRPC_MSGROOM=’General’

The HUBOT_CMONRPC_MSGROOM variable contains the team’s room the chatbot has to send its messages to. For the chat services we tested this with it should be something like this:
- Slack: use the textual ‘General’ chatroom or a custom textual one.
- Hipchat: similar to “17723_yourchat@conf.hipchat.com”. You can find your own room via “Room Settings”
- Flowdock: needs a room identifier similar to “a0ef5f5f-9d97-42aa-b6a3-c1a6bb87510e”. You can find your own identifier via Integrations -> Github -> popup url
- Campfire: a numeric room, which is in the url of the room


## Hubot commands
You can operate Hubot by giving it **s9s command line** commands in the chatroom. In principle it does not matter whether you issue to command in a general chatroom where Hubot is present or if it were in a private chat with the bot itself. Sending a command will be as following:
botname command
Where botname is the name of your Hubot bot, so if in our example Hubot is called “ccbot” and the command is “node list” you would send the command be as following:
@ccbot s9s node --list

Note: when you are in a private chat with the chatbot you must omit the addressing of the bot.

### Command list
The commands that you can use are identical with what the **s9s command line** tool supports. For more details and an introduction to the **s9s command line** tool, check this [blog post](https://severalnines.com/blog/how-use-s9s-command-line-interface-clustercontrol).

#### s9s --help
Syntax: s9s --help

Shows all available commands in the s9s command line tool.

Example:
@ccbot s9s --help

### A few examples
#### List clusters
Syntax: s9s cluster --list --long

Lists all clusters with their name, id and status.

Example:
@ccbot s9s cluster --list --long

#### List nodes
Syntax: s9s node --list --long

Lists all nodes with their name, id and status.

Example:
@ccbot s9s node --list --long

#### Full backup
Syntax: s9s backup --create --backup-method=&lt;backup method&gt; --cluster-id=&lt;cluster id&gt; --nodes=&lt;list of node:port&gt; --backup-directory=&lt;backup directory&gt;

Creates a full backup using the specified backup method, backup node and bacup directory.

Example:
@ccbot s9s backup --create --backup-method=xtrabackupfull --cluster-id=1 --nodes=10.0.0.5:3306 --backup-directory=/storage/backups

#### List configuration
Syntax: s9s node --list-config --nodes=&lt;list of nodes&gt;

List the configuration for the specified node(s).

Example:
@ccbot s9s node --list-config --nodes=10.0.0.3 | grep max_



Happy botting!


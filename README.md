# Ekster: XMPP IoT Registry component

Ekster, the [XMPP](http://www.xmpp.org) [IoT Registry](http://xmpp.org/extensions/xep-0347.html), is an external [XMPP component](http://xmpp.org/extensions/xep-0114.html) that can be used to register, claim and discover XMPP IoT devices.

Ekster is the Dutch word for [Magpie](https://en.wikipedia.org/wiki/Magpie). In the story _A basket of flowers_ by Lilian Gask (1910) a Magpie steals a golden ring. Our Ekster component _steals_ all of our shiny IoT gadgets and puts it in its nest, the IoT Registry.

A good start to learn more about Ekster is to read the [XMPP IoT discovery extension: XEP-0347](http://xmpp.org/extensions/xep-0347.html). Ekster aims to implement this XEP.

For more information about XMPP and IoT you can checkout [this website](http://www.xmpp-iot.org).

## License

Ekster is available under a **MIT License** which means that you can basically do anything you want with this code as long as you provide attribution back to us and don’t hold us liable.

## Roadmap

Ekster is still in development. It is not used in production by us. We believe we've implemented most of of XEP-0347. If you find any bugs or misinterpretations of the XEP please let us know by creating a new issue.

Currently our roadmap for Ekster is:

* Create a more persistent solution for storing data when running Ekster on Docker
* Further testing and improving Ekster
* Validate the current XMPP IoT discovery extension.

## Running Ekster

There are various ways you can run the Ekster component. Our personal favorite is running the component with [docker-compose](https://docs.docker.com/compose/). But you can run Ekster from the command line or as an Heroku application as well.

### Install and run on Docker

The preferred way to run Ekster is using `docker-compose`. A [configuration template](docker-compose-template.yml) is available. Follow these
steps to run Ekster on a Docker host:

* First you need to add the Ekster component credentials to your XMPP server. For example on [Prosody](http://prosody.im/doc/components) or [ejabberd](https://www.ejabberd.im/node/5134).
* Copy the template: `cp docker-compose-template.yml docker-compose.yml`
* Edit the `docker-compose.yml`, change the `TODO` items to the target environment.
* Get Ekster up and running using the command `docker-compose up`.

Please note that the database that is setup with Ekster currently does not save its data to a datastore. It is kept locally on the mongodb docker container. When you remove that container the data will also be gone.

### Install and run from the commandline

* Clone the project from git: `git clone git@github.com:TNO-IoT/ekster.git`
* Go into the folder Ekster was cloned into: `cd ekster`
* Install [nodejs](http://nodejs.org)
* Install coffeescript: `npm install -g coffee-script`
* Start Ekster using the commandline: `src/ekster.coffee`

```
Usage: ekster.coffee [options]

  Options:

    -h, --help                       output usage information
    -V, --version                    output the version number
    -j, --jid <jid>                  jid for the registry
    -P, --password <password>        password for the component
    -H, --host <hostname>            hostname of the XMPP server this component connects to
    -R, --no-reconnect               disable reconnecting to the XMPP server when the connection is lost
    -p, --port [port]                the port to connect to [5347]
    -b, --backend [backend]          the backend to connect to [mongoose]
    -B, --backendHost [backendHost]  the host of the backend [localhost]
    -s, --backendPort [backendPort]  the port where the backend is listening [27017]
    --backendOptions []              the configuration options for the backend []
    -v, --verbose                    verbose logging

  Examples:

    $ registrar --help
    $ registrar --jid registry.yourcompany.com --password secret --host xmpp.yourcompany.com --backend mongoose --backendHost localhost --backendPort 27017 --backendOptions '{ "user": "mongouser", "pass": "mongopass", "db": "mongodb" }'
```

### Install and run on Deis or Heroku

* Create a configuration file `.env`:

    ```
    XMPP_JID=<your component jid>
    XMPP_PASSWD=<your component password>
    XMPP_HOST=<your xmpp server host>
    XMPP_PORT=<your xmpp server's component port, ie 5347>
    BACKEND_TYPE=mongoose
    BACKEND_OPTIONS=\{\"user\":\"iotregistry\",\"pass\":\"your password\",\"db\":\"registry\"\}
    BACKEND_HOST=<your backend server's hostname>
    BACKEND_PORT=<your backend server port>
    ```
* Test your configuration locally with [foreman](http://blog.daviddollar.org/2011/05/06/introducing-foreman.html): `foreman start`
* Deploy to the PaaS of choice.

## Development instructions

The component is build in [coffeescript](http://coffeescript.org) and needs to have coffeescript installed to run. Coffeescript compiles to javascript hence to be able to run coffeescript you need to have [nodejs](http://nodejs.org) installed on your system.

To install a development environment for Ekster please use the instructions below:

* Install [nodejs](http://nodejs.org)
* Install coffeescript via the node package manager: `npm install coffee-script -g`
* Install the grunt build environment: `npm install grunt-cli -g`
* Install the project dependencies: `npm install --production` (for development you should leave out the `--production`)

There is a [Gruntfile](Gruntfile) with the following tasks:

* `default`: watches the code for changes and, on change, runs the linter and test cases.
* `grunt exec:dev`: runs Ekster in development mode. For this you will change the Gruntfile according to your environment.
* `grunt exec:production`: runs Ekster in production mode: this will get you configuration from environment variables.

You can find the source code in `./src`. Test scripts go into `./test`. Currently the [nodeunit](https://www.npmjs.org/package/nodeunit) test framework is used. Details on how to use the [nodeunit test framework with coffeescript is detailed here](http://coffeescriptcookbook.com/chapters/testing/testing_with_nodeunit).

Before adding sources to the git repository they should pass the `coffeelint` and `nodeunit` checks. You can run the checks manually by issuing `grunt coffeelint` and `grunt nodeunit`. Or you can run the checks automatically every time you save a file by issuing `grunt watch` or `grunt`.

### Source code

Below you find a list of source files and a short description about what function they provide:

* [`ekster.coffee`](src/ekster.coffee) - Entry script that creates the connections to the database and XMPP server and starts XMPP stanza processor.
* [`backend.coffee`](src/backend.coffee) - Interface that backend connectors should implement.
* [`logger.coffee`](src/logger.coffee) - Wrapper to the logger module.
* [`mongoose-backend.coffee`](src/mongoose-backend.coffee) - Backend implementation using [mongoose](http://mongoosejs.com) models to write to a mongodb. Currently the default backend for Ekster.
* [`octoblu-backend.coffee`](src/octoblu-backend.coffee) - Backend implementation that uses [octoblu](https://www.octoblu.com) as a backend service. Octoblu rate-limits requests and this may cause unexpected behavior with the registry. Might be outdated...
* [`presence-handler.coffee`](src/presence-handler.coffee) - Handles incoming presence message and friendship relations of the registry.
* [`processor.coffee`](src/processor.coffee) - Handles incoming message for the registry. This is where the XMPP IoT discovery protocol is implemented.
* [`property.coffee`](src/property.coffee) - A name/value pair that a Thing uses to register META information.
* [`thing.coffee`](src/thing.coffee) - The model of a Thing used by the processor.

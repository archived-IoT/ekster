#!/bin/bash
node_modules/coffee-script/bin/coffee src/ekster.coffee --verbose --jid $XMPP_JID --password $XMPP_PASSWD --host $XMPP_PORT_5347_TCP_ADDR --port $XMPP_PORT_5347_TCP_PORT --backend $BACKEND_TYPE --backendOptions $BACKEND_OPTIONS --backendHost $BACKEND_PORT_27017_TCP_ADDR --backendPort $BACKEND_PORT_27017_TCP_PORT | node_modules/bunyan/bin/bunyan

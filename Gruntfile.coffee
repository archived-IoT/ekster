module.exports = (grunt) ->

    grunt.initConfig

        coffeelint:
            all: ['src/**/*.coffee']
            options:
                configFile: './coffeelint.json'

        nodeunit:
            all: ['test/**/*.test.coffee']

        watch:
            coffeescript:
                files: ['src/**/*.coffee', 'test/**/*.coffee']
                tasks: ['coffeelint', 'nodeunit']
                options:
                    spawn: false

        exec:
            dev:
                cmd: () ->
                    if process.platform is 'win32'
                        return 'node_modules/coffee-script/bin/coffee src/ekster.coffee
                            --jid registry.xmpp.local
                            --password testing --host 192.168.99.100 --verbose
                            --backendHost localhost --backendPort 27017
                            --backend mongoose --backendOptions ^"{ }^"'
                    else
                        return 'node_modules/coffee-script/bin/coffee src/ekster.coffee
                            --jid registry.xmpp.local
                            --password testing --host 192.168.99.100 --verbose
                            --backendHost localhost --backendPort 27017
                            --backend mongoose --backendOptions \'{ }\''

            prod:
                cmd: "node_modules/coffee-script/bin/coffee src/ekster.coffee
                    --verbose
                    --jid #{ process.env.REGISTRY_JID }
                    --password #{ process.env.REGISTRY_PASSWORD }
                    --host #{ process.env.XMPP_PORT_5347_TCP_ADDR }
                    --port #{ process.env.XMPP_PORT_5347_TCP_PORT }
                    --backend #{ process.env.REGISTRY_BACKEND }
                    --backendOptions \'#{ process.env.REGISTRY_BACKEND_OPTIONS }\'
                    --backendHost #{ process.env.BACKEND_PORT_27017_TCP_ADDR }
                    --backendPort #{ process.env.BACKEND_PORT_27017_TCP_PORT }"

    grunt.event.on 'watch', (action, filepath) ->
        grunt.config(['coffeelint', 'all'], filepath)

    grunt.loadNpmTasks 'grunt-coffeelint'
    grunt.loadNpmTasks 'grunt-contrib-watch'
    grunt.loadNpmTasks 'grunt-exec'
    grunt.loadNpmTasks 'grunt-contrib-nodeunit'

    grunt.registerTask 'default', ['watch']

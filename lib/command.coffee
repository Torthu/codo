Path     = require 'path'
Codo     = require './codo'
Optimist = require 'optimist'
Theme    = require '../themes/default/lib/theme'
Table    = require 'cli-table'
colors   = require 'colors/safe'

module.exports = class Command
  options: [
    {name: 'help', alias: 'h', describe: 'Show this help'}
    {name: 'version', describe: 'Show version'}
    {name: 'extension', alias: 'x', describe: 'Coffee files extension', default: 'coffee'}
    {name: 'output', alias: 'o', describe: 'The output directory', default: './doc'}
    {name: 'min-coverage', alias: 'm', describe: 'Require a minimum percentage to be documented or fail', default: '0'}
    {name: 'output-dir'}
    {name: 'theme', describe: 'The theme to be used', default: 'default'}
    {name: 'name', alias: 'n', describe: 'The project name used'}
    {name: 'readme', alias: 'r', describe: 'The readme file used'}
    {name: 'quiet', alias: 'q', describe: 'Supress warnings', boolean: true, default: false}
    {name: 'verbose', alias: 'v', describe: 'Show parsing errors', boolean: true, default: false}
    {name: 'undocumented', alias: 'u', describe: 'List undocumented objects', boolean: true, default: false}
    {name: 'closure', describe: 'Try to parse closure-like block comments', boolean: true, default: false}
    {name: 'debug', alias: 'd', boolean: true}
  ]

  @run: ->
    new @().run (code) ->
      process.exit code

  extendOptimist: (optimist, defaults={}, options={}) ->
    for option in options
      optimist.options option.name,
        alias: option.alias,
        describe: option.describe,
        boolean: option.boolean,
        default: defaults[option.name] || defaults[option.alias] || option.default

  lookupTheme: (name) ->
    if name == 'default'
      @theme = Theme
    else
      try
        @theme = require "codo-theme-#{name}"
      catch
        try
          @theme = require Path.resolve("node_modules/codo-theme-#{name}")
        catch
          console.log "Error loading theme #{name}: are you sure you have codo-theme-#{name} package installed?"
          process.exit()

  prepareOptions: (optimist, defaults) ->
    options = optimist.argv
    options._.push entry for entry in defaults._

    keyword = 'inputs'
    for entry in options._
      if entry == '-'
        keyword = 'extras'
      else
        options[keyword] ?= []
        options[keyword].push entry

    delete options._

    options

  run: (cb) ->
    defaults = Codo.detectDefaults(process.cwd())

    optimist = Optimist.usage('Usage: $0 [options] [source_files [- extra_files]]')
    @extendOptimist(optimist, defaults, @options)

    @theme = @lookupTheme(optimist.argv.theme)
    @extendOptimist(optimist, defaults, @theme::options)

    @options = @prepareOptions(optimist, defaults)

    if @options['output-dir']
      console.log "The usage of outdated `--output-dir` option detected. Please switch to `--output`."
      process.exit()

    if @options.help
      console.log optimist.help()
    else if @options.version
      console.log Codo.version()
    else
      @generate(process.cwd(), @options, cb)

  collectStats: (environment) ->
    sections =
      Classes:
        total: environment.allClasses().length
        undocumented: environment.allClasses().filter((e) -> !e.documentation?).map (x) ->
          [x.name, x.file.path]

      Mixins:
        total: environment.allMixins().length
        undocumented: environment.allMixins().filter((e) -> !e.documentation?).map (x) ->
          [x.name, x.file.path]

      Methods:
        total: environment.allMethods().length
        undocumented: environment.allMethods().filter((e) -> !e.entity.documentation?).map (x) ->
          ["#{x.entity.name} (#{x.owner.name})", x.owner.file.path]

    sections

  generate: (dir = process.cwd(), options = @options, cb) ->
    for option in @options
      if option.default?
        options[option.name] ?= option.default
    @theme ?= @lookupTheme(options.theme)

    for option in @theme::options
      if option.default?
        options[option.name] ?= option.default

    environment = Codo.parseProject(dir, options)
    sections    = @collectStats(environment)

    unless options.test
      @theme.compile(environment)

    overall      = 0
    undocumented = 0

    for section, data of sections
      overall      += data.total
      undocumented += data.undocumented.length

    if options.undocumented
      for section, data of sections when data.undocumented.length != 0
        table = new Table
          head: [section, 'Path']

        table.push(entry) for entry in data.undocumented
        unless options.test
          console.log table.toString()
          console.log ''
    else
      table = new Table
        head: ['', 'Total', 'Undocumented']

      undocumented_percent = 100/overall*undocumented || 0

      table.push(
        ['Files', environment.allFiles().length, ''],
        ['Extras', environment.allExtras().length, ''],
        ['Classes', sections['Classes'].total, sections['Classes'].undocumented.length],
        ['Mixins', sections['Mixins'].total, sections['Mixins'].undocumented.length],
        ['Methods', sections['Methods'].total, sections['Methods'].undocumented.length]
      )

      unless options.test
        console.log table.toString()
        console.log ''
        console.log "  Totally documented: #{(100 - undocumented_percent).toFixed(2)}%"
        console.log ''

    documentedRatio = 100 - (100*undocumented/overall).toFixed(2)
    if documentedRatio < options["min-coverage"]
      unless options.test
        console.error colors.red("  Expected " + options["min-coverage"] +
                       "% to be documented, but only " + documentedRatio + "% were.")
      cb 1 if cb
    else
      cb() if cb

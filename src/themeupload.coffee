fs      = require("fs")
restler = require("restler")
walk    = require("walkdir")
YAML    = require("libyaml")
mime    = require("mime")
md5     = require("MD5")
pathMod = require("path")
async   = require("async")


class Upload

  constructor: (inpath) ->

    @inpath      = inpath
    @opts        = {}
    @exclude     = ['theme.yaml', 'index.html']
    @domain      = ''
    @version     = null
    @totalfiles  = 0
    @callcounter = 0

    console.log 'this inpath', @inpath

    @run()

  run: ->
    console.log 'getting configuration...'
    @parseYaml()
    @getDomain()
    console.log 'domain is', @domain
    console.log 'opts', @opts
    @getNextVersion()

  getDomain: ->
    @domain = 'http://themes-nex9.rhcloud.com'
    @domain = 'http://localhost:8001' if @opts.debug

  parseYaml: =>
    yamlPath = @inpath+'/theme.yaml'
    process.kill() unless fs.existsSync yamlPath
    @opts = YAML.readFileSync(yamlPath)[0]

  getNextVersion: ->
    url = @domain + '/api/nextversion'

    console.log 'nextversion url', url
      
    restler.postJson(url, {'_tenant': @opts.tenant}).on 'complete', (data, response) =>
      @version = parseInt data
      console.log 'themeversion is', @version
      @walkFiles()

  pathFilter: (path) =>
    fname = path.split('/')[path.split('/').length-1]
    return false if fs.lstatSync(path).isDirectory()
    return false if fname in @exclude
    return false if fname.indexOf('.') is 0
    true

  walkFiles: ->
    paths        = walk.sync @inpath
    paths        = paths.filter @pathFilter
    _this        = @
    async.eachLimit paths, 10,
      (path, cb) =>

        ext      = pathMod.extname path
        mimetype = mime.lookup path

        stats    = fs.stat path, (err, stats) =>
          payload =
            'action'  : 'uploadurl'
            'filename': path.split('/public')[1]
            'mimetype': mimetype
            'version' : _this.version
            'tenant'  : _this.opts.tenant

          url = "#{_this.domain}/api/themefile/upload"
          restler.postJson(url, payload).on 'complete', (gcsurl, response) =>

            data =
              multipart : true
              data  : {
                file  : restler.file(path, null, stats.size, null, mimetype)
              }
            restler.put(gcsurl, data).on 'complete', (data, response) => 
              console.log pathMod.basename(path), '...done'

              fs.readFile path, (err, buf) =>

                themefile =
                  _tenant  : _this.opts.tenant
                  path    : payload.filename
                  version : _this.version
                  md5     : md5(buf)
                  size    : stats.size
                  mimetype: mimetype
                  gs_path : "#{_this.opts.tenant}/#{_this.version}#{payload.filename}"
                url = "#{_this.domain}/api/themefile"
                restler.postJson(url, themefile).on 'complete', (data, response) ->
                  cb()
      (err) =>
        console.log 'done uploading files...'
        if _this.opts.setdefault
          console.log 'going to set the default version to', _this.version
          url = _this.domain + '/api/setdefault'
          data = 
            version: _this.version
            _tenant: _this.opts.tenant
          restler.postJson(url, data).on 'complete', (data, response) ->
            console.log 'all done!'


class ThemeUpload

  exec: ->

    args = process.argv

    if args.length isnt 3
      if args.length is 2
        console.log 'the command must be called with path as an argument'
        return
      else if args.length > 3
        console.log 'too many arguments'
        return

    path = args[args.length-1]

    if fs.existsSync(path) and fs.existsSync(path+'/public')
      new Upload(path+'/public')
    else
      console.log 'fuck'


module.exports = ThemeUpload



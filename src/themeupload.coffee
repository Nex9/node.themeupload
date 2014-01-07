fs      = require("fs")
restler = require("restler")
walk    = require("walkdir")
YAML    = require("libyaml")
mime    = require("mime")
hash    = require("mhash").hash;

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
    @getNextVersion()

  gaeVersion: ->
    if @opts.gaeversion is 'default'
      return ''
    return '.'+@opts.gaeversion

  getDomain: ->
    @domain = 'http://'+ @opts.tenant + @gaeVersion() + '.nex9-99.appspot.com'
    @domain = 'http://localhost:8080' if @opts.debug

  parseYaml: ->
    yamlPath = @inpath+'/theme.yaml'
    process.kill() unless fs.existsSync yamlPath
    @opts = YAML.readFileSync(yamlPath)[0]

  getNextVersion: ->
    getNextDone = (data) =>
      console.log 'data', data
      @version = parseInt data
      console.log 'themeversion is', @version
      @walkFiles()

    url = @domain + '/api/v2/themeupload/next'
    restler.get(url).on('complete', getNextDone)

  pathFilter: (path) =>
    fname = path.split('/')[path.split('/').length-1]
    return false if fs.lstatSync(path).isDirectory()
    return false if fname in @exclude
    return false if fname.indexOf('.') is 0
    true

  walkFiles: ->
    paths        = walk.sync @inpath
    paths        = paths.filter @pathFilter
    @totalfiles  = paths.length
    @callcounter = @totalfiles
    console.log 'starting deployment for', @totalfiles, 'files'
    for filepath in paths
      @uploadFile filepath

  flushCache: ->
    console.log 'flushing the cache'
    data =
      data : {key: 'UWSMJGaPRcAmgXbNjOhHYrT2VzIkufKqy9eptsExCQnFD'}
    url = @domain + '/api/flushcache'
    restler.post(url, data).on('complete', (data, response) -> console.log('deployment done!'))

  cleanup: ->
    console.log 'done uploading files...'
    if @opts.setdefault
      console.log 'going to set the default version to', @version
      url = @domain + '/api/v2/themeupload/setdefault/' + @version
      restler.get(url).on('complete', @flushCache)
    else
      @flushCache()

  uploadFile: (filepath) ->

    uploadBinary = (body) =>
      stats = fs.statSync(filepath)

      data =
        multipart : true
        data : { file : restler.file(filepath, null, stats.size, null, mimetype) }
      console.log 'uploading ->', serving_path

      restler.post(body, data).on('complete', (data, response) =>
          # console.log 'done uploading', serving_path
          @callcounter -= 1
          # console.log 'callcounter...', @callcounter
          @cleanup() if @callcounter is 0
        )

    postData = (filedata) =>
      url     = @domain + '/api/v2/themeupload/uploadurl'
      payload = JSON.stringify(filedata)
      restler.post(url, {data : payload}).on('complete', uploadBinary)

    # post the request with the data and get the uploadurl
    serving_path = filepath.split('/public')[1]
    mimetype     = mime.lookup serving_path

    filedata =
      path     : serving_path
      mimetype : mimetype
      version  : @version
      sha      : 0

    fs.readFile filepath, (err, data) ->
      filedata.sha = hash('sha224', data)

      postData filedata


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



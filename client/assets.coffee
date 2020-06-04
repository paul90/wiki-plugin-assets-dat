
expand = (text)->
  text
    .replace /&/g, '&amp;'
    .replace /</g, '&lt;'
    .replace />/g, '&gt;'

ignore = (e) ->
  e.preventDefault()
  e.stopPropagation()

context = ($item) ->
  sites = [location.host]
  if remote = $item.parents('.page').data('site')
    unless remote == location.host
      sites.push remote
  journal = $item.parents('.page').data('data').journal
  for action in journal.slice(0).reverse()
    if action.site? and not sites.includes(action.site)
      sites.push action.site
  sites

prepareAssetFolder = (path) ->
  await wiki.archive.mkdir(path)
  .then () ->
    return true
  .catch (error) ->
    if error.toString().startsWith('ParentFolderDoesntExistError')
      nextPath = path.substring(0, path.lastIndexOf('/'))
      await prepareAssetFolder(nextPath)
      await prepareAssetFolder(path)


post_upload = ($item, item, assets, files) ->
  return unless files?.length

  assetFolder = ["/wiki/assets", assets].join('/')
  await prepareAssetFolder(assetFolder)
  for file in files
    reader = new FileReader()
    reader.onload = () ->
      filePath = [assetFolder, file.name].join('/')
      await wiki.archive.writeFile(filePath, reader.result)
      .then () ->
        $item.empty()
        emit $item, item
        bind $item, item
      .catch (error) ->
        console.log "Error saving asset", filePath, error
        $progress.text "Error: #{error}"
    reader.readAsArrayBuffer(file)

get_file = ($item, item, url, success) ->
  assets = item.text.match(/([\w\/-]*)/)[1]
  filename = url.split('/').reverse()[0]
  fetch(url).then((response) ->
    response.blob()
  ).then((blob) ->
    file = new File(
      [blob],
      filename,
      { type: blob.type }
    )

    success assets, file
  ).catch((e) ->
    $progress.text "Copy error: #{e.message}"
  )


delete_file = ($item, item, url) ->
  file = url.split('/').reverse()[0]
  assets = item.text
  assetFolder= ["/wiki/assets", assets].join('/')
  filePath = [assetFolder, file].join('/')
  await wiki.archive.unlink filePath
  .then () ->
    $item.empty()
    emit $item, item
    bind $item, item
  .catch (error) ->
    console.log "Error deleting asset", filePath, error
    $progress.text "Delete error: #{e.statusText} #{e.responseText||''}"


fetch_list = ($item, item, $report, assets, remote) ->
  requestSite = if remote? then remote else null
  assetsURL = wiki.site(requestSite).getDirectURL('assets')
  if assetsURL is ''
    $report.text "site not currently reachable."
    return

  link = (file) ->
    href = "#{assetsURL}/#{if assets is '' then "" else assets + "/"}#{encodeURIComponent file}"
    # todo: no action if not logged on
    act = unless isOwner
      ''
    else if remote != location.host
      '<button class="copy">⚑</button> '
    else
      '<button class="delete">✕</button> '
    
    """<span>#{act}<a href="#{href}" target=_blank>#{expand file}</a></span>"""

  render = (data) ->
    if data.error
      return $report.text "no files" if data.error.code == 'ENOENT'
      return $report.text "plugin reports: #{data.error.code}"
    files = data.files
    if files.length == 0
      return $report.text "no files"
    $report.html (link file for file in files).join "<br>"

    $report.find('button.copy').click (e) ->
      href = $(e.target).parent().find('a').attr('href')
      get_file $item, item, href, (assets, files) ->
        post_upload $item, item, assets, files

    $report.find('button.delete').click (e) ->
      href = $(e.target).parent().find('a').attr('href')
      delete_file $item, item, href

  trouble = (e) ->
    $report.text "plugin error: #{e.statusText} #{e.responseText||''}"

  if assetsURL is '/assets' or assetsURL.protocol? is "hyper:"
    try
      assetsDir = "/wiki/assets/" + assets
      assetList = await wiki.archive.readdir(assetsDir, {includeStats: true})
      assetFiles = []
      assetList.forEach (asset) ->
        if asset.stat.isFile()
          assetFiles.push(asset.name)
      render({error: null, files: assetFiles})
    catch error
      render({error: {code: 'ENOENT'}})
  else
    $.ajax
      url: wiki.site(requestSite).getURL('plugin/assets/list')
      data: {assets}
      dataType: 'json'
      success: render
      error: trouble

emit = ($item, item) ->
  uploader = ->
    return '' if $item.parents('.page').hasClass 'remote'
    """
      <div style="background-color:#ddd;" class="progress-bar" role="progressbar"></div>
      <center><button class="upload">upload</button></center>
      <input style="display: none;" type="file" name="uploads[]" multiple="multiple">
    """

  $item.append """
    <div style="background-color:#eee;padding:15px; margin-block-start:1em; margin-block-end:1em;">
      <dl style="margin:0;color:gray"></dl>
      #{uploader()}
    </div>
  """

  assets = item.text.match(/([\w\/-]*)/)[1]
  for site in context $item
    if site.length is 64
      siteName = site.slice(0,6) +  '..' + site.slice(-2)
    else
      siteName = site
    $report = $item.find('dl').prepend """
      <dt><img width=12 src="#{wiki.site(site).flag()}"> #{siteName}</dt>
      <dd style="margin:8px;"></dd>
    """
    fetch_list $item, item, $report.find('dd:first'), assets, site

bind = ($item, item) ->
  assets = item.text.match(/([\w\/-]*)/)[1]

  $item.dblclick -> wiki.textEditor $item, item

  # https://coligo.io/building-ajax-file-uploader-with-node/
  $button = $item.find '.upload'
  $input = $item.find 'input'

  $button.click (e) ->
    $input.click()

  $input.on 'change', (e) ->
    upload $(this).get(0).files

  $item.on 'dragover', ignore
  $item.on 'dragenter', ignore
  $item.on 'drop', (e) ->
    ignore e
    upload e.originalEvent.dataTransfer?.files

  upload = (files) ->
    return unless files?.length
    post_upload $item,item, assets, files

window.plugins.assets = {emit, bind} if window?
module.exports = {expand} if module?

app.view.thread = {}

app.view.thread.open = (url) ->
  url = app.url.fix(url)
  opened_at = Date.now()
  $view = $("#template > .view_thread").clone()
  $view.attr("data-url", url)
  $view.attr("data-title", url)

  app.view.module.bookmark_button($view)
  app.view.module.link_button($view)
  app.view.module.reload_button($view)

  write = (param) ->
    param or= {}
    param.url = url
    param.title = $view.attr("data-title")
    open(
      "/write/write.html?#{app.url.build_param(param)}"
      undefined
      'width=600,height=300'
    )

  sld = app.url.sld(url)
  if sld is "2ch" or sld is "livedoor"
    $view.find(".button_write").bind "click", ->
      write()
  else
    $view.find(".button_write").remove()

  #リロード処理
  $view.bind "request_reload", ->
    $view.find(".content").empty()
    $view.find(".loading_overlay").show()
    app.view.thread._draw($view)

  $("#tab_b").tab("add", element: $view[0], title: $view.attr("data-title"))

  app.view.thread._read_state_manager($view)
  app.view.thread._draw($view)
    .always ->
      app.history.add(url, $view.attr("data-title"), opened_at)

  $view
    #コンテキストメニュー 表示
    .delegate ".num", "click contextmenu", (e) ->
      if e.type is "contextmenu"
        e.preventDefault()

      app.defer =>
        $menu = $("#template > .view_thread_resmenu")
          .clone()
            .data("contextmenu_source", this)
            .appendTo($view)
        $.contextmenu($menu, e.clientX, e.clientY)

    #コンテキストメニュー 項目クリック
    .delegate ".view_thread_resmenu > *", "click", ->
      $this = $(this)
      $res = $($this.parent().data("contextmenu_source"))
        .closest("article")

      if $this.hasClass("res_to_this")
        write(message: ">>#{$res.find(".num").text()}\n")

      else if $this.hasClass("res_to_this2")
        write(message: """
        >>#{$res.find(".num").text()}
        #{$res.find(".message")[0].innerText.replace(/^/gm, '>')}\n
        """)

      else if $this.hasClass("toggle_aa_mode")
        $res.toggleClass("aa")

      else if $this.hasClass("res_permalink")
        open(url + $res.find(".num").text())

      $this.parent().remove()

    #アンカーポップアップ
    .delegate ".anchor:not(.disabled)", "mouseenter", (e) ->
      tmp = $view.find(".content")[0].children

      frag = document.createDocumentFragment()
      for anchor in app.util.parse_anchor(this.textContent).data
        for segment in anchor.segments
          now = segment[0] - 1
          end = segment[1] - 1
          while now <= end
            if tmp[now]
              frag.appendChild(tmp[now].cloneNode(true))
            else
              break
            now++

      $popup = $("<div>").append(frag)
      $.popup($view, $popup, e.clientX, e.clientY, this)

    #アンカーリンク
    .delegate ".anchor:not(.disabled)", "click", ->
      tmp = /\d+/.exec(this.textContent)
      if tmp
        app.view.thread._jump_to_res($view, tmp[0], true)

    #通常リンク
    .delegate ".message a:not(.anchor)", "click", (e) ->
      url = this.href

      #http、httpsスキーム以外ならクリックを無効化する
      if not /// ^https?:// ///.test(url)
        e.preventDefault()
        return

      #read.crxで開けるURLかどうかを判定
      flg = false
      tmp = app.url.guess_type(url)
      #スレのURLはほぼ確実に判定できるので、そのままok
      if tmp.type is "thread"
        flg = true
      #2chタイプ以外の板urlもほぼ確実に判定できる
      else if tmp.type is "board" and tmp.bbs_type isnt "2ch"
        flg = true
      #2chタイプの板は誤爆率が高いので、もう少し細かく判定する
      else if tmp.type is "board" and tmp.bbs_type is "2ch"
        #2ch自体の場合の判断はguess_typeを信じて板判定
        if app.url.sld(url) is "2ch"
          flg = true
        #ブックマークされている場合も板として判定
        else if app.bookmark.get(app.url.fix(url))
          flg = true
      #read.crxで開ける板だった場合はpreventDefaultしてopenメッセージを送出
      if flg
        e.preventDefault()
        app.message.send("open", {url})

    #IDポップアップ
    .delegate ".id.link, .id.freq", "click", (e) ->
      $container = $("<div>")
      $container.append(
        $view
          .find(".id:contains(\"#{this.textContent}\")")
            .closest("article")
              .clone()
      )
      $.popup($view, $container, e.clientX, e.clientY, this)

    #リプライポップアップ
    .delegate ".rep", "click", (e) ->
      tmp = $view.find(".content")[0].children

      frag = document.createDocumentFragment()
      for num in JSON.parse(this.getAttribute("data-replist"))
        frag.appendChild(tmp[num].cloneNode(true))

      $popup = $("<div>").append(frag)
      $.popup($view, $popup, e.clientX, e.clientY, this)

app.view.thread._jump_to_res = (view, res_num, animate_flg) ->
  $content = $(view).find(".content")
  $target = $content.children(":nth-child(#{res_num})")
  if $target.length > 0
    if animate_flg
      $content.animate(scrollTop: $target[0].offsetTop)
    else
      $content.scrollTop($target[0].offsetTop)

app.view.thread._draw = ($view) ->
  url = $view.attr("data-url")
  deferred = $.Deferred()

  app.thread.get url, (result) ->
    $message_bar = $view.find(".message_bar")
    if result.status is "error"
      $message_bar.addClass("error").text(result.message)

    if "data" of result
      thread = result.data
      $view.attr("data-title", thread.title)

      $view.find(".content").append(app.view.thread._draw_messages(thread))
      app.defer ->
        $view.triggerHandler("draw_content")

      $view
        .closest(".tab")
          .tab "update_title",
            tab_id: $view.attr("data-tab_id"),
            title: thread.title

      deferred.resolve()
    else
      deferred.reject()

    $view.find(".loading_overlay").fadeOut(100)
  deferred

app.view.thread._draw_messages = (thread) ->
  #idをキーにレスを取得出来るインデックスを作成
  id_index = {}
  for res, res_key in thread.res
    tmp = /(?:^| )(ID:(?!\?\?\?)[^ ]+)/.exec(res.other)
    if tmp
      id_index[tmp[1]] or= []
      id_index[tmp[1]].push(res_key)

  #参照インデックス構築
  rep_index = {}
  for res, res_key in thread.res
    for anchor in app.util.parse_anchor(res.message).data
      if anchor.target < 25
        for segment in anchor.segments
          i = Math.max(1, segment[0])
          while i <= Math.min(thread.res.length, segment[1])
            rep_index[i] or= []
            rep_index[i].push(res_key)
            i++

  #DOM構築
  frag = document.createDocumentFragment()
  for res, res_key in thread.res
    article = document.createElement("article")
    if /\　\ (?!<br>|$)/i.test(res.message)
      article.className = "aa"

    header = document.createElement("header")
    article.appendChild(header)

    num = document.createElement("span")
    num.className = "num"
    num.textContent = res_key + 1
    header.appendChild(num)

    name = document.createElement("span")
    name.className = "name"
    name.innerHTML = res.name
      .replace(/<(?!(?:\/?b|\/?font(?: color=[#a-zA-Z0-9]+)?)>)/g, "&lt;")
      .replace(/<\/b>(.*?)<b>/g, '<span class="ob">$1</span>')
    header.appendChild(name)

    mail = document.createElement("span")
    mail.className = "mail"
    mail.textContent = res.mail
    header.appendChild(mail)

    other = document.createElement("span")
    other.className = "other"
    other.textContent = res.other

    tmp = /(^| )(ID:(?!\?\?\?)[^ ]+)/.exec(res.other)
    if tmp
      id_count = id_index[tmp[2]].length

      elm_id = document.createElement("span")

      elm_id.className = "id"
      if id_count >= 5
        elm_id.className += " freq"
      else if id_count >= 2
        elm_id.className += " link"

      elm_id.textContent = tmp[2]
      elm_id.setAttribute("data-id_count", id_count)

      range = document.createRange()
      range.setStart(other.firstChild, tmp.index + tmp[1].length)
      range.setEnd(other.firstChild, tmp.index + tmp[1].length + tmp[2].length)
      range.deleteContents()
      range.insertNode(elm_id)
      range.detach()

    #リプライ数表示追加
    if rep_index[res_key + 1]
      rep_count = rep_index[res_key + 1].length
      rep = document.createElement("span")
      rep.className = "rep #{if rep_count >= 5 then " freq" else " link"}"
      rep.textContent = rep_count
      rep.setAttribute("data-replist", JSON.stringify(rep_index[res_key + 1]))
      other.appendChild(rep)

    header.appendChild(other)

    message = document.createElement("div")
    message.className = "message"
    message.innerHTML = res.message
      #タグ除去
      .replace(/<(?!(?:br|hr|\/?b)>).*?(?:>|$)/g, "")
      #URLリンク
      .replace(/(h)?(ttps?:\/\/[\w\-.!~*'();/?:@&=+$,%#]+)/g,
        '<a href="h$2" target="_blank" rel="noreferrer">$1$2</a>')
      #Beアイコン埋め込み表示
      .replace(///^\s*sssp://(img\.2ch\.net/ico/[\w\-_]+\.gif)\s*<br>///,
        '<img class="beicon" src="http://$1" /><br />')
      #アンカーリンク
      .replace /(?:&gt;|＞){1,2}[\d０-９]+(?:-[\d０-９]+)?(?:\s*,\s*[\d０-９]+(?:-[\d０-９]+)?)*/g, ($0) ->
        str = $0.replace /[０-９]/g, ($0) ->
          String.fromCharCode($0.charCodeAt(0) - 65248)

        reg = /(\d+)(?:-(\d+))?/g
        target_max = 25
        target_count = 0
        while ((res = reg.exec(str)) and target_count <= target_max)
          if res[2]
            if +res[2] > +res[1]
              target_count += +res[2] - +res[1]
          else
            target_count++

        disabled = target_count >= target_max

        "<a href=\"javascript:undefined;\" class=\"anchor" +
        "#{if disabled then " disabled" else ""}\">#{$0}</a>"

    article.appendChild(message)

    frag.appendChild(article)
  frag

app.view.thread._read_state_manager = ($view) ->
  url = $view.attr("data-url")

  read_state = null

  promise_get_read_state = $.Deferred (deferred) ->
    if (bookmark = app.bookmark.get(url)) and "read_state" of bookmark
      read_state = bookmark.read_state
      deferred.resolve()
    else
      app.read_state.get(url)
        .always (_read_state) ->
          read_state = _read_state or {received: 0, read: 0, last: 0, url}
          deferred.resolve()
  .promise()

  promise_first_draw = $.Deferred (deferred) ->
    $view.one "draw_content", -> deferred.resolve()
  .promise()

  $.when(promise_get_read_state, promise_first_draw).done ->
    on_updated_draw = ->
      content = $view.find(".content")[0]

      app.view.thread._jump_to_res($view, read_state.last, false)

      res_read = content.children[read_state.read - 1]
      if res_read
        res_read.classList.add("read")

      res_received = content.children[read_state.received - 1]
      if res_received
        res_received.classList.add("received")

      read_state.received = content.children.length

    on_updated_draw()
    $view.bind("draw_content", on_updated_draw)

  promise_get_read_state.done ->
    scan = ->
      read_state.last = read_state.received
      content = $view[0].querySelector(".content")
      bottom = content.scrollTop + content.clientHeight
      is_updated = false

      for res, res_num in content.children
        if res.offsetTop > bottom
          last = res_num - 1
          if read_state.last isnt last
            read_state.last = last
            is_updated = true
          break

      if read_state.read < read_state.last
        read_state.read = read_state.last
        is_updated = true

      if is_updated
        app.read_state.set(read_state)

    scroll_flag = false
    scanner = setInterval((->
      if scroll_flag
        scan()
        scroll_flag = false
    ), 250)

    $view
      .find(".content")
        .bind "scroll", ->
          scroll_flag = true
      .end()

      .bind "tab_removed", ->
        clearInterval(scanner)
        scan()

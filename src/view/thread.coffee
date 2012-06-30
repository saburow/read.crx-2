do ->
  return if /windows/i.test(navigator.userAgent)
  $.Deferred (d) ->
    if "textar_font" of localStorage
      d.resolve()
    else
      d.reject()
    return
  .pipe null, ->
    $.Deferred (d) ->
      xhr = new XMLHttpRequest()
      xhr.open("GET", "http://idawef.com/read.crx-2/textar-min.woff")
      xhr.responseType = "arraybuffer"
      xhr.onload = ->
        if @status is 200
          buffer = new Uint8Array(@response)
          s = ""
          for a in buffer
            s += String.fromCharCode(a)
          localStorage.textar_font = "data:application/x-font-woff;base64," + btoa(s)
          d.resolve()
        return
      xhr.send()
      return
  .done ->
    $ ->
      style = document.createElement("style")
      style.textContent = """
        @font-face {
          font-family: "Textar";
          src: url(#{localStorage.textar_font});
        }
      """
      document.head.appendChild(style)
      return
    return
  return


app.view_thread = {}

app.boot "/view/thread.html", ["board_title_solver", "history"], (BoardTitleSolver, History) ->
  view_url = app.url.parse_query(location.href).q
  return alert("不正な引数です") unless view_url
  view_url = app.url.fix(view_url)

  $view = $(document.documentElement)
  $view.attr("data-url", view_url)

  $content = $view.find(".content")
  $content.thread("init", url: view_url)
  $view.data("lazyload", new UI.LazyLoad($view.find(".content")[0]))
  $view.data("id_index", $content.thread("id_index"))
  $view.data("rep_index", $content.thread("rep_index"))

  app.view_module.view($view)
  app.view_module.bookmark_button($view)
  app.view_module.tool_menu($view)

  write = (param) ->
    param or= {}
    param.url = view_url
    param.title = document.title
    open(
      "/write/write.html?#{app.url.build_param(param)}"
      undefined
      'width=600,height=300'
    )

  popup_helper = (that, e, fn) ->
    $popup = fn()
    return if $popup.children().length is 0
    $popup.find("article").removeClass("last read received")
    #ポップアップ内のサムネイルの遅延ロードを解除
    $popup.find("img[data-src]").each ->
      @src = @getAttribute("data-src")
      @removeAttribute("data-src")
      return
    $.popup($view, $popup, e.clientX, e.clientY, that)

  if app.url.tsld(view_url) in ["2ch.net", "livedoor.jp"]
    $view.find(".button_write").bind "click", ->
      write()
      return
  else
    $view.find(".button_write").remove()

  #リロード処理
  $view.on "request_reload", (e, ex) ->
    #先にread_state更新処理を走らせるために、処理を飛ばす
    app.defer ->
      return if $view.hasClass("loading")
      return if $view.find(".button_reload").hasClass("disabled")

      $view
        .find(".content")
          .removeClass("searching")
          .removeAttr("data-res_search_hit_count")
        .end()
        .find(".searchbox")
          .val("")
        .end()
        .find(".hit_count")
          .hide()
          .text("")

      app.view_thread._draw($view, ex?.force_update)

    return

  #初回ロード処理
  do ->
    opened_at = Date.now()

    app.view_thread._read_state_manager($view)
    $view.one "read_state_attached", ->
      on_scroll = false
      $content.one "scroll", ->
        on_scroll = true
        return

      $last = $content.find(".last")
      if $last.length is 1
        $content.thread("scroll_to", +$last.find(".num").text(), false)

      #スクロールされなかった場合も余所の処理を走らすためにscrollを発火
      unless on_scroll
        $content.triggerHandler("scroll")

      #二度目以降のread_state_attached時に、最後に見ていたスレが当時最新のレスだった場合、新着を強調表示するためにスクロールを行う
      $view.on "read_state_attached", ->
        $tmp = $content.children(".last.received + article")
        return if $tmp.length isnt 1
        $content.thread("scroll_to", +$tmp.find(".num").text(), true, -100)
        return

    app.view_thread._draw($view)
      .always ->
        History.add(view_url, document.title, opened_at)

  $view
    #名前欄が数字だった場合のポップアップ
    .delegate ".name", "mouseenter", ->
      if /^\d+$/.test(this.textContent)
        if not this.classList.contains("name_num")
          this.classList.add("name_num")
      return

    .delegate ".name_num", "click", (e) ->
      popup_helper this, e, =>
        res = $content[0].children[+this.textContent - 1]
        $("<div>").append($(res).clone())
      return

    #レスメニュー表示
    .on "click contextmenu", "article > header", (e) ->
      if $(e.target).is("a, .link, .freq, .name_num")
        return

      if e.type is "contextmenu"
        e.preventDefault()

      $article = $(@).parent()
      $menu = $("#template > .res_menu").clone().hide().appendTo($article)

      if getSelection().toString().length is 0
        $menu.find(".copy_selection").remove()

      if $article.is(".aa")
        $menu.find(".toggle_aa_mode").text("AA表示モードを解除")
      else
        $menu.find(".toggle_aa_mode").text("AA表示モードに変更")

      unless app.url.tsld(view_url) in ["2ch.net", "livedoor.jp"]
        $menu.find(".res_to_this, .res_to_this2").remove()

      unless $article.is(".popup > article")
        $menu.find(".jump_to_this").remove()

      app.defer ->
        $menu.show()
        $.contextmenu($menu, e.clientX, e.clientY)
        return
      return

    #レスメニュー項目クリック
    .on "click", ".res_menu > li", "click", (e) ->
      $this = $(@)
      $res = $this.closest("article")

      if $this.hasClass("copy_selection")
        selectedText = getSelection().toString()
        if selectedText.length > 0
          app.clipboardWrite(selectedText)

      else if $this.hasClass("jump_to_this")
        $content.thread("scroll_to", +$res.find(".num").text(), true)

      else if $this.hasClass("res_to_this")
        write(message: ">>#{$res.find(".num").text()}\n")

      else if $this.hasClass("res_to_this2")
        write(message: """
        >>#{$res.find(".num").text()}
        #{$res.find(".message")[0].innerText.replace(/^/gm, '>')}\n
        """)

      else if $this.hasClass("toggle_aa_mode")
        $res.toggleClass("aa")

      else if $this.hasClass("res_permalink")
        open(app.safe_href(view_url + $res.find(".num").text()))

      $this.parent().remove()
      return

    #アンカーポップアップ
    .delegate ".anchor", "mouseenter", (e) ->
      popup_helper this, e, =>
        $popup = $("<div>")
        if not @classList.contains("disabled")
          tmp = $content[0].children
          for segment in app.util.parse_anchor(@innerHTML).segments
            now = segment[0] - 1
            end = segment[1] - 1
            while now <= end
              if tmp[now]
                $popup.append(tmp[now].cloneNode(true))
              else
                break
              now++
        else
          $("<div>", {
              text: @getAttribute("data-disabled_reason")
              class: "anchor_popup_disabled_message"
            })
            .appendTo($popup)
        $popup
      return

    #アンカーリンク
    .delegate ".anchor", "click", (e) ->
      e.preventDefault()
      return if @classList.contains("disabled")

      tmp = app.util.parse_anchor(@innerHTML)
      target_res_num = tmp.segments[0]?[0]
      if target_res_num?
        $content.thread("scroll_to", target_res_num, true)
      return

    #通常リンク
    .delegate ".message a:not(.anchor)", "click", (e) ->
      target_url = this.href

      #http、httpsスキーム以外ならクリックを無効化する
      if not /// ^https?:// ///.test(target_url)
        e.preventDefault()
        return

      #.open_in_rcrxが付与されている場合、処理は他モジュールに任せる
      return if @classList.contains("open_in_rcrx")

      #read.crxで開けるURLかどうかを判定
      flg = false
      tmp = app.url.guess_type(target_url)
      #スレのURLはほぼ確実に判定できるので、そのままok
      if tmp.type is "thread"
        flg = true
      #2chタイプ以外の板urlもほぼ確実に判定できる
      else if tmp.type is "board" and tmp.bbs_type isnt "2ch"
        flg = true
      #2chタイプの板は誤爆率が高いので、もう少し細かく判定する
      else if tmp.type is "board" and tmp.bbs_type is "2ch"
        #2ch自体の場合の判断はguess_typeを信じて板判定
        if app.url.tsld(target_url) is "2ch.net"
          flg = true
        #ブックマークされている場合も板として判定
        else if app.bookmark.get(app.url.fix(target_url))
          flg = true
      #read.crxで開ける板だった場合は.open_in_rcrxを付与して再度クリックイベント送出
      if flg
        e.preventDefault()
        @classList.add("open_in_rcrx")
        app.defer =>
          $(@).trigger(e)
      return

    #リンク先情報ポップアップ
    .delegate ".message a:not(.anchor)", "mouseenter", (e) ->
      tmp = app.url.guess_type(@href)
      if tmp.type is "board"
        board_url = app.url.fix(@href)
        after = ""
      else if tmp.type is "thread"
        board_url = app.url.thread_to_board(@href)
        after = "のスレ"
      else
        return

      BoardTitleSolver.ask(url: board_url, offline: true).done (title) =>
        popup_helper @, e, =>
          $("<div>", {class: "popup_linkinfo"})
            .append($("<div>", text: title + after))
        return
      return

    #IDポップアップ
    .delegate ".id.link, .id.freq, .anchor_id", app.config.get("popup_trigger"), (e) ->
      e.preventDefault()

      popup_helper @, e, =>
        id_text = @textContent
          .replace(/^id:/i, "ID:")
          .replace(/\(\d+\)$/, "")
          .replace(/\u25cf$/, "") #末尾●除去

        $popup = $("<div>")
        $content.children("article[data-id=\"#{id_text}\"]")
          .clone()
            .appendTo($popup)
        $popup
      return

    #リプライポップアップ
    .delegate ".rep", app.config.get("popup_trigger"), (e) ->
      popup_helper this, e, =>
        tmp = $content[0].children

        frag = document.createDocumentFragment()
        res_num = +$(@).closest("article").find(".num").text()
        for target_res_num in $view.data("rep_index")[res_num]
          frag.appendChild(tmp[target_res_num - 1].cloneNode(true))

        $popup = $("<div>").append(frag)
      return

  #クイックジャンプパネル
  do ->
    jump_hoge =
      ".jump_one": "article:nth-child(1)"
      ".jump_newest": "article:last-child"
      ".jump_not_read": "article.read + article"
      ".jump_new": "article.received + article"
      ".jump_last": "article.last"

    $jump_panel = $view.find(".jump_panel")

    $view.on "read_state_attached", ->
      already = {}
      for panel_item_selector, target_res_selector of jump_hoge
        res = $view[0].querySelector(target_res_selector)
        res_num = +res.querySelector(".num").textContent if res
        if res and not already[res_num]
          $jump_panel[0]
            .querySelector(panel_item_selector)
              .style["display"] = "block"
          already[res_num] = true
        else
          $jump_panel[0]
            .querySelector(panel_item_selector)
              .style["display"] = "none"
      return

    $jump_panel.on "click", (e) ->
      $target = $(e.target)

      for key, val of jump_hoge
        if $target.is(key)
          selector = val
          break

      if selector
        res_num = $view.find(selector).index() + 1

        if typeof res_num is "number"
          $content.thread("scroll_to", res_num, true)
        else
          app.log("warn", "[view_thread] .jump_panel: ターゲットが存在しません")
      return
    return

  #検索ボックス
  do ->
    search_stored_scrollTop = null
    $view
      .find(".searchbox")
        .on "input", ->
          if @value isnt ""
            if typeof search_stored_scrollTop isnt "number"
              search_stored_scrollTop = $content.scrollTop()

            hit_count = 0
            query = app.util.normalize(@value)

            scrollTop = $content.scrollTop()

            $view
              .find(".content")
                .addClass("searching")
                .children()
                  .each ->
                    if app.util.normalize(@textContent).indexOf(query) isnt -1
                      @classList.add("search_hit")
                      hit_count++
                    else
                      @classList.remove("search_hit")
                    return
                .end()
                .attr("data-res_search_hit_count", hit_count)
              .end()
              .find(".hit_count")
                .text(hit_count + "hit")
                .show()

            if scrollTop is $content.scrollTop()
              $content.triggerHandler("scroll")
          else
            $view
              .find(".content")
                .removeClass("searching")
                .removeAttr("data-res_search_hit_count")
                .find(".search_hit")
                  .removeClass("search_hit")
                .end()
              .end()
              .find(".hit_count")
                .hide()
                .text("")

            if typeof search_stored_scrollTop is "number"
              $content.scrollTop(search_stored_scrollTop)
              search_stored_scrollTop = null
          return

        .on "keyup", (e) ->
          if e.which is 27 #Esc
            if @value isnt ""
              @value = ""
              $(@).triggerHandler("input")
          return

  #フッター表示処理
  do ->
    content = $content[0]

    scroll_left = 0
    update_scroll_left = ->
      scroll_left = content.scrollHeight - (content.offsetHeight + content.scrollTop)
      return

    #未読ブックマーク数表示
    next_unread =
      _elm: $view.find(".next_unread")[0]
      show: ->
        next = null

        bookmarks = app.bookmark.get_all().filter((bookmark) -> bookmark.type is "thread" and bookmark.url isnt view_url)

        #閲覧中のスレッドに新着が有った場合は優先して扱う
        if bookmark = app.bookmark.get(view_url)
          bookmarks.unshift(bookmark)

        for bookmark in bookmarks when bookmark.res_count?
          read = null

          if iframe = parent.document.querySelector("[data-url=\"#{bookmark.url}\"]")
            read = iframe.contentDocument.querySelectorAll(".content > article").length

          unless read
            read = bookmark.read_state?.read or 0

          if bookmark.res_count > read
            next = bookmark
            break

        if next
          if next.url is view_url
            text = "新着レスがあります"
          else
            text = "未読ブックマーク: #{next.title}"
          if next.res_count?
            text += " (未読#{next.res_count - (next.read_state?.read or 0)}件)"
          @_elm.href = app.safe_href(next.url)
          @_elm.textContent = text
          @_elm.setAttribute("data-title", next.title)
          @_elm.style["display"] = "block"
        else
          @hide()
        return
      hide: ->
        @_elm.style["display"] = "none"
        return

    search_next_thread =
      _elm: $view.find(".search_next_thread")[0]
      show: ->
        if content.childNodes.length >= 1000
          @_elm.style["display"] = "block"
        else
          @hide()
        return
      hide: ->
        @_elm.style["display"] = "none"
        return

    update_thread_footer = ->
      if scroll_left is 0
        next_unread.show()
        search_next_thread.show()
      else
        next_unread.hide()
        search_next_thread.hide()
      return

    $view
      .on "tab_selected view_loaded", ->
        update_thread_footer()
        return

      .find(".content").on "scroll", ->
        update_scroll_left()
        update_thread_footer()
        return
      .end()

      #次スレ検索
      .find(".button_tool_search_next_thread, .search_next_thread").on "click", (e) ->
        if $view.find(".next_thread_list:visible").length isnt 0
          return
        $div = $("#template > .next_thread_list").clone()
        $div.find(".close").one "click", ->
          $div.fadeOut("fast", -> $div.remove)
          return
        $div.find(".current").text(document.title)
        $div.find(".status").text("検索中")
        $div.appendTo(document.body)
        app.util.search_next_thread(view_url, document.title)
          .done (res) ->
            $div.find(".status").text("")
            $ol = $div.find("ol")
            for thread in res
              $("<li>", {
                class: "open_in_rcrx"
                text: thread.title
                "data-href": thread.url
              }).appendTo($ol)
            return
          .fail ->
            $div.find(".status").text("次スレ検索に失敗しました")
            return
        return

    app.message.add_listener "bookmark_updated", (message) ->
      if scroll_left is 0
        next_unread.show()
      return

    return

  #サムネイルロード時の縦位置調整
  $view.on "lazyload-load", ".thumbnail > a > img", ->
    a = @parentNode
    container = a.parentNode
    a.style["top"] = "#{(container.offsetHeight - a.offsetHeight) / 2}px"

  #パンくずリスト表示
  do ->
    board_url = app.url.thread_to_board(view_url)
    BoardTitleSolver.ask(url: board_url, offline: true).always (title) ->
      $view
        .find(".breadcrumb > li > a")
          .attr("href", board_url)
          .text(if title? then "#{title.replace(/板$/, "")}板" else "板")
          .css("display", "none")
      # Windows版Chromeで描画が崩れる現象を防ぐため、わざとリフローさせる。
      app.defer ->
        $view.find(".breadcrumb > li > a").css("display", "inline-block")
        return
      return
    return

  return

app.view_thread._draw = ($view, force_update) ->
  deferred = $.Deferred()

  $view.addClass("loading")
  $reload_button = $view.find(".button_reload")
  $reload_button.addClass("disabled")
  content = $view.find(".content")[0]

  fn = (thread, error) ->
    if error
      $view.find(".message_bar").addClass("error").html(thread.message)
    else
      $view.find(".message_bar").removeClass("error").empty()

    (deferred.reject(); return) unless thread.res?

    document.title = thread.title

    $(content).thread("add_item", thread.res.slice(content.children.length))

    #サムネイル追加処理
    do ->
      fn_add_thumbnail = (source_a, thumb_path) ->
        source_a.classList.add("has_thumbnail")

        thumb = document.createElement("div")
        thumb.className = "thumbnail"

        thumb_link = document.createElement("a")
        thumb_link.href = app.safe_href(source_a.href)
        thumb_link.target = "_blank"
        thumb_link.rel = "noreferrer"
        thumb.appendChild(thumb_link)

        thumb_img = document.createElement("img")
        thumb_img.src = "/img/loading.svg"
        thumb_img.setAttribute("data-src", thumb_path)
        thumb_link.appendChild(thumb_img)

        sib = source_a
        while true
          pre = sib
          sib = pre.nextSibling
          if sib is null or sib.nodeName is "BR"
            if sib?.nextSibling?.classList?.contains("thumbnail")
              continue
            if not pre.classList?.contains("thumbnail")
              source_a.parentNode.insertBefore(document.createElement("br"), sib)
            source_a.parentNode.insertBefore(thumb, sib)
            break
        null

      config_thumbnail_supported =
        app.config.get("thumbnail_supported") is "on"
      config_thumbnail_ext =
        app.config.get("thumbnail_ext") is "on"

      for a in content.querySelectorAll(".message > a:not(.thumbnail):not(.has_thumbnail)")
        #サムネイル表示(対応サイト)
        if config_thumbnail_supported
          #YouTube
          if res = /// ^http://
              (?:www\.youtube\.com/watch\?v=|youtu\.be/)
              ([\w\-]+).*
            ///.exec(a.href)
            fn_add_thumbnail(a, "http://img.youtube.com/vi/#{res[1]}/default.jpg")
          #ニコニコ動画
          else if res = /// ^http://(?:www\.nicovideo\.jp/watch/|nico\.ms/)
              (?:sm|nm)(\d+) ///.exec(a.href)
            tmp = "http://tn-skr#{parseInt(res[1], 10) % 4 + 1}.smilevideo.jp"
            tmp += "/smile?i=#{res[1]}"
            fn_add_thumbnail(a, tmp)

        #サムネイル表示(画像っぽいURL)
        if config_thumbnail_ext
          if /\.(?:png|jpe?g|gif|bmp|webp)(?:[\?#].*)?$/i.test(a.href)
            fn_add_thumbnail(a, a.href)

    $view.data("lazyload").scan()

    $view.trigger("view_loaded")

    deferred.resolve()

  app.module null, ["thread"], (Thread) ->
    thread = new Thread($view.attr("data-url"))
    thread.get(force_update)
      .progress ->
        fn(thread, false)
        return
      .done ->
        fn(thread, false)
        return
      .fail ->
        fn(thread, true)
        return
      .always ->
        $view.removeClass("loading")
        setTimeout((-> $reload_button.removeClass("disabled")), 1000 * 5)
        return
    return

  deferred.promise()

app.view_thread._read_state_manager = ($view) ->
  view_url = $view.attr("data-url")
  board_url = app.url.thread_to_board(view_url)
  $content = $($view.find(".content"))
  content = $content[0]

  #read_stateの取得
  get_read_state = $.Deferred (deferred) ->
    read_state_updated = false
    if (bookmark = app.bookmark.get(view_url))?.read_state?
      read_state = bookmark.read_state
      deferred.resolve({read_state, read_state_updated})
    else
      app.read_state.get(view_url).always (_read_state) ->
        read_state = _read_state or {received: 0, read: 0, last: 0, url: view_url}
        deferred.resolve({read_state, read_state_updated})
  .promise()

  #スレの描画時に、read_state関連のクラスを付与する
  $view.on "view_loaded", ->
    get_read_state.done ({read_state, read_state_updated}) ->
      content.querySelector(".last")?.classList.remove("last")
      content.querySelector(".read")?.classList.remove("read")
      content.querySelector(".received")?.classList.remove("received")

      content.children[read_state.last - 1]?.classList.add("last")
      content.children[read_state.read - 1]?.classList.add("read")
      content.children[read_state.received - 1]?.classList.add("received")

      $view.triggerHandler("read_state_attached")
    return

  get_read_state.done ({read_state, read_state_updated}) ->
    scan = ->
      received = content.childNodes.length
      #onbeforeunload内で呼び出された時に、この値が0になる場合が有る
      return if received is 0

      last = $content.thread("get_read")

      if read_state.received isnt received
        read_state.received = received
        read_state_updated = true

      if read_state.last isnt last
        read_state.last = last
        read_state_updated = true

      if read_state.read < read_state.last
        read_state.read = read_state.last
        read_state_updated = true
      return

    #アンロード時は非同期系の処理をzombie.htmlに渡す
    #そのためにlocalStorageに更新するread_stateの情報を渡す
    on_beforeunload = ->
      scan()
      if read_state_updated
        if localStorage.zombie_read_state?
          data = JSON.parse(localStorage["zombie_read_state"])
        else
          data = []
        data.push(read_state)
        localStorage["zombie_read_state"] = JSON.stringify(data)
      return

    window.addEventListener("beforeunload", on_beforeunload)

    #スクロールされたら定期的にスキャンを実行する
    scroll_flg = false
    scroll_watcher = setInterval ->
      if scroll_flg
        scroll_flg = false
        scan()
        if read_state_updated
          app.message.send("read_state_updated", {board_url, read_state})
    , 250

    scan_and_save = ->
      scan()
      if read_state_updated
        app.read_state.set(read_state)
        app.bookmark.update_read_state(read_state)
        read_state_updated = false

    app.message.add_listener "request_update_read_state", (message) ->
      if not message.board_url? or message.board_url is board_url
        scan_and_save()
      return

    $view
      .find(".content")
        .on "scroll", ->
          scroll_flg = true
          return
      .end()

      .on "request_reload", ->
        scan_and_save()
        return

    window.addEventListener "view_unload", ->
      clearInterval(scroll_watcher)
      window.removeEventListener("beforeunload", on_beforeunload)
      #ロード中に閉じられた場合、スキャンは行わない
      return if $view.hasClass("loading")
      scan_and_save()
      return

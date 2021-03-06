(($)->
  template_confirm = """
    <div class="dialog dialog_confirm dialog_overlay">
      <div class="dialog_spacer"></div>
      <div class="dialog_body">
        <div class="dialog_message"></div>
        <div class="dialog_bottom">
          <button class="dialog_ok"></button>
          <button class="dialog_no"></button>
        </div>
      </div>
      <div class="dialog_spacer"></div>
    </div>
  """

  $.dialog = (method, prop) ->
    $.Deferred (deferred) ->
      #prop.message, prop.label_ok, prop.label_no
      if method is "confirm"
        $(template_confirm)
          .find(".dialog_message")
            .text(prop.message)
          .end()
          .find(".dialog_ok")
            .text(prop.label_ok)
            .bind "click", ->
              $(@).closest(".dialog").remove()
              deferred.resolve(true)
          .end()
          .find(".dialog_no")
            .text(prop.label_no)
            .bind "click", ->
              $(@).closest(".dialog").remove()
              deferred.resolve(false)
          .end()
          .appendTo("body")
      else
        deferred.reject()
    .promise()
)(jQuery)

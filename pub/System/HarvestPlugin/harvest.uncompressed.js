"use strict";
jQuery(function($) {

  var gotChangeEvent = false;

  $(document).on("change", "#selecttoggle", function() {
    var $this = $(this);
    if ($this.is(":checked")) {
      $this.parent().find("#selectall").hide();
      $this.parent().find("#clearall").show();
      $(".harvestResults input").parent().parent().addClass("foswikiSelected");
      $(".harvestResults input").prop('checked', true);
    } else {
      $this.parent().find("#selectall").show();
      $this.parent().find("#clearall").hide();
      $(".harvestResults input").parent().parent().removeClass('foswikiSelected');
      $(".harvestResults input").prop('checked', false);
    }
  });

  $("#analyzeForm").livequery(function() {
    $(this).ajaxForm({
      dataType:"json",
      beforeSubmit: function() {
        $.blockUI({message:"<h1>Inspecting ...</h1>"});
        $("#messageContainer").hide();
      },
      success: function(data) {
        var downloadForm = $("#downloadForm"), 
            len = data.result.length, 
            container = $("<table class='harvestResults'></table>");
        $.unblockUI();
        $.pnotify({
          pnotify_history: false,
          pnotify_text: len+" item(s) found",
          pnotify_delay: 2000,
          pnotify_opacity: 0.9
        });
        container.html($("#imageTemplate").render(data.result));
        $(".harvestResults").replaceWith(container);
        downloadForm.show();
        //$this.hide();
      },
      error: function(xhr) {
        var obj = $.parseJSON(xhr.responseText);
        $.unblockUI();
        $.pnotify({
          pnotify_history: false,
          pnotify_title: "Error",
          pnotify_text: obj.error.message,
          pnotify_type: "error",
          pnotify_delay: 2000,
          pnotify_opacity: 0.9
        });
      }
    });  
  });

  $("#downloadForm").livequery(function() {
    $(this).ajaxForm({
      dataType:"json",
      type:"post",
      beforeSubmit: function() {
        $.blockUI({message:"<h1>Downloading ...</h1>"});
        $("#messageContainer").empty().hide();
      },
      success: function(data) {
        var url = foswiki.getPreference("SCRIPTURL")+"/view/"+foswiki.getPreference("WEB")+"/"+foswiki.getPreference("TOPIC");
        $.unblockUI();
        $.blockUI({message:"<h1>"+data.result+"</h1>"});
        window.setTimeout(function() {
          window.location.href = url;
        }, 500);
      },
      error: function(xhr) {
        var data = xhr.responseJSON;
        $.unblockUI();
        $("#messageContainer").append("<div class='foswikiErrorMessage'>Error: "+data.error.message+"</div>").show();
        $("#downloadForm").hide();
      }
    });
  });

  $(document).on("click", ".harvestResults td", function(e) {
    var $target = $(e.target),
        $elem;

    if ($target.is("input[type=checkbox]")) {
      selectRow($target);
    } else {
      $elem = $(this).parents('tr:first').find('input[type=checkbox]');
      if ($elem.is(":checked")) {
        $elem.prop("checked", false);
      } else {
        $elem.prop("checked", true);
      }
      selectRow($elem);
      return false;
    }
  });

  function selectRow(elem) {
    var $row = elem.parents("tr:first");

    if (elem.is(":checked")) {
      $row.addClass("foswikiSelected");
    } else {
      $row.removeClass("foswikiSelected");
    }
  }

  $(".harvestResults img").livequery(function() {
    var $this = $(this);
    $this.tooltip({
        show: {
          delay: 350
        },
        position: { 
          my: "left+15 top+20", 
          at: "left bottom", 
          collision: "flipfit" 
        },
        track:true,
        content: function() { 
            return $("<img/>").attr('src', $this.attr("src")).css({
              "max-width": 300,
              "max-height": 600
            });
        }
      });
  });
});


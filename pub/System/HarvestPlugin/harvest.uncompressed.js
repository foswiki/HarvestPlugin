jQuery(function($) {
"use strict";

  var gotChangeEvent = false;

  $("#selecttoggle").change(function() {
    var $this = $(this);
    if ($this.is(":checked")) {
      $this.parent().find("#selectall").hide();
      $this.parent().find("#clearall").show();
      $(".harvestResults input").parent().parent().addClass("selected");
      $(".harvestResults input").attr('checked', 'checked');
    } else {
      $this.parent().find("#selectall").show();
      $this.parent().find("#clearall").hide();
      $(".harvestResults input").parent().parent().removeClass('selected');
      $(".harvestResults input").removeAttr('checked');
    }
  });

  $("#analyzeForm").ajaxForm({
    dataType:"json",
    beforeSubmit: function() {
      $.blockUI({message:"<h1>Inspecting ...</h1>"});
      $("#messageContainer").hide();
    },
    success: function(data, msg, xhr) {
      var downloadForm = $("#downloadForm"), 
          len = data.result.length, i,
          container = $("<table class='harvestResults'></table>");
      $.unblockUI();
      $.pnotify({
        pnotify_history: false,
        pnotify_text: len+" images found",
        pnotify_delay: 2000,
        pnotify_opacity: 0.9
      });
      container.html($("#imageTemplate").render(data.result));
      $(".harvestResults").replaceWith(container);
      downloadForm.show();
      //$("#analyzeForm").hide();
    },
    error: function(xhr, status, error) {
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

  $("#downloadForm").ajaxForm({
    dataType:"json",
    type:"post",
    beforeSubmit: function() {
      $.blockUI({message:"<h1>Downloading ...</h1>"});
      $("#messageContainer").empty().hide();
    },
    success: function(data, msg, xhr) {
      var url = foswiki.getPreference("SCRIPTURL")+"/view/"+foswiki.getPreference("WEB")+"/"+foswiki.getPreference("TOPIC");
      $.unblockUI();
      $.blockUI({message:"<h1>"+data.result+"</h1>"});
      window.setTimeout(function() {
        window.location.href = url;
      }, 500);
    },
    error: function(xhr, status, error) {
      var data = xhr.responseJSON;
      $.unblockUI();
      $("#messageContainer").append("<div class='foswikiErrorMessage'>Error: "+data.error.message+"</div>").show();
      $("#downloadForm").hide();
    }
  });

  $(document).on("change", ".harvestResults input", function(e) {
    gotChangeEvent = true;
    window.setTimeout(function() {
      gotChangeEvent = false;
    }, 200);
    selectRow(this);
  });

  $(document).on("click", ".harvestResults td", function(e) {
    var $elem = $(this).parents('tr:first').find('input[type=checkbox]');
    if (!gotChangeEvent) {
      if ($elem.is(":checked")) {
        $elem.removeAttr("checked");
      } else {
        $elem.attr("checked", "checked");
      }
      selectRow($elem);
      return false;
    }
  });

  function selectRow(elem) {
    var $elem = $(elem),
        $row = $elem.parents("tr:first"),
        text = "selected",
        classStr = "plus";

    if ($elem.is(":checked")) {
      $row.addClass("selected");
    } else {
      $row.removeClass("selected");
      text = "unselected";
      classStr = "minus";
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


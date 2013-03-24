###########################################################
# Model
############################################################

class TenPointModel extends Backbone.Model
  idAttribute: "_id"

  setHandlers: =>
    intertwinkles.socket.on "tenpoints:tenpoint", @_load
    intertwinkles.socket.on "tenpoints:point", @_setPoint
    intertwinkles.socket.on "tenpoints:support", @_setSupport
    intertwinkles.socket.on "tenpoints:editing", @_setEditing

  _load: (data) =>
    @set data.model

  _getPoint: (point_id) =>
    return _.find @get("points"), (p) -> p._id == point_id

  _matchSupporter: (data, supporter) =>
    d = data
    s = supporter
    return (
      (s.user_id? and d.user_id? and s.user_id == d.user_id) or
      (not s.user_id? and not data.user_id? and
       s.name and d.name and s.name == d.name)
    )

  _setPoint: (data) =>
    point = @_getPoint(data.point._id)
    if point?
      _.extend(point, data.point)
      @trigger "change:point:#{point._id}", point
    else
      @get("points").push(data.point)
      @trigger "change:points"

  _setSupport: (data) =>
    point = @_getPoint(data.point_id)
    return @fetch() unless point?
    find_supporter = _.find point.supporters, (s) => @_matchSupporter(data, s)
    if data.vote
      if not _.find(point.supporters, find_supporter)
        point.supporters.push({
          user_id: data.user_id
          name: data.name
        })
        trigger "change:point:#{point._id}"
    else
      point.supporters = _.reject(point.supporters, find_supporter)
      trigger "change:point:#{point._id}"

  _setEditing: (data) =>
    point = @_getPoint(data.point_id)
    return @fetch() unless point?
    point.editing = data.editing
    trigger "change:point:#{point._id}"

  fetch: (cb) =>
    return unless @get("slug")
    if cb?
      intertwinkles.socket.once "tenpoints:tenpoint", (data) =>
        @_load(data)
        cb(null, this)
    intertwinkles.socket.send "tenpoints/fetch_tenpoint", {slug: @get("slug")}

  save: (update, opts) =>
    @set(update) if update?
    data = {
      model: {
        _id: @id
        name: @get("name")
        slug: @get("slug")
        number_of_points: @get("number_of_points")
        sharing: @get("sharing")
      }
    }
    if opts.success? or opts.error?
      intertwinkles.socket.once "tenpoints:tenpoint", (data) =>
        opts.error(data.error) if data.error?
        opts.success(data.model) if data.model?
    intertwinkles.socket.send "tenpoints/save_tenpoint", data
        

fetchTenPointList = (cb) =>
  intertwinkles.socket.once "tenpoints:list", cb
  intertwinkles.socket.send "tenpoints/fetch_tenpoint_list"

###########################################################
# Views
###########################################################

class TenPointsBaseView extends intertwinkles.BaseView
  events: 'click .softnav': 'softNav'
  render: => @$el.html(@template())

#
# Front matter
#

class SplashView extends TenPointsBaseView
  template:     _.template $("#splashTemplate").html()
  itemTemplate: _.template $("#splashItemTemplate").html()
  
  initialize: (options) ->
    @setTenPointList(options.tenPointList, false)
    intertwinkles.user.on  "change", @fetchTenPointList, this

  remove: =>
    super()
    intertwinkles.user.off "change", @fetchTenPointList, this

  fetchTenPointList: => fetchTenPointList(@setTenPointList)

  setTenPointList: (data, render=true) =>
    @tenPointList = {
      group: (new TenPointModel(tp) for tp in data.group or [])
      public: (new TenPointModel(tp) for tp in data.public or [])
    }
    if render
      @render()

  render: =>
    @$el.html(@template())
    if @tenPointList.group?.length > 0
      @$(".group-tenpoints").html("<ul></ul>")
      for tenpoint in @tenPointList.group
        @_addItem(".group-tenpoints ul", tenpoint)
    if @tenPointList.public?.length > 0
      @$(".public-tenpoints").html("<ul></ul>")
      for tenpoint in @tenPointList.public
        @_addItem(".public-tenpoints ul", tenpoint)
    intertwinkles.sub_vars(@el)

  _addItem: (selector, tenpoint) =>
    @$(selector).append(@itemTemplate(tenpoint: tenpoint))
  
class EditTenPointView extends TenPointsBaseView
  template: _.template $("#editTemplate").html()
  events:
    'click .softnav': 'softNav'
    'submit    form': 'saveTenPoint'
    'keyup #id_name': 'setSlug'
    'keyup #id_slug': 'checkSlug'

  initialize: (options) ->
    super()
    if options?.model.id
      @model = options.model
      @title = "Edit Board Settings"
      @action = "Save"
    else
      @model = new TenPointModel()
      @title = "Add new board"
      @action = "Add board"

  _slugCheck = (show) =>

  setSlug: =>
    unless @model.get("slug")
      @$("#id_slug").val(intertwinkles.slugify(@$("#id_name").val()))
    @checkSlug()

  checkSlug: =>
    val = @$("#id_slug").val()
    parent = @$("#id_slug").closest(".control-group")
    showURL = ->
      parent.find(".url-display").html(
        "#{INTERTWINKLES_APPS.tenpoints.url}/10/#{encodeURIComponent(val)}/"
      )
    if val and val != @model.get("slug")
      intertwinkles.socket.send "tenpoints/check_slug", {slug: val}
      intertwinkles.socket.once "tenpoints:check_slug", (data) =>
        parent.removeClass('error')
        parent.find(".error-msg").remove()
        if data.ok
          showURL()
        else
          parent.addClass('error')
          @$("#id_slug").after("<span class='help-inline error-msg'>Name not available</span>")
          parent.find(".url-display").html("")
    else if val == @model.get("slug")
      showURL()


  render: =>
    @$el.html(@template({
      model: @model.toJSON()
      title: @title
      action: @action
    }))
    @sharing_control?.remove()
    @sharing_control = new intertwinkles.SharingFormControl({
      sharing: @model.get("sharing")
    })
    @addView("#sharing_controls", @sharing_control)
  
  saveTenPoint: (event) =>
    event.preventDefault()
    cleaned_data = @validate()
    if cleaned_data
      @model.save {
        name: cleaned_data.name
        slug: cleaned_data.slug
        number_of_points: cleaned_data.number_of_points
        sharing: @sharing_control.sharing
      }, {
        success: (model) =>
          intertwinkles.app.navigate("/tenpoints/10/#{model.slug}/", {trigger: true})
      }

  validate: =>
    return @validateFields "form", [
      ["#id_name", ((val) -> $.trim(val) or null), "This field is required."]
      ["#id_slug", ((val) -> $.trim(val) or null), "This field is required."]
      ["#id_number_of_points", (val) ->
        num = parseInt(val, 10)
        if not isNaN(num) and num > 0
          return num
        return null
      , "Number bigger than 0 required"]
    ]

class TenPointView extends TenPointsBaseView
  template: _.template $("#tenpointTemplate").html()
  initialize: (options) ->
    @model = options.model
  render: =>
    @$el.html(@template(model: @model.toJSON()))

###########################################################
# Router
###########################################################

class Router extends Backbone.Router
  routes:
    "tenpoints/10/:slug/point/:point_id/": "pointDetail"
    "tenpoints/10/:slug/history/:point_id/": "history"
    "tenpoints/10/:slug/edit/": "edit"
    "tenpoints/10/:slug/": "board"
    "tenpoints/add/": "add"
    "tenpoints/": "index"

  initialize: ->
    @model = new TenPointModel()
    @model.setHandlers()
    @model.set(INITIAL_DATA.tenpoint or {})
    @tenPointList = INITIAL_DATA.ten_points_list
    @_joinRoom(@model) if @model.id?
    super()

  pointDetail: (slug, point_id) =>
    $("title").html(@model.get("name") + " - Ten Points")
    @_open(
      new PointDetailView({model: @model, point_id: point_id}), slug
    )
  history: (slug, point_id) =>
    $("title").html(@model.get("name") + " - Ten Points")
    @_open(
      new HistoryView({model: @model, point_id: point_id}), slug
    )
  edit: (slug) =>
    $("title").html("Edit " + @model.get("name") + " - Ten Points")
    @_open(new EditTenPointView({model: @model}), slug)
  board: (slug) =>
    $("title").html(@model.get("name") + " - Ten Points")
    @_open(new TenPointView({model: @model}), slug)
  add: =>
    $("title").html("Add - Ten Points")
    @_open(new EditTenPointView({model: @model}), null)
  index: =>
    $("title").html("Ten Points")
    view = new SplashView(tenPointList: @tenPointList)
    if @view?
      fetchTenPointList(view.setTenPointList)
    @_open(view, null)

  onReconnect: =>
    @model.fetch()
    @_joinRoom(@model)

  _open: (view, slug) =>
    if @model.get("slug") and @model.get("slug") != slug
      @_leaveRoom()
    if slug? and not @model.get("slug")?
      @model.set({slug: slug})
      return @model.fetch =>
        $("title").html(@model.get("name") + " - Ten Points")
        @_joinRoom(@model)
        @_showView(view)
    else
      @_showView(view)

  _showView: (view) =>
    @view?.remove()
    $("#app").html(view.el)
    view.render()
    @view = view
    window.scrollTo(0, 0)

  _leaveRoom: =>
    @roomView?.$el.before("<li class='room-users'></li>")
    @roomView?.remove()
    @sharingView?.remove()

  _joinRoom: =>
    @_leaveRoom()

    @roomView = new intertwinkles.RoomUsersMenu(room: "tenpoints/#{@model.id}")
    $(".sharing-online-group .room-users").replaceWith(@roomView.el)
    @roomView.render()

    @sharingView = new intertwinkles.SharingSettingsButton(model: @model)
    $(".sharing-online-group .sharing").html(@sharingView.el)
    @sharingView.render()
    @sharingView.on "save", (sharing) =>
      @model.save {sharing}, {success: => @sharingView.close()}

###########################################################
# Main
###########################################################

app = null
intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "tenpoints"})
  intertwinkles.build_footer($("footer"))

  unless app?
    app = intertwinkles.app = new Router()
    Backbone.history.start({pushState: true, hashChange: false})
    intertwinkles.socket.on "reconnect", ->
      intertwinkles.socket.once "identified", ->
        app.onReconnect()
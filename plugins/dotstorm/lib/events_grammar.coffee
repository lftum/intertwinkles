logger = require("log4js").getLogger()

module.exports = {
  get_terms: (event) ->
    return null unless event.application == "dotstorm"
    switch event.type
      when "create"
        return [{
          entity: "Dotstorm"
          aspect: "\"#{event.data.entity_name}\""
          collective: "created dotstorms"
          verbed: "created"
          manner: ""
        }]
      when "visit"
        return [{
          entity: event.data.entity_name
          aspect: "dotstorm"
          collective: "visited dotstorms"
          verbed: "visited"
          manner: ""
        }]
      when "update"
        attributes = []
        for key in ["name", "topic"]
          if event.data[key]?
            attributes.push({
              entity: event.data.entity_name
              aspect: key
              collective: "changed dotstorms"
              verbed: "changed"
              manner: "from \"#{event.data["old_" + key]}\" to \"#{event.data[key]}\""
            })
        if event.data.sharing?
          attributes.push({
            entity: event.data.entity_name
            aspect: "sharing settings"
            collective: "changed dotstorms"
            verbed: "changed"
            manner: ""
          })
        if event.data.rearranged?
          attributes.push({
            entity: event.data.entity_name
            aspect: "ideas"
            collective: "changed dotstorms"
            verbed: "rearranged"
            manner: ""
          })
        return attributes
      when "append"
        if event.data.is_new
          return [{
            entity: event.data.entity_name
            aspect: "idea"
            collective: "added ideas"
            verbed: "added"
            manner: event.data.description
            image: event.data.image
          }]
        else
          return [{
            entity: event.data.entity_name
            aspect: "idea"
            collective: "edited ideas"
            verbed: "edited"
            manner: ""
            image: event.data.image
          }]
    logger.error("Unknown event type \"#{event.type}\"")
    return null
}
_      = require 'underscore'
async  = require 'async'
expect = require 'expect.js'
config = require './test_config'
common = require './common'
schema = require('../lib/schema').load(config)
email_notices = require("../lib/email_notices").load(config)
api_methods = require("../lib/api_methods")(config)

describe "Activity summaries", ->
  mail = null
  before (done) ->
    common.startUp (server) =>
      @server = server
      common.startMailServer (mailserver) ->
        mail = mailserver
        done()

  after (done) ->
    common.shutDown(@server, done)

  it "renders summary", (done) ->
    async.waterfall [
      (done) ->
        schema.User.findOne {email: "one@mockmyid.com"}, (err, user) ->
          expect(err).to.be(null)
          user.notifications.activity_summaries.sms = true
          user.notifications.activity_summaries.email = true
          user.mobile.number = "1234567890"
          user.mobile.carrier = "T-Mobile"
          user.save (err, doc) ->
            done(err, doc)
      (user, done) ->
        schema.Group.findOne {slug: "two-members"}, (err, group) ->
          expect(err).to.be(null)
          api_methods.post_event {
            application: "www"
            entity: group._id
            type: "join"
            user: user
            group: group._id
            anon_id: "anon"
            url: group.url
            data: {entity_name: group.name}
          }, (err, event) ->
            done(err, user, group, event)

      (user, group, event, done) ->
        email_notices.render_daily_activity_summary user, new Date(), (err, formats) ->
          expect(err).to.be(null)
          expect(formats).to.not.be(null)
          sms = "Recent InterTwinkles activity: 1 edit #{config.short_url_base}"
          expect(formats.sms.substring(0, sms.length)).to.be(sms)
          expect(formats.email.subject).to.not.a(String)
          expect(formats.email.text).to.not.a(String)
          expect(formats.email.html).to.not.a(String)
          done()

    ], done

  it "sends email", (done) ->
    mail.outbox.length = 0
    email_notices.send_daily_activity_summaries (err, count) ->
      expect(err).to.be(null)
      expect(count).to.be(2) # two people (members of two-members)
      expect(mail.outbox.length).to.be(3) # one sms, two emails
      recipients = (m.to[0].address for m in mail.outbox)
      recipients.sort()
      expect(recipients).to.eql(
        ["1234567890@tmomail.net", "one@mockmyid.com", "two@mockmyid.com"]
      )
      done()
      
require "http/client"
require "json"
require "mongo"
require "option_parser"
require "./modlookup.cr"

# TODO: Write documentation for `Modlookup::Listener`

module Modlookup::Listener
  VERSION = "0.1.0"

  track_user_info   = false
  verbose = false

  OptionParser.parse! do |parser|
    parser.banner = "Usage: modlookup-listener [arguments]"
    parser.on("-u", "--users", "Track user data too (staff, partner, etc)") { track_user_info = true }
    parser.on("-v", "--verbose", "Enable verbose logging") { verbose = true }
    parser.on("-h", "--help", "Show this help") { puts parser }
  end

  config = Modlookup::Config.from_yaml(File.read("/etc/modlookup.yml"))

  if config.mongouser.nil?
    mongodb = Mongo::Client.new "mongodb://#{config.mongohost}:#{config.mongoport}/#{config.mongodb}"
  else
    mongodb = Mongo::Client.new "mongodb://#{config.mongouser}:#{config.mongopass}@#{config.mongohost}:#{config.mongoport}/admin"
  end

  db = mongodb[config.mongodb]
  modstate = db["modstate"].as(Mongo::Collection)
  usercoll = db["user"].as(Mongo::Collection)
  bans = db["bans"].as(Mongo::Collection)

  modstate_indexes = modstate.find_indexes()
  modstate_has_index = false
  modstate_indexes.each do |index|
    if index["name"] == "nick_1_channel_1"
      modstate_has_index = true
    end
  end

  user_indexes = usercoll.find_indexes()
  user_has_index = false
  user_indexes.each do |index|
    if index["name"] == "nick_1"
      user_has_index = true
    end
  end

  ban_indexes = bans.find_indexes()
  ban_has_expire_index = false
  ban_has_lookup_index = false
  ban_has_channel_index = false
  ban_has_user_index = false
  ban_indexes.each do |index|
    if index["name"] == "channel_1_user_1"
      ban_has_lookup_index = true
    elsif index["name"] == "expiration"
      ban_has_expire_index = true
    elsif index["name"] == "channel_1"
      ban_has_channel_index = true
    elsif index["name"] == "user_1"
      ban_has_user_index = true
    end
  end

  if modstate_has_index == false
    puts "We are missing an index. Creating an index for nick and channel to speedup processing."
    modstate.create_index(BSON.from_json({ "nick": 1, "channel": 1 }.to_json),Mongo::IndexOpt.new(true,false,"nick_1_channel_1",false,false,0,nil,nil,nil))
  end

  if user_has_index == false
    puts "We are missing an index. Creating an index for users to speedup processing."
    usercoll.create_index(BSON.from_json({ "nick": 1 }.to_json),Mongo::IndexOpt.new(true,false,"nick_1",false,false,0,nil,nil,nil))
  end

  if ban_has_expire_index == false
    puts "We are missing an index. Creating an index for bans to expire timeouts."
    bans.create_index(BSON.from_json({ "expires": 1 }.to_json),Mongo::IndexOpt.new(true,false,"expiration",false,false,1,nil,nil,nil))
  end

  if ban_has_lookup_index == false
    puts "We are missing an index. Creating an index for bans to speedup processing."
    bans.create_index(BSON.from_json({ "channel": 1, "user": 1 }.to_json),Mongo::IndexOpt.new(true,false,"channel_1_user_1",false,false,0,nil,nil,nil))
  end

  if ban_has_channel_index == false
    puts "We are missing an index. Creating an index for bans to speedup processing."
    bans.create_index(BSON.from_json({ "channel": 1 }.to_json),Mongo::IndexOpt.new(true,false,"channel_1",false,false,0,nil,nil,nil))
  end

  if ban_has_user_index == false
    puts "We are missing an index. Creating an index for bans to speedup processing."
    bans.create_index(BSON.from_json({ "user": 1 }.to_json),Mongo::IndexOpt.new(true,false,"user_1",false,false,0,nil,nil,nil))
  end

  chan = Channel(Modlookup::TwitchMessage | Nil).new

  spawn do
    puts "Starting firehose listener"
    HTTP::Client.get("http://tmi.twitch.tv/firehose?oauth_token=#{config.oauth}") do |response|
      if response.success?
        while true
          if !response.nil?
            data = response.body_io.gets
            if !data.nil?
              if /data:/.match data
                json_array = data.split("data: ")
                json_array.delete_at(0)
                twitch = Modlookup::TwitchMessage.from_json(json_array.join(""))
                chan.send(twitch)
              end
            end
          else
            exit(1)
          end
        end
      else
        puts "#{response.status_code}"
        puts "#{response.body}"
      end
    end
  end

  while twitch = chan.receive
    case twitch.command
    when ""
      if !twitch.tags.badges.nil?
        mod_message = Modlookup::ModMessage.new(twitch.nick.downcase(), twitch.room.delete('#'), twitch.tags.badges.not_nil!.moderator.to_i)
        if mod_message.mod == 1
          test = modstate.find_one(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel }.to_json))
          if test.nil?
            modstate.insert(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel }.to_json))
            if verbose
              puts "Inserted #{mod_message.nick} - #{mod_message.channel}"
            end
          end
        else
          test = modstate.find_one(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel }.to_json))
          if !test.nil?
            modstate.remove(test)
            if verbose
              puts "Removed #{mod_message.nick} - #{mod_message.channel}"
            end
          end
        end
        if track_user_info
          test = usercoll.find_one(BSON.from_json({ "nick": twitch.nick.downcase() }.to_json))
          badges = twitch.tags.badges.not_nil!
          if test.nil?
            usercoll.insert(BSON.from_json({ "nick": twitch.nick.downcase(), "staff": badges.staff, "partner": badges.partner }.to_json))
            if verbose
              puts "Created user #{twitch.nick.downcase()}"
            end
          else
            usercoll.update(BSON.from_json({ "nick": twitch.nick.downcase() }.to_json), 
              BSON.from_json({ "nick": twitch.nick.downcase(), "staff": badges.staff, "partner": badges.partner }.to_json))
            if verbose
              puts "Updated user #{twitch.nick.downcase()}"
            end
          end
        end
      end
      is_banned = bans.find_one(BSON.from_json({ "user": twitch.nick.downcase(), "channel": twitch.room.delete('#') }.to_json))
      if !is_banned.nil?
        bans.remove(is_banned)
        puts "Removed ban on user #{twitch.nick.downcase()} from channel #{twitch.room.delete("#")}"
      end
    when "CLEARCHAT"
      # data: {"command":"CLEARCHAT","room":"","nick":"","target":"#hachubby","body":"mraleksiev","tags":"ban-duration=5;room-id=195166073;target-user-id=464776424;tmi-sent-ts=1569961251823"}
      user = twitch.body
      channel = twitch.target.delete("#")
      timeout_duration = 0
      if user != ""
        if twitch.tags.ban_duration.nil?
          bson = BSON.new()
          bson["user"] = user
          bson["channel"] = channel
          bson["expires"] = Time.utc(9999, 1, 1, 0, 0, 0)
          bans.insert(bson)

          puts "Added ban for user #{user} in channel #{channel}"
        else
          timeout_duration = twitch.tags.ban_duration.not_nil!
          tmi_time = Time.utc
          span = Time::Span.new(0,0,0,timeout_duration)

          bson = BSON.new()
          bson["user"] = user
          bson["channel"] = channel
          bson["expires"] = tmi_time + span
          bans.insert(bson)
          #bans.insert(BSON.from_json({ "user": user, "channel": channel, "expires": tmi_time + span }.to_json))
          puts "Added timeout for user #{user} in channel #{channel}"
        end
      end
    end
  end
  puts "Somehow we got here... exiting."
  exit(0)
end

require "http/client"
require "json"
require "mongo"
require "./modlookup.cr"

# TODO: Write documentation for `Modlookup::Listener`

module Modlookup::Listener
  VERSION = "0.1.0"

  config = Modlookup::Config.from_yaml(File.read("./config.yml"))

  if config.mongouser.nil?
    mongodb = Mongo::Client.new "mongodb://#{config.mongohost}:#{config.mongoport}/#{config.mongodb}"
  else
    mongodb = Mongo::Client.new "mongodb://#{config.mongouser}:#{config.mongopass}@#{config.mongohost}:#{config.mongoport}/#{config.mongodb}"
  end

  db = mongodb[config.mongodb]
  modstate = db["modstate"]
  user = db["user"]

  indexes = modstate.find_indexes()
  has_index = false
  indexes.each do |index|
    if index["name"] == "nick_1_channel_1"
      has_index = true
    end
  end

  if has_index == false
    puts "We are missing an index. Creating an index for nick and channel to speedup processing."
    modstate.create_index(BSON.from_json({ "nick": 1, "channel": 1 }.to_json),Mongo::IndexOpt.new(true,false,"nick_1_channel_1",false,false,0,nil,nil,nil))
  end

  channel = Channel(Modlookup::TwitchMessage | Nil).new

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
                channel.send(twitch)
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

  while twitch = channel.receive
    case twitch.command
    when ""
      if !twitch.tags.badges.nil?
        mod_message = Modlookup::ModMessage.new(twitch.nick.downcase(), twitch.room.delete('#'), twitch.tags.badges.not_nil!.moderator.to_i)
        if mod_message.mod == 1
          test = modstate.find_one(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel }.to_json))
          if test.nil?
            modstate.insert(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel }.to_json))
            puts "inserted #{mod_message.nick} - #{mod_message.channel}"
          end
        else
          test = modstate.find_one(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel }.to_json))
          if !test.nil?
            modstate.remove(test)
            puts "removed #{mod_message.nick} - #{mod_message.channel}"
          end
        end

        test = user.find_one(BSON.from_json({ "nick": twitch.nick.downcase() }.to_json))
        badges = twitch.tags.badges.not_nil!
        if test.nil?
          user.insert(BSON.from_json({ "nick": twitch.nick.downcase(), "staff": badges.staff, "partner": badges.partner }.to_json))
        else
          puts "Updated user #{twitch.nick.downcase()}"
          user.update(BSON.from_json({ "nick": twitch.nick.downcase() }.to_json), 
            BSON.from_json({ "nick": twitch.nick.downcase(), "staff": badges.staff, "partner": badges.partner }.to_json))
        end
      end
    end
  end
  puts "Somehow we got here... exiting."
  exit(0)
end

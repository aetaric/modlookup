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
  collection = db["modstate"]

  channel = Channel(Modlookup::TwitchMessage | Nil).new

  spawn do
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
      end
    end
  end

  while twitch = channel.receive
    case twitch.command
    when ""
      if !twitch.tags.badges.nil?
        mod_message = Modlookup::ModMessage.new(twitch.nick.downcase(), twitch.room.delete('#'), twitch.tags.badges.not_nil!.moderator.to_i)
        if mod_message.mod == 1
          test = collection.find_one(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel, "mod": mod_message.mod }.to_json))
          if test.nil?
            collection.insert(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel, "mod": mod_message.mod }.to_json))
            puts "inserted #{mod_message.nick} - #{mod_message.channel}"
          end
        else
          test = collection.find_one(BSON.from_json({ "nick": mod_message.nick, "channel": mod_message.channel, "mod": mod_message.mod }.to_json))
          if !test.nil?
            collection.remove(test)
            puts "removed #{mod_message.nick} - #{mod_message.channel}"
          end
        end
      end
    end
  end
end

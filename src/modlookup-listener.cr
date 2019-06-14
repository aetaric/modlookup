require "http/client"
require "json"
require "mongo"
require "./modlookup.cr"

# TODO: Write documentation for `Modlookup::Listener`

module Modlookup::Listener
  VERSION = "0.1.0"
  
  struct TwitchMessage
    JSON.mapping(
      command: { type: String },
      room: { type: String },
      nick: { type: String },
      target: { type: String },
      body: { type: String },
      tags: { type: Tags }
    )
  end
  
  struct TagParser
    def initialize(string)
      string = string + ";" # workaround for twitch's tag crap not ending in a ';' but sometimes having a user-type
      @reader = Char::Reader.new(string)
    end
  
    delegate current_char, next_char, has_next?, to: @reader
  
    def parse
      while has_next?
        key = read_value
  
        value = if current_char == ';' || !has_next?
                  next_char if has_next?
                  nil
                else
                  read_value
                end
  
        yield(key, value)
      end
    end
  
    def read_value
      String.build do |str|
        loop do
          case current_char
          when '=', ';'
            next_char
            break
          else
            str << current_char
            next_char
          end
        end
      end
    end
  end

  struct BadgeParser
    def initialize(string)
      string = string + ","
      @reader = Char::Reader.new(string)
    end

    delegate current_char, next_char, has_next?, to: @reader

    def parse
      while has_next?
        key = read_value

        value = if current_char == "," || !has_next?
          next_char if has_next?
          nil
        else
          read_value
        end
        yield(key, value)
      end
    end

    def read_value
      begin
      String.build do |str|
        loop do
          case current_char
          when '/', ','
            next_char
            break
          else
            str << current_char
            next_char
          end
        end
      end
      rescue ex : IndexError
        puts ex
        puts @reader.pos
        puts @reader.string
        #str = 0
      end
    end
  end
  
  struct Tags
    getter id : String
    getter display_name : String
    getter msg_id : String
    getter badges : Badges | Nil
  
    def self.new(parser : JSON::PullParser)
      string = parser.read_string
      id = ""
      display_name = ""
      msg_id = ""
      badges = nil
  
      TagParser.new(string).parse do |key, value|
        case key
        when "id"
          id = value
        when "display-name"
          display_name = value
        when "msg-id"
          msg_id = value
        when "badges"
          if !value.nil?
            badges = Badges.new(value)
          else
            badges = Badges.new("none/1,")
          end 
        else
          # skip
        end
      end
  
      new(id.not_nil!, display_name.not_nil!, msg_id.not_nil!, badges)
    end
  
    def initialize(@id : String, @display_name : String,
                   @msg_id : String, @badges : Badges | Nil)
    end
  end

  struct Badges

    def staff
      @staff
    end

    def moderator
      @moderator
    end

    def broadcaster
      @broadcaster
    end

    def subscriber
      @subscriber
    end
    
    def partner
      @partner
    end

    def vip
      @vip
    end

    def self.new(string : String | Nil)

      staff = 0
      moderator = 0
      broadcaster = 0
      subscriber = 0
      partner = 0
      premium = 0
      vip = 0

      if !string.nil?
        BadgeParser.new(string).parse do |key, value|
          case key
          when "staff"
            staff = value
          when "broadcaster"
            broadcaster = value
          when "moderator"
            moderator = value
          when "subscriber"
            subscriber = value
          when "partner"
            partner = value
          when "premium"
            premium = value
          when "vip"
            vip = value
          when "twitchcon2018"
          when "bits"
          when "sub-gifter"
          when "bits-charity"
          when "bits-leader"
          when "turbo"
          when "none"
          else
            #puts "Got unknown badge #{key} with value #{value}"
          end
        end
      end
      
      new(staff.not_nil!, moderator.not_nil!, broadcaster.not_nil!, subscriber.not_nil!)
    end

    def initialize (@staff : Int32 | String, @moderator : Char | Int32 | String, @broadcaster : Char | Int32 | String, @subscriber : Char | Int32 | String)
    end
  end

  config = Modlookup::Config.from_yaml(File.read("./config.yml"))

  if config.mongouser.nil?
    mongodb = Mongo::Client.new "mongodb://#{config.mongohost}:#{config.mongoport}/#{config.mongodb}"
  else
    mongodb = Mongo::Client.new "mongodb://#{config.mongouser}:#{config.mongopass}@#{config.mongohost}:#{config.mongoport}/#{config.mongodb}"
  end

  db = mongodb[config.mongodb]
  collection = db["modstate"]

  HTTP::Client.get("http://tmi.twitch.tv/firehose?oauth_token=#{config.oauth}") do |response|
    if response.status_code == 200
      while true 
        data = response.body_io.gets
        if !data.nil?
          if /data:/.match data
            json_array = data.split("data: ")
            json_array.delete_at(0)
            twitch = TwitchMessage.from_json(json_array.join(""))

            case twitch.command
            when ""
              if !twitch.tags.badges.nil?
                mod_message = Modlookup::ModMessage.new(twitch.tags.display_name, twitch.room.delete('#'), twitch.tags.badges.not_nil!.moderator.to_i)
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
      end
    end
  end
end
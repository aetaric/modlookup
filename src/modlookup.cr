require "yaml"
require "json"

module Modlookup
    class Config
        YAML.mapping(
          oauth: String,
          mongouser:     { type: String, nilable: true },
          mongopass:     { type: String, nilable: true },
          mongohost:     { type: String, default: "127.0.0.1" },
          mongoport:     { type: String, default: "27017" },
          mongodb:       { type: String, default: "modlookup" }
        )
    end
    struct ModMessage
      include JSON::Serializable

      JSON.mapping(
        nick: { type: String },
        channel: { type: String },
        mod: { type: Int32 }
      )

      def initialize(@nick : String, @channel : String, @mod : String | Int32)
      end
    end
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
      getter ban_duration : Int32 | Nil
      getter tmi_sent_time : Int32
    
      def self.new(parser : JSON::PullParser)
        string = parser.read_string
        id = ""
        display_name = ""
        msg_id = ""
        tmi_sent_time = 0
        ban_duration = nil
        badges = nil
    
        TagParser.new(string).parse do |key, value|
          case key
          when "id"
            id = value
          when "display-name"
            display_name = value
          when "msg-id"
            msg_id = value
          when "tmi-sent-time"
            tmi_sent_time = value.not_nil!.to_i
          when "ban-duration"
            ban_duration = value.not_nil!.to_i
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
    
        new(id.not_nil!, display_name.not_nil!, msg_id.not_nil!, tmi_sent_time.not_nil!, ban_duration, badges)
      end
    
      def initialize(@id : String, @display_name : String,
                     @msg_id : String, @tmi_sent_time : Int32 | String,
                     @ban_duration : Int32 | Nil, @badges : Badges | Nil)
      end
    end
    struct Badges

      def staff
        @staff.to_i
      end
  
      def moderator
        @moderator.to_i
      end
  
      def subscriber
        @subscriber.to_i
      end
      
      def partner
        @partner.to_i
      end
  
      def vip
        @vip.to_i
      end
  
      def self.new(string : String | Nil)
  
        staff = 0
        moderator = 0
        subscriber = 0
        partner = 0
        premium = 0
        vip = 0
  
        if !string.nil?
          BadgeParser.new(string).parse do |key, value|
            case key
            when "staff"
              staff = value
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
            when "broadcaster"
            when "twitchcon2018"
            when "bits"
            when "sub-gifter"
            when "bits-charity"
            when "bits-leader"
            when "turbo"
            when "founder"
            when "glhf-pledge"
            when "hype-train"
            when "none"
            else
              #puts "Got unknown badge #{key} with value #{value}"
            end
          end
        end
        
        new(staff.not_nil!, moderator.not_nil!, subscriber.not_nil!, vip.not_nil!, partner.not_nil!)
      end
  
      def initialize (@staff : Int32 | String, @moderator : Char | Int32 | String, @subscriber : Char | Int32 | String, 
        @vip : Char | Int32 | String, @partner : Char | Int32 | String)
      end
    end
end

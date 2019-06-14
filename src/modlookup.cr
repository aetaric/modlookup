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
end
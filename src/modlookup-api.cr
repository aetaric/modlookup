require "mongo"
require "kemal"
require "./modlookup.cr"

module Modlookup::API

  config = Modlookup::Config.from_yaml(File.read("./config.yml"))

  if config.mongouser.nil?
    mongodb = Mongo::Client.new "mongodb://#{config.mongohost}:#{config.mongoport}/#{config.mongodb}"
  else
    mongodb = Mongo::Client.new "mongodb://#{config.mongouser}:#{config.mongopass}@#{config.mongohost}:#{config.mongoport}/#{config.mongodb}"
  end

  db = mongodb[config.mongodb]

  before_get do |env|
    puts "Setting response content type"
    env.response.headers.add("Access-Control-Allow-Origin", "*")
    env.response.content_type = "application/json"
  end

  get "/api/mod/:nick" do |env|
    nick = env.params.url["nick"]
    a = [] of BSON
    results = db["modstate"].find(BSON.from_json({ "nick": nick }.to_json)).each do |obj|
      a.push(obj)
    end
    a.to_s + "\n"
  end

  get "/api/user/:nick" do |env|
    nick = env.params.url["nick"]
    db["user"].find_one(BSON.from_json({ "nick": nick }.to_json)).to_json + "\n"
  end

  Kemal.run
end
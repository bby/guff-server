require 'rubygems' # not necessary with ruby 1.9 but included for completeness
require 'sinatra'
require "sinatra/reloader" if development?
require 'data_mapper'
require 'json'
require_relative 'cloud_message_client.rb'

configure :development do
  enable :logging, :dump_errors, :raise_errors
  DataMapper.setup(:default, 'mysql://guff:guff@localhost/guff')
end

configure :production do
  enable :logging, :dump_errors, :raise_errors
  DataMapper.setup :default, ENV['DATABASE_URL']
  set :protection, :except => :json_csrf
end

class Message
  include DataMapper::Resource
  
  property :id, Serial
  property :ip, String
  property :message, String, :length => 141
  property :accuracy, String
  property :latitude, Float
  property :longitude, Float
  property :created_at, DateTime
  property :updated_at, DateTime
  property :token_id, String, :length => 250
end

class Location
  include DataMapper::Resource

  property :id, Serial
  property :token_id, String, :length => 250
  property :accuracy, String
  property :latitude, Float
  property :longitude, Float
  property :created_at, DateTime
  property :updated_at, DateTime
end

DataMapper.finalize
DataMapper.auto_upgrade!

get '/messages/:latitude/:longitude' do
  puts "message called"
  expiry = Time.now - 7200
  #old mysql query
  #puts "query: SELECT ((acos( cos( radians(#{params[:latitude]}) ) * cos( radians( a.latitude ) ) * cos( radians( a.longitude ) - radians(#{params[:longitude]}) ) + sin( radians(#{params[:latitude]}) ) * sin( radians( a.latitude ) ) )) * 6371) as distance, a.* FROM messages a WHERE created_at > '#{expiry.strftime('%Y-%m-%d %H:%M:%S')}' HAVING distance < 0.2"
  puts "select id, distance, message, latitude, longitude, created_at from ( select id, message, latitude, longitude, created_at, ( 6371 * acos( cos( radians(#{params[:latitude]}) ) * cos( radians( a.latitude ) ) * cos( radians( a.longitude ) - radians(#{params[:longitude]}) ) + sin( radians(#{params[:latitude]}) ) * sin( radians( a.latitude ) ) ) ) as distance, a.* from messages a ) as dt where distance < 0.2 and created_at > '#{expiry.strftime('%Y-%m-%d %H:%M:%S')}' order by distance asc"
  @messages = repository(:default).adapter.select("select id, distance, message, latitude, longitude, created_at from ( select ( 6371 * acos( cos( radians(#{params[:latitude]}) ) * cos( radians( a.latitude ) ) * cos( radians( a.longitude ) - radians(#{params[:longitude]}) ) + sin( radians(#{params[:latitude]}) ) * sin( radians( a.latitude ) ) ) ) as distance, a.* from messages a ) as dt where distance < 0.2 and created_at > '#{expiry.strftime('%Y-%m-%d %H:%M:%S')}' order by created_at desc")
  @messages_hash = @messages.map { |row| Hash[row.members.zip(row.values)] }
  
  response['Access-Control-Allow-Origin'] = "*"
  content_type :json
  @messages_hash.to_json
end

post '/send' do
  response['Access-Control-Allow-Origin'] = "*"
  @message = Message.create(
    :message      => params[:message],
    :accuracy       => params[:accuracy],
    :latitude       => params[:latitude],
    :longitude       => params[:longitude],
    :token_id       => params[:tokenID],
    :created_at => Time.now
  )
  if @message.save
    content_type :json
    { :success_message => 'Message posted' }.to_json
  end
  puts "params: " + params.inspect

  # Notify other people
  @location = Location.first(:token_id => params[:tokenID])
  if @location.nil?
    #Create
    @location = Location.create(
      :latitude       => params[:latitude],
      :longitude       => params[:longitude],
      :token_id       => params[:tokenID],
      :created_at => Time.now,
      :updated_at => Time.now
    )
  else
    #Update
    @location.latitude = params[:latitude]
    @location.longitude = params[:longitude]
    @location.updated_at = Time.now
  end 
  @location.save

  # Now find all nearyby peeps and shout out to them
  expiry = Time.now - 7200
  @peeps = repository(:default).adapter.select("select token_id from ( select ( 6371 * acos( cos( radians(#{params[:latitude]}) ) * cos( radians( a.latitude ) ) * cos( radians( a.longitude ) - radians(#{params[:longitude]}) ) + sin( radians(#{params[:latitude]}) ) * sin( radians( a.latitude ) ) ) ) as distance, a.* from locations a ) as dt where distance < 0.2 and created_at > '#{expiry.strftime('%Y-%m-%d %H:%M:%S')}' and token_id!='#{params[:tokenID]}' order by created_at desc")

  puts "Number of peeps to push to #{@peeps.length}"



  CloudMessageClient::sendMessage(@peeps, params[:message])

end
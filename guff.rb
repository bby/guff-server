require 'rubygems' # not necessary with ruby 1.9 but included for completeness
require 'sinatra'
require "sinatra/reloader" if development?
require 'data_mapper'
require 'json'

configure :development do
  enable :logging, :dump_errors, :raise_errors
  DataMapper.setup(:default, 'mysql://guff:guff@127.0.0.1/guff')
end

configure :production do
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
end

DataMapper.finalize
DataMapper.auto_upgrade!

get '/messages/:latitude/:longitude' do
  puts "message called"
  expiry = Time.now - 7200
  #old mysql query
  #puts "query: SELECT ((acos( cos( radians(#{params[:latitude]}) ) * cos( radians( a.latitude ) ) * cos( radians( a.longitude ) - radians(#{params[:longitude]}) ) + sin( radians(#{params[:latitude]}) ) * sin( radians( a.latitude ) ) )) * 6371) as distance, a.* FROM messages a WHERE created_at > '#{expiry.strftime('%Y-%m-%d %H:%M:%S')}' HAVING distance < 0.2"
  puts "select id, distance, message, latitude, longitude, created_at from ( select id, message, latitude, longitude, created_at, ( 6371 * acos( cos( radians(#{params[:latitude]}) ) * cos( radians( a.latitude ) ) * cos( radians( a.longitude ) - radians(#{params[:longitude]}) ) + sin( radians(#{params[:latitude]}) ) * sin( radians( a.latitude ) ) ) ) as distance, a.* from messages a ) as dt where distance < 0.2 and created_at > '#{expiry.strftime('%Y-%m-%d %H:%M:%S')}' order by distance asc"
  @messages = repository(:default).adapter.select("select id, distance, message, latitude, longitude, created_at from ( select ( 6371 * acos( cos( radians(51.5284089) ) * cos( radians( a.latitude ) ) * cos( radians( a.longitude ) - radians(-0.0371275) ) + sin( radians(51.5284089) ) * sin( radians( a.latitude ) ) ) ) as distance, a.* from messages a ) as dt where distance < 0.2 and created_at > '2012-07-08 08:07:58' order by created_at desc")
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
    
    :created_at => Time.now
  )
  if @message.save
    content_type :json
    { :success_message => 'Message posted' }.to_json
  end
  puts "params: " + params.inspect
end
#!/usr/bin/env ruby

require 'date'
require 'rubygems'
require 'oauth'
require 'yaml'
require 'net/http'
require 'json'

module TelldusLive
  SERVICE_OPTIONS = { 
    :site => "http://api.telldus.com",
    :request_token_path => "/oauth/requestToken",
    :authorize_path => "/oauth/authorize",
    :access_token_path => "/oauth/accessToken"
  }

  class Client
    def initialize(auth)
      @consumer = OAuth::Consumer.new(
        auth['consumer_key'],
        auth['consumer_secret'],
        SERVICE_OPTIONS
      )
      @access_token = OAuth::AccessToken.new(
        @consumer,
        auth['token'],
        auth['token_secret']
      )
    end

    def device(device_id)
      Device.new self, request("/device/info", :id => device_id)
    end

    def devices
      request("/devices/list")['device'].map do |device_spec|
        Device.new self, device_spec
      end
    end

    def sensor(sensor_id)
      Sensor.new self, request("/sensor/info", :id => sensor_id)
    end

    def sensors
      request("/sensors/list")['sensor'].map do |sensor_spec|
        Sensor.new self, sensor_spec
      end
    end

    def request(function, arguments={})
      query = arguments.map{ |k,v| "#{k.to_s}=#{v}" }.join("&")
      uri = "/json#{function}"
      uri += "?#{query}" unless query.empty?

      response = @access_token.get(uri)
      raise "Received #{response.code} #{response.message} from server" unless Net::HTTPSuccess === response

      response = JSON.parse(response.body)
      raise "Received error message from server: #{response['error']}" if response.has_key? 'error'

      response
    end
  end

  class Device
    attr_reader :id
    attr_reader :name
    attr_reader :level

    def initialize(client, spec)
      @client = client
      @id = spec['id']
      @name = spec['name']
      @level = ((spec['statevalue'].to_i / 255.0) * 100).floor
    end

    def level=(value)
      response = @client.request(
        "/device/dim",
        :id => id,
        :level => [[((value/100.0)*255).floor, 255].min, 0].max
      )

      if response['status'] == "success"
        @level = value
      else
        puts %[Level change on "#{@name}" did not succeed]
      end
    end
  end

  class Sensor
    attr_reader :id
    attr_reader :name
    attr_reader :last_update

    def initialize(client, spec)
      @client = client
      @id = spec['id']
      @name = spec['name']
      @data = spec['data']
      @last_update = Time.at(spec['lastUpdated'])
    end

    def data
      @data ||= retrieve_data
    end

    private

    def retrieve_data
      @client.request("/sensor/info", :id => @id)['data']
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  auth = YAML.load_file(File.join([File.dirname(__FILE__), 'auth.yml']))
  command = ARGV.shift

  case command
  when "devices"
    client = TelldusLive::Client.new(auth)
    client.devices.each do |device|
      puts "#{device.id} #{device.name}"
    end

  when "dim"
    raise "Not enough arguments. Expected 2 arguments." if ARGV.length < 2

    client = TelldusLive::Client.new(auth)
    device = client.device(ARGV.shift)
    level = ARGV.shift

    raise "Could not parse new level: #{level}" unless level.match(/^([+-]?)(\d+)$/)
    
    sign = $1
    amount = $2.to_i

    case sign
    when ""
      device.level = amount
    when "+"
      device.level += amount
    when "-"
      device.level -= amount
    else
      raise "This shouldn't happen"
    end
        
  when "sensors"
    client = TelldusLive::Client.new(auth)
    client.sensors.each do |sensor|
      puts "#{sensor.id} #{sensor.name}"
    end

  when "sensor"
    client = TelldusLive::Client.new(auth)
    sensor = client.sensor(ARGV.shift)

    puts "#{sensor.id} #{sensor.name}"

    sensor.data.each do |datum|
      puts "  #{datum['name']}: #{datum['value']}"
    end

  else
    puts "Usage:"
    puts "  #{$PROGRAM_NAME} command [argument]..."

    exit 1
  end
end


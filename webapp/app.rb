#!/usr/bin/env ruby

require 'sinatra'
require 'rack/cache'

require_relative '../config'
require_relative '../lib/slcc_calendar'

def event2hash(e)
  hash = {}
  hash[:summary] = e.summary
  hash[:description] = e.description
  hash[:start_date] = e.start.date_time.to_s
  hash[:end_date] = e.end.date_time.to_s
  hash[:live_url] = e.extended_properties.shared["live_url"] if e.extended_properties && e.extended_properties.shared && e.extended_properties.shared["live_url"]
  hash[:thumbnail_url] = e.extended_properties.shared["thumbnail_url"] if e.extended_properties && e.extended_properties.shared && e.extended_properties.shared["thumbnail_url"]
  hash[:live_ended] = e.extended_properties.shared["live_ended"] if e.extended_properties && e.extended_properties.shared && e.extended_properties.shared["live_ended"]
  hash[:on_live] = e.extended_properties.shared["on_live"] if e.extended_properties && e.extended_properties.shared && e.extended_properties.shared["on_live"]
  if hash[:live_ended].nil?
    if e.description[-2,2] == '##'
      hash[:live_ended] = "true"
      hash[:on_live] = "false"
    else
      hash[:live_ended] = "false"
    end
  end

  hash
end

use Rack::Cache

get '/' do
  content_type :json
  cache_control :public, :max_age => 60

  puts 'retrieving events'
  calendar = SLCCalendar::Calendar.new
  current_events = calendar.events(1, 120)
  events = []
  current_events.each{|e|
    events << event2hash(e)
  }

  return events.to_json
end

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
  hash[:thumbnail_url] = e.extended_properties.shared["thumbnail_url"] if e.extended_properties && e.extended_properties.shared && e.extended_properties.shared["thumbnail_url"]

  hash
end

use Rack::Cache

get '/' do
  cache_control :public, :max_age => 60

  puts 'retrieving events'
  calendar = SLCCalendar::Calendar.new
  current_events = calendar.events
  events = []
  current_events.each{|e|
    events << event2hash(e)
  }

  return events.to_json
end

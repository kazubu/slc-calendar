#!/usr/bin/env ruby
# frozen_string_literal: true

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
  if e&.extended_properties&.shared
    hash[:tweet_url] = e.extended_properties.shared['tweet_url'] if e.extended_properties.shared['tweet_url']
    hash[:channel_name] = e.extended_properties.shared['channel_name'] if e.extended_properties.shared['channel_name']
    hash[:channel_id] = e.extended_properties.shared['channel_id'] if e.extended_properties.shared['channel_id']
    hash[:video_title] = e.extended_properties.shared['video_title'] if e.extended_properties.shared['video_title']
    hash[:live_url] = e.extended_properties.shared['live_url'] if e.extended_properties.shared['live_url']
    hash[:thumbnail_url] = e.extended_properties.shared['thumbnail_url'] if e.extended_properties.shared['thumbnail_url']
    hash[:live_ended] = e.extended_properties.shared['live_ended'] if e.extended_properties.shared['live_ended']
    hash[:on_live] = e.extended_properties.shared['on_live'] if e.extended_properties.shared['on_live']
  end

  if hash[:live_ended].nil?
    if e.description[-2, 2] == '##'
      hash[:live_ended] = 'true'
      hash[:on_live] = 'false'
    else
      hash[:live_ended] = 'false'
    end
  end

  hash
end

use Rack::Cache

get '/' do
  content_type :json
  cache_control :public, max_age: 60

  puts 'retrieving events'
  calendar = SLCCalendar::Calendar.new
  current_events = calendar.events(1, 120)
  events = []
  updated_at = nil
  current_events.each do |e|
    events << event2hash(e)
    updated_at = e.updated if updated_at.nil? || updated_at < e.updated
  end

  {
    events: events,
    updated_at: updated_at.to_s
  }.to_json
end

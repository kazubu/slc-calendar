#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logger'
require './lib/slcc_schedule_collector'
require './config'

$logger = Logger.new($stdout)

def extract_youtube_channel_id url
  if url.index('youtube.com/channel/')
    return url.split('/channel/')[1].split('?')[0]
  end
  url
end

def extract_youtube_channel_urls urls
  return "" if urls.nil?
  return "" if urls.length == 0
  urls.each{|x|
    u = x[:expanded_url]
    return extract_youtube_channel_id(u) if u.index('youtube.com/channel/') or u.index('youtube.com/@') or u.index('youtube.com/c/')
  }
  ""
end

collector = SLCCalendar::ScheduleCollector.new(
  twitter_consumer_key: TWITTER_CONSUMER_KEY,
  twitter_consumer_secret: TWITTER_CONSUMER_SECRET,
  twitter_bearer_token: TWITTER_BEARER_TOKEN,
  youtube_data_api_key: YOUTUBE_DATA_API_KEY
)

res = []
TWITTER_LISTS.each do |x|
  user_id = x[0]
  list_id = x[1]
  collector.get_list_members(user_id, list_id).each{|x|
    name = x[:name]
    screen_name = x[:screen_name]
    youtube = ""

    urls = []
    urls += x[:attrs][:entities][:url][:urls] if x[:attrs][:entities] && x[:attrs][:entities] [:url]
    urls += x[:attrs][:entities][:description][:urls] if x[:attrs][:entities] && x[:attrs][:entities][:description]
    youtube = extract_youtube_channel_urls urls

    res << "#{name},#{screen_name},#{youtube}"
  }
end

puts res


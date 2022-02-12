#!/usr/bin/env ruby
# frozen_string_literal: true

require 'twitter'
require 'nkf'

require_relative './slcc_youtube'

module SLCCalendar
  class Schedule
    attr_reader :video, :tweet

    def initialize(video:, tweet:)
      @video = video
      @tweet = tweet
    end
  end

  class ScheduleCollector
    module Utils
      def expand_url(url)
        begin
          response = Net::HTTP.get_response(URI.parse(url))
        rescue StandardError
          return url
        end
        case response
        when Net::HTTPRedirection
          expand_url(response['location'])
        else
          url.to_s
        end
      end

      module_function :expand_url
    end

    attr_reader :latest_tweet_id

    def initialize(twitter_consumer_key:, twitter_consumer_secret:, twitter_bearer_token:, youtube_data_api_key:)
      @latest_tweet_id = nil

      @twitter_consumer_key = twitter_consumer_key
      @twitter_consumer_secret = twitter_consumer_secret
      @twitter_bearer_token = twitter_bearer_token
      @youtube_data_api_key = youtube_data_api_key
    end

    def get_schedules(twitter_id, list_id, since_id: nil)
      announces, latest_id = collect_announces(twitter_id, list_id, since_id: since_id)
      @latest_tweet_id = latest_id

      schedules = []
      video_ids = []
      announces.each do |a|
        video_ids << a[:video_id]
      end

      yt = YouTube.new(api_key: @youtube_data_api_key)
      videos = yt.get_videos(video_ids)

      announces.each do |a|
        video = videos.find{|v| v.video_id == a[:video_id] }
        next if video.nil? || !video.upcoming_stream?

        schedules << Schedule.new(video: video, tweet: a[:tweet])
      end

      schedules
    end

    private

    def extract_youtube_video_ids(tweet)
      youtube_url_lists = ['youtu.be', 'youtube.com']
      ids = []

      return false if tweet.urls.count <= 0

      tweet.urls.each do |u|
        youtube_url_lists.each do |y|
          if u.expanded_url.to_s.index(y)
            e_url = Utils.expand_url(u.expanded_url.to_s)
            ids << YouTube::Utils.url_to_video_id(e_url) if e_url.index('watch')
          end
        end
      end

      return ids if ids.length > 0

      false
    end

    def collect_announces(twitter_user, list_id, since_id: nil)
      client = Twitter::REST::Client.new do |config|
        config.consumer_key = @twitter_consumer_key
        config.consumer_secret = @twitter_consumer_secret
        config.bearer_token = @twitter_bearer_token
      end

      announces = []

      tweets_count = 0

      last_id = nil
      option = { count: 1000, tweet_mode: 'extended' }
      option[:since_id] = since_id if since_id

      latest_id = nil

      client.list_timeline(twitter_user, list_id, option).each do |tweet|
        tweets_count += 1
        last_id = tweet.id
        latest_id = tweet.id if latest_id.nil? || latest_id < tweet.id
        text = NKF.nkf('-w -Z4', tweet.full_text)

        next unless tweet.in_reply_to_status_id.nil? # Skip a reply to any tweet
        next unless tweet.retweeted_status.nil? # Skip RT

        video_ids = extract_youtube_video_ids(tweet)
        next unless video_ids

        tweet_announces = []

        video_ids.each do |v|
          tweet_announces << {
            tweet: tweet,
            video_id: v
          }
        end

        # only recent tweet for same video url
        tweet_announces.each do |aa|
          next if aa[:video_id] && (announces.select{|a| a[:video_id] && a[:video_id] == aa[:video_id] }.length > 0)

          announces << aa
        end
      end

      puts "Collected tweets: #{tweets_count}"
      puts "Collected announces: #{announces.length}"
      puts "Latest id: #{latest_id}"

      return announces, latest_id
    end
  end
end

#!/usr/bin/env ruby
# frozen_string_literal: true

require 'twitter'

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

    def get_schedules(twitter_id, list_id, since_id: nil, include_ended: false)
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
        next if video.nil? || !video.live? || (!include_ended && !video.upcoming_stream?)

        schedules << Schedule.new(video: video, tweet: a[:tweet])
      end

      schedules
    end

    def extract_youtube_video_ids(tweet)
      youtube_url_lists = ['youtu.be', 'youtube.com']
      ids = []

      tweet.urls.each do |u|
        youtube_url_lists.each do |y|
          if u.expanded_url.to_s.index(y)
            e_url = Utils.expand_url(u.expanded_url.to_s)
            ids << YouTube::Utils.url_to_video_id(e_url) if e_url.index('watch')
          end
        end
      end

      ids
    end

    def get_collabo_video_ids(tweet)
      video_ids = []
      if tweet.quoted_tweet?
        new_tweet = tweet.quoted_tweet
        if tweet.full_text.index('コラボ') || tweet.full_text.index('こらぼ')
          $logger.info "Collaboration is detected in tweet: #{tweet.id}. Checking quoted tweet: #{new_tweet.id}."
          video_ids = extract_youtube_video_ids(new_tweet)
        elsif new_tweet.full_text.index(tweet.user.screen_name)
          $logger.info "Quoted tweet includes the screen name of original tweet user. Original tweet: #{tweet.id}. Checking quoted tweet: #{new_tweet.id}."
          video_ids = extract_youtube_video_ids(new_tweet)
        end
      end
      video_ids
    end

    private

    def collect_announces(twitter_user, list_id, since_id: nil)
      client = Twitter::REST::Client.new do |config|
        config.consumer_key = @twitter_consumer_key
        config.consumer_secret = @twitter_consumer_secret
        config.bearer_token = @twitter_bearer_token
      end

      announces = []

      tweets_count = 0

      option = { count: 1000, tweet_mode: 'extended' }
      option[:since_id] = since_id if since_id

      latest_id = nil

      client.list_timeline(twitter_user, list_id, option).each do |tweet|
        tweets_count += 1
        latest_id = tweet.id if latest_id.nil? || latest_id < tweet.id

        next if !tweet.in_reply_to_status_id.nil? && tweet.in_reply_to_user_id != tweet.user.id # Skip a reply to others tweet
        next unless tweet.retweeted_status.nil? # Skip RT

        video_ids = extract_youtube_video_ids(tweet)
        video_ids = get_collabo_video_ids(tweet) if video_ids.empty?

        next if video_ids.empty?

        tweet_announces = []

        video_ids.each do |v|
          tweet_announces << {
            tweet: tweet,
            video_id: v
          }
        end

        # only recent tweet for same video url
        tweet_announces.each do |aa|
          next if aa[:video_id] &&
                  !announces.select{|a| a[:video_id] && a[:video_id] == aa[:video_id] }.empty?

          announces << aa
        end
      end

      $logger.info "Collected tweets: #{tweets_count}"
      $logger.info "Collected announces: #{announces.length}"
      $logger.info "Latest id: #{latest_id}"

      return announces, latest_id
    end
  end
end

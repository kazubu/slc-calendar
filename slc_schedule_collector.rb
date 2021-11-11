#!/usr/bin/env ruby
require 'twitter'
require 'pp'
require 'net/http'
require 'uri'
require 'json'
require 'nkf'

require_relative './slc_utils'
require_relative './config'

module SLCCalendar
  class ScheduleCollector
    attr_reader :latest_tweet_id

    def initialize
      @latest_tweet_id = nil
    end

    def get_schedules(twitter_id, list_id, since_id: nil)
      announces, latest_id = collect_announces(twitter_id, list_id, since_id: since_id)
      @latest_tweet_id = latest_id
      announce_parser(announces)
    end

    private

    def is_include_youtube_live(tweet)
      youtube_url_lists = [ 'youtu.be', 'youtube.com' ]
      url = nil

      return false if tweet.urls.count <= 0
      tweet.urls.each{|u|
        youtube_url_lists.each{|y|
          if u.expanded_url.to_s.index(y)
            url = u.expanded_url.to_s
            break
          end
        }
      }

      return false if url.nil?

      e_url = Utils.expand_url(url).to_s

      if e_url.index('watch')
        video_url, date, ch_name, title = Utils.is_upcoming_stream(e_url)
        if video_url
          return video_url, date, ch_name, title
        end
      end

      return false
    end

    def collect_announces(twitter_user, list_id, since_id: nil)
      client = Twitter::REST::Client.new do|config|
        config.consumer_key = TWITTER_CONSUMER_KEY
        config.consumer_secret = TWITTER_CONSUMER_SECRET
        config.bearer_token = TWITTER_BEARER_TOKEN
      end

      announce_lists = []

      tweets_count = 0

      last_id = nil
      option = {count: 1000, tweet_mode: 'extended'}
      option[:since_id] = since_id if since_id

      latest_id = nil

      client.list_timeline(twitter_user, list_id, option).each{|x|
        tweets_count += 1
        last_id = x.id
        latest_id = x.id if latest_id.nil? || latest_id < x.id
        skip_unless_upcoming_live = false
        text = NKF.nkf('-w -Z4', x.full_text)
        next if !x.in_reply_to_status_id.nil? # Skip a reply to any tweet
        next if !x.retweeted_status.nil? # Skip RT

        if (
            text.index('配信') &&
            (text.index('配信します') || text.index('告知'))
        )
          # pass
        else
          skip_unless_upcoming_live = true
        end

        live = is_include_youtube_live(x)
        next if (skip_unless_upcoming_live && !live)

        d = { user: x.user.screen_name,
              uri: x.uri.to_s,
              text: x.full_text,
              live_info: live
        }

        next if announce_lists.select{|a| a[:live_info] && a[:live_info][0] == d[:live_info][0]}.length > 0 if live
        announce_lists << d
      }

      puts "Collected tweets: #{tweets_count}"
      puts "Collected announces: #{announce_lists.length}"
      puts "Latest id: #{latest_id}"

      return announce_lists, latest_id
    end

    def announce_parser(announces)
      schedules = []

      announces.each{|a|
        if a[:live_info]
          schedules << {
            user: a[:user],
            date: a[:live_info][1].strftime('%Y/%m/%d'),
            time: a[:live_info][1].strftime('%H:%M'),
            channel_title: a[:live_info][2],
            title: a[:live_info][3],
            tweet_url: a[:uri],
            video_url: a[:live_info][0]
          }
        else
          # 告知っぽいけどYouTube URLがない
        end
      }

      schedules
    end
  end
end

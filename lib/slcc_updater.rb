#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config'
require_relative './slcc_schedule_collector'
require_relative './slcc_calendar'

module SLCCalendar
  class Updater
    def initialize
      @youtube = YouTube.new(api_key: YOUTUBE_DATA_API_KEY)
    end

    def update_by_tweets
      create_count = 0
      update_count = 0
      skip_count = 0

      collector = SLCCalendar::ScheduleCollector.new(
        twitter_consumer_key: TWITTER_CONSUMER_KEY,
        twitter_consumer_secret: TWITTER_CONSUMER_SECRET,
        twitter_bearer_token: TWITTER_BEARER_TOKEN,
        youtube_data_api_key: YOUTUBE_DATA_API_KEY
      )
      calendar = SLCCalendar::Calendar.new

      latest_id_list = {}
      begin
        latest_id_list = JSON.parse(File.read(TWITTER_LATEST_ID_STORE)) if File.exist?(TWITTER_LATEST_ID_STORE)
      rescue StandardError
        latest_id_list = {}
      end

      schedules = []
      TWITTER_LISTS.each do |x|
        user_id = x[0]
        list_id = x[1]
        schedules += if latest_id_list[list_id.to_s]
                       collector.get_schedules(user_id, list_id, since_id: latest_id_list[list_id.to_s].to_i)
                     else
                       collector.get_schedules(user_id, list_id)
                     end
        latest_id_list[list_id.to_s] = collector.latest_tweet_id if collector.latest_tweet_id
      end

      current_events = calendar.events

      schedules.each do |sc|
        event_id = nil
        current_events.each do |ev|
          event_id = ev.id if ev.description.index(sc.video.video_url)
        end

        if event_id
          # event is already exists
          ev = current_events.select{|x| x.id == event_id }[0]
          nev = calendar.gen_event(sc)
          if calendar.compare_events(ev, nev)
            skip_count += 1
            calendar.puts_event(ev, message: 'SKIP')
          else
            update_count += 1
            calendar.puts_event(calendar.update(event_id, sc), message: 'UPDATE')
          end
        else
          # no existing events
          create_count += 1
          calendar.puts_event(calendar.create(sc), message: 'CREATE')
        end
      end

      begin
        File.write(TWITTER_LATEST_ID_STORE, latest_id_list.to_json)
      rescue StandardError
        puts 'Failed to write latest id list'
      end

      puts "#{create_count} created; #{update_count} updated; #{skip_count} skipped;"
    end

    # 配信URLをチェックして時間だけアップデートする
    def update_registered_events
      update_count = 0
      skip_count = 0
      ended_count = 0

      calendar = SLCCalendar::Calendar.new

      current_events = calendar.events(2, 120)

      events = []
      current_events.each do |e|
        if calendar.is_live_ended(e)
          ended_count += 1
          next
        end

        next unless e.description.index('/watch?v=')

        video_id = e.description.split('/watch?v=')[1].split('"')[0]

        tweet_url = nil
        tweet_url = "https://twitter.com/#{e.description.split('twitter.com/')[1].split('"')[0]}" if e.description.index('twitter.com/')

        events << { event: e, video_id: video_id, tweet_url: tweet_url }
      end

      videos = @youtube.get_videos(events.map{|x| x[:video_id] })

      events.each do |e|
        video = videos.find{|x| x.video_id == e[:video_id] }
        tweet_url = e[:tweet_url]

        sc = Schedule.new(video: video, tweet: tweet_url)

        # live is finished after last execution
        if video.nil?
          # need to update existing event if live is deleted due to can't generate new event without video detail.
          e[:event].description = "#{e[:event].description}##"
          calendar.puts_event(calendar.update_event(e[:event]), message: 'ENDED')
          ended_count += 1
          next
        elsif !video.upcoming_stream?
          # live is finished. generate new event
          calendar.puts_event(calendar.update(e[:event].id, sc), message: 'ENDED')
          ended_count += 1
          next
        end

        # generate new event for compare
        nev = calendar.gen_event(sc)
        if calendar.compare_events(e[:event], nev)
          skip_count += 1
          calendar.puts_event(e[:event], message: 'SKIP')
        else
          update_count += 1
          calendar.puts_event(calendar.update(e[:event].id, sc), message: 'UPDATE')
        end
      end

      puts "#{update_count} updated; #{skip_count} skipped; #{ended_count} ended;"
    end

    def force_register(video_id)
      c = SLCCalendar::Calendar.new

      current_events = c.events(10, 30)

      if current_events.find{|x| x.description.index(video_id) }
        puts 'This video is exists.'
        return false
      end

      video = @youtube.get_videos(video_id)[0]
      unless video
        puts 'Invalid video id?'
        return false
      end

      sc = Schedule.new(video: video, tweet: nil)

      c.puts_event(c.create(sc), message: 'CREATE')
    end
  end
end

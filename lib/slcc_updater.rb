#!/usr/bin/env ruby

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

      ssc = SLCCalendar::ScheduleCollector.new(
        twitter_consumer_key: TWITTER_CONSUMER_KEY,
        twitter_consumer_secret: TWITTER_CONSUMER_SECRET,
        twitter_bearer_token: TWITTER_BEARER_TOKEN,
        youtube_data_api_key: YOUTUBE_DATA_API_KEY
      )
      c = SLCCalendar::Calendar.new

      latest_id_list = {}
      begin
        if File.exist?(TWITTER_LATEST_ID_STORE)
          latest_id_list = JSON.parse(File.read(TWITTER_LATEST_ID_STORE))
        end
      rescue
        latest_id_list = {}
      end

      s = []
      TWITTER_LISTS.each{|x|
        user_id = x[0]
        list_id = x[1]
        if latest_id_list[list_id.to_s]
          s += ssc.get_schedules(user_id, list_id, since_id: latest_id_list[list_id.to_s].to_i)
        else
          s += ssc.get_schedules(user_id, list_id)
        end
        latest_id_list[list_id.to_s] = ssc.latest_tweet_id if ssc.latest_tweet_id
      }

      begin
        File.write(TWITTER_LATEST_ID_STORE, latest_id_list.to_json)
      rescue
        puts "Failed to write latest id list"
      end

      current_events = c.events

      s.each{|sc|
        event_id = nil
        current_events.each{|ev|
          event_id = ev.id if ev.description.index(sc.video.video_url)
        }

        if event_id
          # event is already exists
          ev = current_events.select{|x| x.id == event_id}[0]
          nev = c.gen_event(sc)
          if ev.summary == nev.summary && ev.description == nev.description && ev.start.date_time == nev.start.date_time && ev.end.date_time == nev.end.date_time
            puts "## no update; skip"
            skip_count += 1
            c.puts_event(ev)
          else
            puts "## update"
            update_count += 1
            c.puts_event c.update(event_id, sc)
          end
        else
          # no existing events
          puts "## create"
          create_count += 1
          c.puts_event c.create(sc)
        end
      }

      puts "#{create_count} created; #{update_count} updated; #{skip_count} skipped;"
    end

    # 配信URLをチェックして時間だけアップデートする
    def update_registered_events
      update_count = 0
      skip_count = 0
      ended_count = 0

      c = SLCCalendar::Calendar.new

      current_events = c.events(2, 120)

      events = []
      video_ids = []
      current_events.each{|e|
        if e.description[-2,2] == '##'
          ended_count += 1
          next
        end

        next unless e.description.index('/watch?v=')
        video_id = e.description.split('/watch?v=')[1].split('"')[0]

        tweet_url = nil
        if e.description.index('twitter.com/')
          tweet_url = 'https://twitter.com/' + e.description.split('twitter.com/')[1].split('"')[0]
        end

        events << {event: e, video_id: video_id, tweet_url: tweet_url}
        video_ids << video_id
      }

      videos = @youtube.get_videos(video_ids)

      events.each{|e|
        video = videos.find{|x| x.video_id == e[:video_id] }
        tweet_url = e[:tweet_url]

        if video.nil? || !video.is_upcoming_stream
          puts '## marking as ended'
          e[:event].description += "##"
          c.puts_event c.update_event(e[:event])
          ended_count += 1
          next
        end

        sc = Schedule.new(video: video, tweet: tweet_url)
        nev = c.gen_event(sc)

        if e[:event].summary == nev.summary && e[:event].description == nev.description && e[:event].start.date_time == nev.start.date_time && e[:event].end.date_time == nev.end.date_time
          puts "## no update; skip"
          skip_count += 1
          c.puts_event(e[:event])
        else
          puts "## update"
          update_count += 1
          c.puts_event c.update(e[:event].id, sc)
        end
      }

      puts "#{update_count} updated; #{skip_count} skipped; #{ended_count} ended;"
    end

    def force_register(video_id)
      c = SLCCalendar::Calendar.new

      current_events = c.events(10,30)

      if current_events.find{|x| x.description.index(video_id)}
        puts 'This video is exists.'
        return false
      end

      video = @youtube.get_videos(video_id)[0]
      unless video
        puts 'Invalid video id?'
        return false
      end

      sc = Schedule.new(video: video, tweet: nil)

      c.puts_event c.create(sc)
    end
  end
end

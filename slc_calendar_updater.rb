#!/usr/bin/env ruby

require_relative './slc_schedule_collector'
require_relative './slc_calendar'

module SLCCalendar
  class CalendarUpdater
    def initialize
    end

    def update_by_tweets
      create_count = 0
      update_count = 0
      skip_count = 0

      ssc = SLCCalendar::ScheduleCollector.new
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
        latest_id_list[list_id.to_s] = ssc.latest_tweet_id
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
          event_id = ev.id if ev.description.index(sc[:video_url]) if sc[:video_url]
          event_id = ev.id if ev.description.index(sc[:tweet_url]) if sc[:tweet_url] if event_id.nil?
        }

        if event_id
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

        detail = Utils.is_upcoming_stream(video_id)
        unless detail
          puts '## marking as ended'
          e.description += "##"
          c.puts_event c.update_event(e)
          ended_count += 1
          next
        end

        sc = {
          date: detail[1].strftime('%Y/%m/%d'),
          time: detail[1].strftime('%H:%M'),
          channel_title: detail[2],
          title: detail[3],
          video_url: detail[0],
          tweet_url: tweet_url
        }

        nev = c.gen_event(sc)

        if e.summary == nev.summary && e.description == nev.description && e.start.date_time == nev.start.date_time && e.end.date_time == nev.end.date_time
          puts "## no update; skip"
          skip_count += 1
          c.puts_event(e)
        else
          puts "## update"
          update_count += 1
          c.puts_event c.update(e.id, sc)
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

      detail = Utils.is_upcoming_stream(video_id, force: true)
      unless detail
        puts 'Invalid video id?'
        return false
      end

      sc = {
        date: detail[1].strftime('%Y/%m/%d'),
        time: detail[1].strftime('%H:%M'),
        channel_title: detail[2],
        title: detail[3],
        video_url: detail[0]
      }

      c.puts_event c.create(sc)
    end
  end
end

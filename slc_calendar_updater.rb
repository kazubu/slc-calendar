#!/usr/bin/env ruby

require_relative './slc_schedule_collector'
require_relative './slc_calendar'

module SLCCalendar
  class CalendarUpdater
    def initialize
    end

    def update_by_tweets
      ssc = SLCCalendar::ScheduleCollector.new
      c = SLCCalendar::Calendar.new

      s = []
      TWITTER_LISTS.each{|x|
        s += ssc.get_schedules(x[0], x[1])
      }

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
            c.puts_event(ev)
          else
            puts "## update"
            c.puts_event c.update(event_id, sc)
          end
        else
          puts "## create"
          c.puts_event c.create(sc)
        end
      }
    end

    # 配信URLをチェックして時間だけアップデートする
    def update_registered_events
      ended_count = 0
      skip_count = 0
      update_count = 0
      c = SLCCalendar::Calendar.new

      current_events = c.events(2, 120)

      current_events.each{|e|
        next unless e.description.index('/watch?v=')
        video_id = e.description.split('/watch?v=')[1].split('"')[0]

        detail = Utils.is_upcoming_stream(video_id)
        unless detail
          ended_count += 1
          next
        end

        start_date = detail[1].strftime('%Y/%m/%d')
        start_time = detail[1].strftime('%H:%M')

        if r = c.update_starttime(e, start_date, start_time)
          puts '## updated!'
          update_count += 1
          c.puts_event(r)
        else
          puts '## no update;skipped'
          skip_count += 1
          c.puts_event(e)
        end
      }

      puts "#{update_count} update; #{skip_count} skipped; #{ended_count} ended;"
    end
  end
end

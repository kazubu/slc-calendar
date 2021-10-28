#!/usr/bin/env ruby

require_relative './slc_schedule_collector'
require_relative './slc_calendar'

class SLCCalendarUpdater
  def initialize
  end

  def main
    ssc = SLCScheduleCollector.new
    c = SLCCalendar.new

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
          c.update(event_id, sc)
        end
      else
        puts "## create"
        c.create(sc)
      end
    }
  end
end

#!/usr/bin/env ruby

require_relative './slc_schedule_collector'

ssc = SLCCalendar::ScheduleCollector.new

s = []
TWITTER_LISTS.each{|x|
  s += ssc.get_schedules(x[0], x[1])
}

pp s


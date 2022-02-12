#!/usr/bin/env ruby

require_relative './lib/slc_schedule_collector'

ssc = SLCCalendar::ScheduleCollector.new

s = []
TWITTER_LISTS.each do |x|
  s += ssc.get_schedules(x[0], x[1])
end

pp s

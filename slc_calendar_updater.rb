#!/usr/bin/env ruby

require "google/apis/calendar_v3"
require "googleauth"
require "googleauth/stores/file_token_store"
require "fileutils"

require_relative './slc_schedule_collector'

class SLC_Calendar_Updater

  def initialize
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.client_options.application_name = APPLICATION_NAME
    @service.authorization = authorize
    @calendar_id = GOOGLE_CALENDAR_ID
  end

  def authorize
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(GOOGLE_CALENDAR_CLIENT_SECRET_PATH),
      scope: Google::Apis::CalendarV3::AUTH_CALENDAR)
    authorizer.fetch_access_token!
    authorizer
  end

  def puts_event(event)
    puts "Summary:  #{event.summary}"
    puts "ID:       #{event.id}"
    puts "Start:    #{event.start.date_time}"
    puts "End:      #{event.end.date_time}"
  end

  def a(url)
    return "<a href=\"#{url}\"target=\"_blank\">#{url}</a>"
  end

  def gen_description(ev)
    ret = ""
    ret += "Twitter: #{a("https://twitter.com/#{ev[:user]}")}\n" if ev[:user]
    ret += "チャンネル: #{ev[:channel_title]}\n" if ev[:channel_title]
    ret += "タイトル: #{ev[:title]}\n" if ev[:title]
    ret += "告知ツイート: #{a(ev[:tweet_url])}\n" if ev[:tweet_url]
    ret += "配信URL: #{a(ev[:video_url])}\n" if ev[:video_url]

    ret
  end

  def create(ev)
    title = "#{ev[:channel_title]}: #{ev[:title]}"
    description = gen_description(ev)
    year,mon,day,hr,min = "#{ev[:date]} #{ev[:time]}".gsub('/', ' ').gsub(':', ' ').split(' ').map{|x| x.to_i }
    start_time = DateTime.new(year, mon, day, hr, min, 0, offset="+0900")

    event = Google::Apis::CalendarV3::Event.new({
      summary: title,
      description: description,
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time + Rational(1, 24)
      )
    })

    response =  @service.insert_event(
      @calendar_id,
      event
    )

    puts_event(response)
  end

  def events
    events = @service.list_events(@calendar_id,
                                  time_min: (Time.now - 30*24*60*60).iso8601,
                                  time_max: (Time.now + 120*24*60*60).iso8601,
                                 )

    return events.items
  end

  def update(event_id, ev)
    title = "#{ev[:channel_title]}: #{ev[:title]}"
    description = gen_description(ev)
    year,mon,day,hr,min = "#{ev[:date]} #{ev[:time]}".gsub('/', ' ').gsub(':', ' ').split(' ').map{|x| x.to_i }

    start_time = DateTime.new(year, mon, day, hr, min, 0, offset="+0900")

    event = Google::Apis::CalendarV3::Event.new({
      summary: title,
      description: description,
      start: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time
      ),
      end: Google::Apis::CalendarV3::EventDateTime.new(
        date_time: start_time + Rational(1, 24)
      )
    })

    response =  @service.update_event(
      @calendar_id,
      event_id,
      event
    )

    puts_event(response)
  end

  def delete(event_id)
    @service.delete_event(
      @calendar_id,
      event_id
    )
  end

  def main
    ssc = SLCScheduleCollector.new

    s = []
    TWITTER_LISTS.each{|x|
      s += ssc.get_schedules(x[0], x[1])
    }

    current_events = events

    s.each{|ev|
      event_id = nil
      current_events.each{|cev|
        event_id = cev.id if cev.description.index(ev[:video_url]) if ev[:video_url]
        event_id = cev.id if cev.description.index(ev[:tweet_url]) if ev[:tweet_url] if event_id.nil?
      }

      if event_id
        puts "update"
        update(event_id, ev)
      else
        puts "create"
        create(event_id)
      end
    }
  end
end

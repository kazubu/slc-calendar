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
      json_key_io: File.open(__dir__ + '/' + GOOGLE_CALENDAR_CLIENT_SECRET_PATH),
      scope: Google::Apis::CalendarV3::AUTH_CALENDAR)
    authorizer.fetch_access_token!
    authorizer
  end

  def puts_event(event)
    puts "\tSummary:  #{event.summary}"
    puts "\tID:       #{event.id}"
    puts "\tStart:    #{event.start.date_time}"
    puts "\tEnd:      #{event.end.date_time}"
  end

  def a(url)
    return "<a href=\"#{url}\"target=\"_blank\">#{url}</a>"
  end

  def gen_description(sc)
    ret = ""
    ret += "チャンネル: #{sc[:channel_title]}\n" if sc[:channel_title]
    ret += "タイトル: #{sc[:title]}\n" if sc[:title]
    ret += "\n"
    ret += "配信URL: #{a(sc[:video_url])}\n" if sc[:video_url]
    ret += "\n"
    ret += "告知ツイート: #{a(sc[:tweet_url])}\n" if sc[:tweet_url]

    ret
  end

  def gen_event(sc)
    title = "#{sc[:channel_title]}: #{sc[:title]}"
    description = gen_description(sc)
    year,mon,day,hr,min = "#{sc[:date]} #{sc[:time]}".gsub('/', ' ').gsub(':', ' ').split(' ').map{|x| x.to_i }
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

    event
  end

  def create(sc)
    return if sc.nil?

    event = gen_event(sc)
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

  def update(event_id, sc)
    return if sc.nil?

    event = gen_event(sc)
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

    s.each{|sc|
      event_id = nil
      current_events.each{|ev|
        event_id = ev.id if ev.description.index(sc[:video_url]) if sc[:video_url]
        event_id = ev.id if ev.description.index(sc[:tweet_url]) if sc[:tweet_url] if event_id.nil?
      }

      if event_id
        ev = current_events.select{|x| x.id == event_id}[0]
        nev = gen_event(sc)
        if ev.summary == nev.summary && ev.description == nev.description && ev.start.date_time == nev.start.date_time && ev.end.date_time == nev.end.date_time
          puts "## no update; skip"
          puts_event(ev)
        else
          puts "## update"
          update(event_id, sc)
        end
      else
        puts "## create"
        create(sc)
      end
    }
  end
end

#!/usr/bin/env ruby

require "google/apis/calendar_v3"
require "googleauth"
require "googleauth/stores/file_token_store"
require "fileutils"

module SLCCalendar
  class Calendar
    def initialize
      @service = Google::Apis::CalendarV3::CalendarService.new
      @service.client_options.application_name = APPLICATION_NAME
      @service.authorization = authorize
      @calendar_id = GOOGLE_CALENDAR_ID
    end

    def puts_event(event, message: nil)
      print "#{message}\t" if message
      print "summary: #{event.summary},"
      print " calendar_id: #{event.id},"
      print " start_time: #{event.start.date_time},"
      print " end_time: #{event.end.date_time}\n"
    end

    # return true if event info is same
    def compare_events(ev, nev)
      return false if ev.summary != nev.summary
      return false if ev.description != nev.description
      return false if ev.start.date_time != nev.start.date_time
      return false if ev.end.date_time != nev.end.date_time
      if ev.extended_properties
        return false if nev.extended_properties.nil?
        if ev.extended_properties.shared
          return false if nev.extended_properties.shared.nil?
          return false if ev.extended_properties.shared != nev.extended_properties.shared
        else
          return false if nev.extended_properties.shared
        end
        if ev.extended_properties.private
          return false if nev.extended_properties.private.nil?
          return false if ev.extended_properties.private != nev.extended_properties.private
        else
          return false if nev.extended_properties.private
        end
      else
        return false if nev.extended_properties
      end

      true
    end

    def is_live_ended(e)
      return true if e.description[-2,2] == '##'
      return true if e.extended_properties && e.extended_properties.shared && e.extended_properties.shared["live_ended"] && e.extended_properties.shared["live_ended"] == "true"
      false
    end

    def gen_event(sc)
      title = "#{sc.video.channel_title}: #{sc.video.video_title}"
      description = gen_description(sc)
      start_time = nil
      end_time = nil

      if sc.video.scheduled_start_time
        start_time = DateTime.parse(sc.video.scheduled_start_time.to_s)
      end

      if start_time.nil? || ( sc.video.actual_start_time && ( sc.video.actual_start_time - sc.video.scheduled_start_time ).floor.abs > 600 )
        start_time = DateTime.parse(sc.video.actual_start_time.to_s)
      end

      raise "Start date is not found" unless start_time

      live_ended = false
      if sc.video.actual_end_time
        end_time = DateTime.parse(sc.video.actual_end_time.to_s)
        live_ended = true
      else
        end_time = start_time + Rational(1, 24)
      end

      thumbnail_url = sc.video.thumbnail_url
      ep = Google::Apis::CalendarV3::Event::ExtendedProperties.new({
        shared: {
          "thumbnail_url" => thumbnail_url,
          "live_ended" => (live_ended ? "true" : "false")
        }
      })

      event = Google::Apis::CalendarV3::Event.new({
        summary: title,
        description: description,
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: start_time
        ),
        extended_properties: ep,
        end: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: end_time
        )
      })

      event
    end

    def events(past = 7, future = 120)
      events = @service.list_events(@calendar_id,
                                    time_min: (Time.now - past * 24 * 60 * 60).iso8601,
                                    time_max: (Time.now + future * 24 * 60 * 60).iso8601
                                   )

      puts "#{events.items.length} events received"
      return events.items
    end

    def create(sc)
      return if sc.nil?

      event = gen_event(sc)
      response =  @service.insert_event(
        @calendar_id,
        event
      )

      return response
    end

    def update(event_id, sc)
      return if sc.nil?

      event = gen_event(sc)
      response =  @service.update_event(
        @calendar_id,
        event_id,
        event
      )

      return response
    end

    def update_event(ev)
      return if ev.nil?

      response = @service.update_event(
        @calendar_id,
        ev.id,
        ev
      )

      return response
    end

    def delete(event_id)
      @service.delete_event(
        @calendar_id,
        event_id
      )
    end

    private
    def authorize
      authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(GOOGLE_CALENDAR_CLIENT_SECRET_PATH),
        scope: Google::Apis::CalendarV3::AUTH_CALENDAR)
      authorizer.fetch_access_token!
      authorizer
    end

    def a(url)
      return "<a href=\"#{url}\"target=\"_blank\">#{url}</a>"
    end

    def gen_description(sc)
      tweet_url = nil
      if sc.tweet.kind_of?(String)
        tweet_url = sc.tweet
      else
        tweet_url = sc.tweet.uri if sc.tweet.uri
      end

      ret = ""
      ret += "チャンネル: #{sc.video.channel_title}\n"
      ret += "タイトル: #{sc.video.video_title}\n"
      ret += "\n" if sc.video.video_url
      ret += "配信URL: #{a(sc.video.video_url)}\n" if sc.video.video_url
      ret += "\n" if tweet_url
      ret += "告知ツイート: #{a(tweet_url)}\n" if tweet_url
      ret += "##" if !sc.video.is_upcoming_stream

      ret
    end

  end
end

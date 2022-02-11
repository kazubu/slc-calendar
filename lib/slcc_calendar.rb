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

      if sc.video.actual_end_time
        end_time = DateTime.parse(sc.video.actual_end_time.to_s)
      else
        end_time = start_time + Rational(1, 24)
      end

      event = Google::Apis::CalendarV3::Event.new({
        summary: title,
        description: description,
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: start_time
        ),
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

      ret
    end

  end
end

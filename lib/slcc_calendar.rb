#!/usr/bin/env ruby
# frozen_string_literal: true

require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'

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
        elsif nev.extended_properties.shared
          return false
        end
        if ev.extended_properties.private
          return false if nev.extended_properties.private.nil?
          return false if ev.extended_properties.private != nev.extended_properties.private
        elsif nev.extended_properties.private
          return false
        end
      elsif nev.extended_properties
        return false
      end

      true
    end

    def is_live_ended(e)
      return true if e.description[-2, 2] == '##'
      return true if e.extended_properties && e.extended_properties.shared && e.extended_properties.shared['live_ended'] && e.extended_properties.shared['live_ended'] == 'true'

      false
    end

    def gen_event(sc)
      title = "#{sc.video.channel_title}: #{sc.video.video_title}"
      description = gen_description(sc)

      start_time = DateTime.parse(sc.video.scheduled_start_time.to_s) if sc.video.scheduled_start_time
      start_time = DateTime.parse(sc.video.actual_start_time.to_s) if start_time.nil? || (sc.video.actual_start_time && (sc.video.actual_start_time - sc.video.scheduled_start_time).floor.abs > 600)

      raise 'Start date is not found' unless start_time

      end_time = if sc.video.actual_end_time
                   DateTime.parse(sc.video.actual_end_time.to_s)
                 else
                   start_time + Rational(1, 24)
                 end

      thumbnail_url = sc.video.thumbnail_url
      live_ended = !sc.video.upcoming_stream?
      live_url = sc.video.video_url
      on_live = sc.video.live_state == 'live'
      ep = Google::Apis::CalendarV3::Event::ExtendedProperties.new({
                                                                     shared: {
                                                                       'thumbnail_url' => thumbnail_url,
                                                                       'live_ended' => (live_ended ? 'true' : 'false'),
                                                                       'live_url' => live_url,
                                                                       'on_live' => (on_live ? 'true' : 'false'),
                                                                       'channel_name' => sc.video.channel_title,
                                                                       'video_title' => sc.video.video_title
                                                                     }
                                                                   })

      Google::Apis::CalendarV3::Event.new({
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
    end

    def events(past = 7, future = 120)
      events = @service.list_events(@calendar_id,
                                    time_min: (Time.now - past * 24 * 60 * 60).iso8601,
                                    time_max: (Time.now + future * 24 * 60 * 60).iso8601)

      puts "#{events.items.length} events received"
      events.items
    end

    def create(sc)
      return if sc.nil?

      event = gen_event(sc)
      @service.insert_event(
        @calendar_id,
        event
      )
    end

    def update(event_id, sc)
      return if sc.nil?

      event = gen_event(sc)
      @service.update_event(
        @calendar_id,
        event_id,
        event
      )
    end

    def update_event(ev)
      return if ev.nil?

      @service.update_event(
        @calendar_id,
        ev.id,
        ev
      )
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
        scope: Google::Apis::CalendarV3::AUTH_CALENDAR
      )
      authorizer.fetch_access_token!
      authorizer
    end

    def a(url)
      "<a href=\"#{url}\"target=\"_blank\">#{url}</a>"
    end

    def gen_description(sc)
      tweet_url = nil
      if sc.tweet.is_a?(String)
        tweet_url = sc.tweet
      elsif sc.tweet.uri
        tweet_url = sc.tweet.uri
      end

      ret = +''
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

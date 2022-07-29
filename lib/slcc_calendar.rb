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

    def event_summary(event)
      s = "summary: #{event.summary},"
      s += " calendar_id: #{event.id},"
      s += " start_time: #{event.start.date_time},"
      s += " end_time: #{event.end.date_time}"
      s
    end

    # return true if event info is same
    def compare_events(event, new_event)
      return false if event.summary != new_event.summary
      return false if event.description != new_event.description
      return false if event.start.date_time != new_event.start.date_time
      return false if event.end.date_time != new_event.end.date_time

      if event.extended_properties
        return false if new_event.extended_properties.nil?

        if event.extended_properties.shared
          return false if new_event.extended_properties.shared.nil?
          return false if event.extended_properties.shared != new_event.extended_properties.shared
        elsif new_event.extended_properties.shared
          return false
        end
        if event.extended_properties.private
          return false if new_event.extended_properties.private.nil?
          return false if event.extended_properties.private != new_event.extended_properties.private
        elsif new_event.extended_properties.private
          return false
        end
      elsif new_event.extended_properties
        return false
      end

      true
    end

    def is_live_ended(event)
      return true if event.description[-2, 2] == '##'
      return true if event&.extended_properties&.shared && event.extended_properties.shared['live_ended'] && event.extended_properties.shared['live_ended'] == 'true'

      false
    end

    def gen_event(schedule)
      title = "#{schedule.video.channel_title}: #{schedule.video.video_title}"
      description = gen_description(schedule)

      start_time = DateTime.parse(schedule.video.scheduled_start_time.to_s) if schedule.video.scheduled_start_time
      if start_time.nil? || (schedule.video.actual_start_time && (schedule.video.actual_start_time - schedule.video.scheduled_start_time).floor.abs > 600)
        start_time = DateTime.parse(schedule.video.actual_start_time.to_s)
      end

      raise 'Start date is not found' unless start_time

      end_time = if schedule.video.actual_end_time
                   DateTime.parse(schedule.video.actual_end_time.to_s)
                 else
                   start_time + Rational(1, 24)
                 end

      if schedule.video.on_live? && (DateTime.now - end_time) > 0
        end_time = DateTime.now + Rational(10, 24*60)
      end

      tweet_url = ''
      if schedule.tweet.is_a?(String)
        tweet_url = schedule.tweet
      elsif schedule.tweet&.uri
        tweet_url = schedule.tweet.uri.to_s
      end

      thumbnail_url = schedule.video.thumbnail_url
      live_ended = !schedule.video.upcoming_or_on_live?
      live_url = schedule.video.video_url
      on_live = schedule.video.on_live?
      ep = Google::Apis::CalendarV3::Event::ExtendedProperties.new({
                                                                     shared: {
                                                                       'tweet_url' => tweet_url,
                                                                       'thumbnail_url' => thumbnail_url,
                                                                       'live_ended' => (live_ended ? 'true' : 'false'),
                                                                       'live_url' => live_url,
                                                                       'on_live' => (on_live ? 'true' : 'false'),
                                                                       'channel_name' => schedule.video.channel_title,
                                                                       'channel_id' => schedule.video.channel_id,
                                                                       'video_title' => schedule.video.video_title,
                                                                       'video_id' => schedule.video.video_id
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
      page_token = nil
      items = []

      time_min = (Time.now - ( past * 24 * 60 * 60 )).iso8601
      time_max = (Time.now + ( future * 24 * 60 * 60 )).iso8601

      begin
        events = @service.list_events(@calendar_id,
                                      max_results: 2500,
                                      time_min: time_min,
                                      time_max: time_max )
        #events.items.each{|x| items << x }
        items += events.items

        page_token = events.next_page_token ? events.next_page_token : nil
      end while !page_token.nil?

      items
    end

    def create(schedule)
      return if schedule.nil?

      event = gen_event(schedule)
      @service.insert_event(
        @calendar_id,
        event
      )
    end

    def update(event_id, schedule)
      return if schedule.nil?

      event = gen_event(schedule)
      @service.update_event(
        @calendar_id,
        event_id,
        event
      )
    end

    def update_event(event)
      return if event.nil?

      @service.update_event(
        @calendar_id,
        event.id,
        event
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

    def gen_description(schedule)
      tweet_url = nil
      if schedule.tweet.is_a?(String)
        tweet_url = schedule.tweet
      elsif schedule.tweet&.uri
        tweet_url = schedule.tweet.uri.to_s
      end

      ret = +''
      ret += "チャンネル: #{schedule.video.channel_title}\n"
      ret += "タイトル: #{schedule.video.video_title}\n"
      ret += "\n" if schedule.video.video_url
      ret += "配信URL: #{a(schedule.video.video_url)}\n" if schedule.video.video_url
      ret += "\n" if tweet_url
      ret += "告知ツイート: #{a(tweet_url)}\n" if tweet_url

      ret
    end
  end
end

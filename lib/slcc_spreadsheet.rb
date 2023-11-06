#!/usr/bin/env ruby
# frozen_string_literal: true

require 'google/apis/sheets_v4'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'

module SLCCalendar
  class Spreadsheet
    def initialize
      @service = Google::Apis::SheetsV4::SheetsService.new
      @service.client_options.application_name = APPLICATION_NAME
      @service.authorization = authorize
      @spreadsheet_id = GOOGLE_SPREADSHEET_ID
      @ranges = GOOGLE_SPREADSHEET_RANGES
    end

    def get_youtube_channels
      result = []
      begin
        @ranges.each do |r|
          @service.get_spreadsheet_values(@spreadsheet_id, r).values.each do |row|
            result << { name: row[0], channel: row[2] } if row[2] && row[2].length > 0
          end
        end
      rescue => e
        puts "Exception: #{e}"
      end

      result
    end

    private

    def authorize
      authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(GOOGLE_CALENDAR_CLIENT_SECRET_PATH),
        scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
      )
      authorizer.fetch_access_token!
      authorizer
    end
  end
end

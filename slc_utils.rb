#!/usr/bin/env ruby

module SLCCalendar
  module Utils
    def retry_on_error(times: 3)
      try = 0
      begin
        try += 1
        yield
      rescue
        retry if try < times
        raise
      end
    end

    def expand_url(url)
      begin
        response = Net::HTTP.get_response(URI.parse(url))
      rescue
        return url
      end
      case response
      when Net::HTTPRedirection
        expand_url(response['location'])
      else
        url
      end
    end

    def vurl_to_vid(url)
      if url.index('http') == 0
        return url.split('v=')[1].split('&')[0]
      else
        return url
      end
    end

    module_function :retry_on_error
    module_function :expand_url
    module_function :vurl_to_vid
  end
end

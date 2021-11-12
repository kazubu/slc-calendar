# SLC Calendar

The purpose of this program is to retrieve upcoming live broadcasts on YouTube from the Twitter list and register them as schedules in Google Calendar so that you can easily check the schedule of the broadcasts.

## Install

The required gems needed to be installed. Gemfile is included in this repository.

You need to rename `config.rb.example` to `config.rb` and fill the required parameters.
Required parameters are:
 - Twitter API Consumer Key/Consumer Secret/Bearer token
 - List of Twitter Lists
 - API Key for YouTube Data API v3
 - Google Calendar ID
 - The path of client secret for a Service Account which has full access for above Google Calendar.

## Usage

Then you can execute `update`, `update_by_tweets` or `update_registered` command that works as below. It's recommended to register them to crontab or any periodical execution mechanism.
 - `update_by_tweets` command checks the tweets from Twitter list and register tweeted livestreams.
 - `update_registered` command checks already registered events in Google Calendar and reflects the changes of the livestream.
 - `update` command runs both above actions in sequence.




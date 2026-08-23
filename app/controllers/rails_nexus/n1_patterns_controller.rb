module RailsNexus
  class N1PatternsController < ApplicationController
    before_action :rails_nexus_require_auth!

    def index
      @patterns = RailsNexus::LoggedException.n_plus_one_patterns(limit: 50)
      @summary = RailsNexus::LoggedException.n_plus_one_summary
    end
  end
end

module RailsNexus
  class N1PatternsController < ApplicationController
    def index
      @patterns = RailsNexus::LoggedException.n_plus_one_patterns(limit: 50)
      @summary = RailsNexus::LoggedException.n_plus_one_summary
    end
  end
end

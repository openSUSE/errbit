# frozen_string_literal: true

# Gem-provided trackers register themselves when their gem is required. The
# in-repo GitHub App tracker lives in lib/ and is therefore reloaded by
# Zeitwerk in development, so each (re)load has to replace the previously
# registered class with the fresh one.
Rails.application.config.to_prepare do
  ErrbitPlugin::Registry.issue_trackers.delete(ErrbitGithubAppPlugin::IssueTracker.label)

  ErrbitPlugin::Registry.add_issue_tracker(ErrbitGithubAppPlugin::IssueTracker)
end

# Load the Rails application.
require File.expand_path('../application', __FILE__)

# Load up Errbit::Config with values from the environment
require Rails.root.join('config/load')

if Errbit::Config.log_location == 'STDOUT'
  Rails.logger = ActiveSupport::Logger.new STDOUT
elsif Errbit::Config.log_location == 'Syslog::Logger'
  require 'syslog/logger'
  Rails.logger = Syslog::Logger.new('errbit', Syslog::LOG_LOCAL0)
else
  Rails.logger = ActiveSupport::Logger.new Errbit::Config.log_location
end

Rails.logger.level = Errbit::Config.log_level.to_sym

ActionMailer::Base.smtp_settings = {
  :address        => 'smtp.sendgrid.net',
  :port           => '587',
  :authentication => :plain,
  :user_name      => ENV['SENDGRID_USERNAME'],
  :password       => ENV['SENDGRID_PASSWORD'],
  :domain         => 'heroku.com',
  :enable_starttls_auto => true
}

# Initialize the Rails application.
Rails.application.initialize!


# frozen_string_literal: true

module ErrbitGithubAppPlugin
  # Files GitHub issues as a GitHub App installation instead of with user
  # credentials. The App only needs the "Issues: Read & write" repository
  # permission and only reaches the repositories it is installed on, so
  # neither Errbit nor any user has to hold a broad "repo" scoped token.
  class IssueTracker < ErrbitPlugin::IssueTracker
    class Error < StandardError; end

    LABEL = "github_app"

    NOTE = "Issues are created by a GitHub App instead of a user account, " \
           "so nobody needs a write-scoped OAuth token. Configure your " \
           "GitHub repository in the <strong>GITHUB REPO</strong> field " \
           "above, set the GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY " \
           "environment variables, and install the App (with the " \
           "<strong>Issues: Read &amp; write</strong> permission) on the " \
           "repository."

    # The credentials are site-wide environment variables and the repository
    # comes from the app's GITHUB REPO field, so there is nothing to fill in
    # per app.
    FIELDS = {}

    # GitHub rejects App JWTs that expire more than ten minutes ahead of its
    # own clock, so stay a minute short of that: the backdated iat below covers
    # our clock running behind, this covers it running ahead.
    JWT_LIFETIME = 540

    # The classic mixup is pasting the App's 40-character hex client secret,
    # which is an OAuth credential and cannot sign App tokens.
    NOT_A_PRIVATE_KEY = "GITHUB_APP_PRIVATE_KEY holds neither an RSA private key in PEM " \
                        "format nor the path of a readable .pem file. Download the key " \
                        "with the \"Generate a private key\" button on the GitHub App's " \
                        "settings page - the App's client secret is a different " \
                        "credential and cannot be used here."

    def self.label
      LABEL
    end

    def self.note
      NOTE
    end

    def self.fields
      FIELDS
    end

    def self.icons
      ErrbitGithubPlugin::IssueTracker.icons
    end

    def configured?
      errors.empty?
    end

    def url
      "#{Errbit::Config.github_url}/#{repo}/issues"
    end

    def errors
      errors = []

      if Errbit::Config.github_app_id.blank? || Errbit::Config.github_app_private_key.blank?
        errors << [:base, "You must set the GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY environment variables."]
      elsif (key_error = private_key_error)
        errors << [:base, key_error]
      end

      if repo.blank?
        errors << [:base, "You must specify your GitHub repository url."]
      end

      errors
    end

    def repo
      options[:github_repo]
    end

    def create_issue(title, body, user: {})
      issue = client.create_issue(repo, title, attributed_body(body, user))

      issue.html_url
    end

    # @param url [String]
    # @param user [Hash]
    # @return [String] The URL of the closed issue
    def close_issue(url, user: {})
      # It would be better to get the number from issue.number when we create
      # the issue, however, since we only have the url, get the number from it.
      # ex: "https://github.com/octocat/Hello-World/issues/1347"
      issue_number = url.split("/").last

      issue = client.close_issue(repo, issue_number)

      issue.html_url
    end

    private

    # The App acts as "<app-name>[bot]", so name the real reporter in the body.
    def attributed_body(body, user)
      login = user["github_login"]
      reporter = login.present? ? "@#{login}" : user["name"]

      return body if reporter.blank?

      "#{body}\n\n_Reported by #{reporter} via Errbit_"
    end

    def client
      Octokit::Client.new(
        access_token: installation_token,
        api_endpoint: Errbit::Config.github_api_url
      )
    end

    # Asks GitHub where the App is installed for the repository and trades the
    # App JWT for a one-hour token narrowed down to just the issues of that
    # one repository, whatever else the installation covers.
    def installation_token
      app_client = Octokit::Client.new(
        bearer_token: app_jwt,
        api_endpoint: Errbit::Config.github_api_url
      )

      installation = app_client.find_repository_installation(repo)

      app_client.create_app_installation_access_token(
        installation.id,
        repositories: [repo.split("/").last],
        permissions: {issues: "write"}
      ).token
    rescue Octokit::NotFound
      raise Error, "The GitHub App is not installed on #{repo}. " \
                   "Install it on the repository to let Errbit create issues."
    rescue Octokit::Unauthorized
      raise Error, "GitHub did not accept the App credentials. " \
                   "Check GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY."
    end

    def app_jwt
      now = Time.now.to_i

      # iat is backdated by the sixty seconds GitHub recommends to survive
      # clock drift between us and them
      payload = {
        iat: now - 60,
        exp: now + JWT_LIFETIME,
        iss: Errbit::Config.github_app_id.to_s
      }

      JWT.encode(payload, private_key, "RS256")
    end

    # Parsed once per tracker: configured? asks for the key on every render
    # and app save, and creating an issue needs it again right afterwards.
    def private_key
      @private_key ||= OpenSSL::PKey::RSA.new(private_key_pem).tap do |key|
        raise Error, NOT_A_PRIVATE_KEY unless key.private?
      end
    rescue OpenSSL::PKey::RSAError
      raise Error, NOT_A_PRIVATE_KEY
    end

    # GITHUB_APP_PRIVATE_KEY either holds the PEM itself (with its newlines
    # usually escaped by the environment) or the path of the .pem file.
    def private_key_pem
      value = Errbit::Config.github_app_private_key

      return value.gsub('\n', "\n") if value.include?("-----BEGIN")

      # The value is not echoed on failure: an unreadable path is usually a
      # pasted secret of the wrong kind, which must not end up in a flash
      # message or log.
      File.read(value)
    rescue SystemCallError
      raise Error, NOT_A_PRIVATE_KEY
    end

    def private_key_error
      private_key

      nil
    rescue Error => e
      e.message
    end
  end
end

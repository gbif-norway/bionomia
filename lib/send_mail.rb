# encoding: utf-8

module Bionomia
  class SendMail

    def initialize(opts = {})
      settings = Settings.merge!(opts)
      Pony.options = {
        charset: 'UTF-8',
        from: settings.gmail.email,
        subject: (settings.subject || subject),
        via: :smtp,
        via_options: {
          address: 'smtp.gmail.com',
          port: '587',
          enable_starttls_auto: true,
          user_name: settings.gmail.username,
          password: settings.gmail.password,
          domain: settings.gmail.domain
        }
      }
    end

    def send_message(email:, body:)
      Pony.mail(
        to: email,
        body: body
      )
    end

    def send_messages
      users = User.where.not(email: nil)
                  .where(wants_mail: true)
                  .where("mail_last_sent < ? OR mail_last_sent IS NULL", 6.days.ago)
      users.find_each do |user|
        articles = user_articles(user)
        if articles.count > 0
          begin
            body = construct_message(user, articles)
            send_message(email: user.email, body: body)
          rescue
            puts "Email failed for #{user.email}"
            next
          end
        end
        user.mail_last_sent = Time.now
        user.save
      end
    end

    def mark_articles_sent
      Article.where(mail_sent: false).update_all(mail_sent: true)
    end

    def subject
      "Bionomia :: New articles used your specimen data"
    end

    def salutation(fullname = "")
      "Dear #{fullname},\n\n"\
      "The following articles were recently discovered by the Global Biodiversity Information Facility (GBIF) as having used the data from specimens you collected or identified.\n\n"
    end

    def format_article(article)
      "#{article[:citation]} https://doi.org/#{article[:doi]}. [Your records: https://bionomia.net/profile/citation/#{article[:doi]}]"
    end

    def closing
      "\n\n\nWe hope you enjoy Bionomia, https://bionomia.net and find it useful. "\
      "Your support is greatly appreciated, https://bionomia.net/donate.\n"\
      "If you wish to stop receiving these messages, login to your account and adjust the email notification settings in your profile."
    end

    private

    def user_articles(user)
      Article.joins(article_occurrences: :user_occurrences)
             .where(user_occurrences: { user_id: user.id, visible: true })
             .where.not(citation: nil)
             .distinct
             .pluck_to_hash(:doi, :citation, :mail_sent)
             .delete_if{|o| o[:mail_sent]}
    end

    def construct_message(user, articles)
      body  = salutation(user.fullname)
      body += articles.map{|a| format_article(a) }.join("\n\n")
      body += closing
      body
    end

  end
end

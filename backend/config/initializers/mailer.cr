# Mail delivery. Tests record mails in memory; development writes .eml files
# to tmp/mails (reset links are also logged); production picks a provider:
#
#   MAIL_DELIVERY=smtp      SMTP_HOST, SMTP_PORT (587), SMTP_USERNAME, SMTP_PASSWORD
#   MAIL_DELIVERY=ses       AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   MAIL_DELIVERY=sendgrid  SENDGRID_API_KEY  (also mailgun, postmark)
#   MAIL_FROM="Braxy <no-reply@example.com>"
case Saci.env
when "test"
  Saci::Mailer.delivery_adapter = :test
when "production"
  case ENV["MAIL_DELIVERY"]? || "smtp"
  when "ses"      then Saci::Mailer.delivery_method = :ses
  when "sendgrid" then Saci::Mailer.delivery_method = :sendgrid
  when "mailgun"  then Saci::Mailer.delivery_method = :mailgun
  when "postmark" then Saci::Mailer.delivery_method = :postmark
  else
    Saci::Mailer.delivery_adapter = :smtp
    Saci::Mailer.smtp_settings = Saci::Mailer::SmtpSettings.new(
      host: ENV["SMTP_HOST"]? || "localhost",
      port: (ENV["SMTP_PORT"]? || "587").to_i,
      username: ENV["SMTP_USERNAME"]?,
      password: ENV["SMTP_PASSWORD"]?,
      tls: :auto)
  end
else
  Saci::Mailer.delivery_adapter = :file
end

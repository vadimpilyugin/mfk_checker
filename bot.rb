require 'telegram/bot'
require "open-uri"

BOT_TOKEN = '368621709:AAFU630-YbkR7FKV7jnpXBpoYdaeNiYVR_E'
SECONDS_TO_WAIT = 60

token = BOT_TOKEN
user_list = {}

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message.text
    when '/start'
      bot.api.send_message(chat_id: message.chat.id, text: "Привет! Напиши id курса, который нужно мониторить")  
    when /\d+/
      if !user_list.has_key?(message.chat.id)
        course_id = message.text.to_i
        response = check_site_for_updates(course_id)
        if response[:ok]
          bot.api.send_message(chat_id: message.chat.id, text: "Ок! Буду следить за этим курсом")
          bot.api.send_message(chat_id: message.chat.id, text: "Места: #{response['current']}/#{response['all']}")
          # user_list[message.chat.id] = message.text.to_i
          pid = Process.fork do
            while true do
              alert_if_has_empty(course_id, bot, message.chat.id)
              sleep SECONDS_TO_WAIT
            end
          end
          user_list[message.chat.id] = pid
        else
          bot.api.send_message(chat_id: message.chat.id, text: "Извини! Произошла ошибка")
        end
      end
    when '/stop'
      bot.api.send_message(chat_id: message.chat.id, text: "Прощай!")
      Process.kill('INT', user_list[message.chat.id]) if user_list.has_key?(message.chat.id)
      user_list.delete(message.chat.id)
    end
  end
end

def check_site_for_updates(id)
  data = URI.parse("https://lk.msu.ru/course/view?id=#{id}").read
  regex = /<p><strong>Записалось \/ всего мест<\/strong><br \/>\s+(?<current>\d+)\s+\/\s+(?<all>\d+)/
  if data =~ regex
    return {current: $~['current'].to_i, all: $~['all'].to_i, ok: true}
    	# 
  else
    return {ok: false}
  end
end

def alert_if_has_empty(id, bot, chat_id)
  response = check_site_for_updates(id)
  if response[:ok] #&& response[:current] < response[:all]
    bot.api.send_message(
      chat_id: chat_id,
      parse_mode: 'Markdown',
      text:"Эй! Появилось место на курсе!\n"+"(https://lk.msu.ru/course/view?id=#{id})\n"+"Места: *#{response[:current]}/#{response[:all]}*\n")
  end
end
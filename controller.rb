require_relative 'model'
require_relative 'view'
require 'telegram/bot'

class Controller
  BOT_TOKEN = ''
  SECONDS_TO_WAIT = 10

  def self.run_bot
    Telegram::Bot::Client.run(BOT_TOKEN) do |bot|
      Thread.new {update_courses(bot)}
      bot.listen do |message|
        Printer::debug(
          who:"[@#{message.from.username}]",
          msg:message.text
        )
      	case message.text
      	  when '/start'
      	  	# создаем пользователя или находим существующего
      	  	user = User.first_or_create(
      	  	  chat_id:message.chat.id,
      	  	  username:message.from.username
      	  	)
      	  	# пишем приветствие и пояснение к использованию
            bot.api.send_message(
              chat_id: message.chat.id, 
              text: View::start_message
            )
          when /\/add\s+(?<course_id>\d+)/
            course_id = $~['course_id'].to_i
            # создаем или получаем курс
            status = Course.create_course course_id
            # если произошла ошибка во время создания курса
            if !status[:ok]
              # отправляем сообщение с ошибкой
              bot.api.send_message(
                parse_mode: 'Markdown', 
                chat_id: message.chat.id, 
                text: View::sub_message(ok:false, msg:status[:msg], course:status[:course], course_id:course_id)
              )
            else
              # ошибки не было
              # записываем в переменную
              course = status[:course]
              # добавляем в список подписок этот курс
              status = User.sub(message.chat.id, course.course_id)
              # если успешно подписали на курс
              if status[:ok]
                View::sub_message(ok:true, course:course, chat_id:message.chat.id).each do |msg|
                  # пишем сообщение, что курс добавлен в подписки
                  bot.api.send_message(
                    parse_mode: 'Markdown', 
                    chat_id: message.chat.id, 
                    text: msg
                  )
                end
              # если произошла ошибка с подпиской
              else
                # пишем сообщение об ошибке
                bot.api.send_message(
                  parse_mode: 'Markdown', 
                  chat_id: message.chat.id, 
                  text: View::sub_message(ok:false, course:course, chat_id:message.chat.id, msg:status[:msg])
                )
              end
            end
          when /\/remove\s+(?<course_id>\d+)/
            # запоминаем course_id
            course_id = $~['course_id'].to_i
            course = Course.get course_id
            # удаляем из подписок этот курс
            status = User.unsub(message.chat.id, course_id)
            # если успешно отписали
            if status[:ok]
              # пишем сообщение, что курс удален из подписок
              bot.api.send_message(
                parse_mode: 'Markdown', 
                chat_id: message.chat.id, 
                text: View::unsub_message(ok:true, course:course)
              )
            else
              # пишем сообщение, что произошла ошибка удаления курса из подписок
              bot.api.send_message(
                parse_mode: 'Markdown', 
                chat_id: message.chat.id, 
                text: View::unsub_message(ok:false, msg:status[:msg])
              )
            end
          when '/stop'
            # удаляем все подписки пользователя
            status = User.unsub_all(message.chat.id)
            # если успешно отписали
            if status[:ok]
              # посылаем сообщение с прощанием
              bot.api.send_message(
                parse_mode: 'Markdown', 
                chat_id: message.chat.id, 
                text: View::bye_message(ok:true)
              )
            else
              # посылаем сообщение с ошибкой
              bot.api.send_message(
                parse_mode: 'Markdown', 
                chat_id: message.chat.id, 
                text: View::bye_message(ok:false)
              )
            end
          when /\/check/
            # запускаем новую нить, которая проверит курсы пользователя
            Thread.new do
              # для каждого курса пользователя
              User.get(message.chat.id).courses.each do |crs| 
                Course.update_course(crs.course_id)
                # посылаем пользователю обновленную информацию
                bot.api.send_message(
                  parse_mode: 'Markdown', 
                  chat_id: message.chat.id, 
                  text: View::course_to_string(crs)
                )
              end
            end
          when '/help'
            bot.api.send_message(
              parse_mode: 'Markdown', 
              chat_id: message.chat.id, 
              text: View::api_message
            )
        end
      end
    end
  end
  def self.update_courses(bot)
    while true
      # выбираем список курсов, у которых есть подписчики и время последнего обновления меньше
      # текущего минус число секунд
      courses_to_update = DataMapper.repository.adapter.select(
        'select courses.course_id as id from courses 
        where update_time < \''+(Time.now-SECONDS_TO_WAIT).strftime('%Y-%m-%d %H:%M:%S')+'\'  and
                (select count(*) from course_users 
                where course_course_id = courses.course_id) > 0 order by (select count(*) from course_users 
                where course_course_id = courses.course_id) desc')
      # если нет курсов для обновления
      if courses_to_update.empty?
        # спим 1 секунду
        sleep 1
      # если есть курсы
      else
        Printer::debug(
          who:"[update_courses]",
          msg:"#{courses_to_update.size} courses to update"
        )
        # для каждого курса из выбранной группы
        courses_to_update.each do |course_id| 
          # вызываем функцию обновления
          Course.update_course(course_id)
          # сохраняем запись о курсе
          course = Course.get(course_id)
          # если места только что появились либо места только что закончились
          if course.has_changed
            # создаем новую нить для отправки уведомлений пользователям
            Thread.new(course) do |crs|
              Printer::debug(
                who:"[update_courses]", 
                msg:"course '#{crs.name}' has #{crs.all - crs.current} empty places!"
              )
              # для всех пользователей, подписанных на курс
              crs.users.each do |user|
                # сообщаем, что есть свободные места
                bot.api.send_message( 
                  parse_mode: 'Markdown', 
                  chat_id: user.chat_id, 
                  text: View::free_place(crs)
                )
              end
            end
          end
        end
      end
    end
  end
end

Controller.run_bot

require_relative 'model'

class View
  def self.api_message
  	'
/add id - добавить курс
/remove id - отписаться от курса
/stop - отписаться от всех курсов
/check - проверить заполненность

/help - показать это сообщение'
  end
  def self.start_message
  	'Привет! Чтобы добавить курс, тебе надо узнать его id. 
Зайди на страницу курса (пример: https://lk.msu.ru/course/view?id=778)
и ты увидишь его id в адресной строке (в примере - 778).

Добавь курсы, за которыми ты хочешь следить:

  	'+api_message
  end
  def self.id_to_url(course_id)
  	"(#{Course::BASE_URL+course_id.to_s})"
  end
  def self.sub_message(hsh)
  	# если операция подписки была успешна
  	if hsh[:ok]
  	  res = ["Хорошо! Буду следить за курсом '#{hsh[:course].name}'"]
      # если на курсе уже есть места
      if hsh[:course].has_free?
        res << free_place(hsh[:course])
      else
        res << test_course(hsh[:course].course_id)
      end
    # если уже подписан
  	elsif hsh[:msg] == 'double subscription'
      "Ты уже подписан на курс '#{hsh[:course].name}'!"
    # если максимум подписок
    elsif hsh[:msg] == 'reached subscriptions limit'
      "Ты уже подписался на 5 курсов. Сначала отпишись от старых"
    # если не получилось создать курс
    else
  	  'Произошла ошибка! Проверь, открывается ли страничка курса 
'+id_to_url(hsh[:course_id])
  	end
  end
  def self.unsub_message(hsh)
    # если операция отписки была успешна
    if hsh[:ok]
      "Больше не слежу за курсом '#{hsh[:course].name}'"
    elsif hsh[:msg] == 'save failed'
      "Произошла ошибка на сервере. Извини :("
    elsif hsh[:msg] == 'user not found'
      "Сначала зарегестрируйся в /start"
    elsif hsh[:msg] == 'no such course'
      'Ты и так не подписан на этот курс'
    end
  end
  def self.bye_message(hsh)
    # если успешно отписали
    if hsh[:ok]
      'Прощай!'
    else
      'Что-то пошло не так, и я не смог тебя отписать'
    end
  end
  def self.bold(s)
    "*#{s}*"
  end
  def self.course_to_string(crs)
    "#{crs.name}\n"+
    "#{id_to_url(crs.course_id)}\n"+
    "Места: "+bold("#{crs.current}/#{crs.all}")
  end
  def self.test_course(course_id)
    course_to_string(Course.get(course_id))
  end
  def self.test_message(chat_id)
    # если у пользователя нет курсов
    if User.get(chat_id).courses.count == 0
      ['У тебя еще нет курсов :)']
    else
      # для всех курсов пользователя переводим каждый в строку
      User.get(chat_id).courses.map { |crs| course_to_string(crs) }
    end
  end
  def self.free_place(crs)
    "Эй! Появилось место на курсе '#{crs.name}!'\n"+
    id_to_url(crs.course_id)+"\n"+
    "Места: "+bold("#{crs.current}/#{crs.all}")
  end
end
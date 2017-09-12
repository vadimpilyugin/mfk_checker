require 'rubygems'
require 'data_mapper'
require 'open-uri'
require_relative 'printer'

class User
  MAX_COURSES = 5
  include DataMapper::Resource

  property :chat_id, Integer, :key => true
  property :username, String, :required => true

  has n, :courses, :through => Resource

  def self.create_user(chat_id, username)
    # если человек уже существует
    if User.count(chat_id:chat_id) != 0
      # выходим с успехом
      Printer::debug(
        who:"[create_user #{chat_id}, #{username}]",
        msg:"user already exist"
      )
      return {ok:true}
    end
    # человек не существует
    # если успешно создали чат
    if User.create(chat_id:chat_id, username:username).saved?
      Printer::debug(
        who:"[create_user #{chat_id}, #{username}]",
        msg:"created chat for user @#{username}"
      )
      return {ok:true}
    # если чат не создался
    else
      Printer::error(
        who:"[create_user #{chat_id}, #{username}]",
        msg:"failed to created chat for user @#{username}"
      )
      return {ok:false}
    end
  end

  def self.sub(chat_id, course_id)
    # если человек не существует
    if User.count(chat_id:chat_id) == 0
      # страшно ругаемся и выходим с ошибкой
      Printer::error(
        who:"sub #{chat_id}, #{course_id}", 
        msg:"no such user"
      )
      return {ok:false}
    end
    # человек существует
    # сохраняем запись о человеке
    user = User.get(chat_id)
    # ищем курс среди подписок
    course = user.courses.get(course_id)
    # если мы нашли курс среди подписок
    if !course.nil?
      # возвращаем ошибку двойной подписки
      Printer::error(
        who:"[sub #{chat_id}, #{course_id}]", 
        msg:"double subscription"
      )
      return {ok:false, msg:"double subscription"}
    end
    # курса нет среди подписок
    # если у человека больше MAX_COURSES курсов
    if user.courses.count >= MAX_COURSES
      # возвращаем отмену
      Printer::error(
        who:"[sub #{chat_id}, #{course_id}]", 
        msg:"reached subscriptions limit"
      )
      return {ok:false, msg:"reached subscriptions limit"}
    end
    # если курс в нашей базе не существует
    if Course.count(course_id:course_id) == 0
      # пытаемся создать его
      status = Course.create_course(course_id)
      # если курс был НЕуспешно создан
      if !status
        # печатаем ошибку и возвращаемся
        Printer::error(
          who:"sub #{chat_id}, #{course_id}", 
          msg:"failed to create course"
        )
        return {ok:false, msg:'failed to create course'}
      end
    end
    # курс был успешно создан
    # сохраняем запись о курсе
    course = Course.get(course_id)
    # увеличиваем счетчик подписок на курс
    course.update(
      times_subscribed: course.times_subscribed+1
    )
    # добавляем в список подписок
    user.courses << course
    # если сохранение было успешным
    if user.save
      Printer::debug(
        who:"[sub #{chat_id}, #{course_id}]", 
        msg:"@#{user.username} subscribed to '#{course.name}'"
      )
      # возвращаем успех
      return {ok:true}
    # если не сохранилось
    else
      Printer::error(
        who:"[sub #{chat_id}, #{course_id}]", 
        msg:"failed to save"
      )
      # возвращаем ошибку
      return {ok:false}
    end
  end

  def self.unsub(chat_id, course_id)
    # если человек не существует
    if User.count(chat_id:chat_id) == 0
      # возвращаем неудачу
      Printer::error(
        who:"[unsub #{chat_id},#{course_id}]", 
        msg:"user not found"
      )
      return {ok:false, msg:'user not found'}
    end
    # человек существует
    # сохраняем в переменную запись о человеке
    user = User.get(chat_id)
    # если у человека нет такого курса в подписках
    if user.courses.get(course_id).nil?
      Printer::error(
        who:"[unsub #{chat_id}, #{course_id}]", 
        msg:"@#{user.username} doesn't have this course"
      )
      # возвращаем ошибку
      return {ok:false, msg:"no such course"}
    end
    # курс есть в подписках
    # удаляем курс из его подписок
    res = user.courses.delete_if {|crs| crs.course_id == course_id}
    # FIXME(1): почему-то без проверки include изменения не сохраняются
    user.courses.include?(1)
    # если сохранилось
    if user.save
      Printer::debug(
        who:"[unsub #{chat_id}, #{course_id}]", 
        msg:"@#{user.username} unsubscribed from '#{Course.get(course_id).name}'"
      )
      # возвращаем успех
      return {ok:true}
    else
      Printer::error(
        who:"[unsub #{chat_id}, #{course_id}]", 
        msg:"@#{user.username} failed to unsubscribe from '#{Course.get(course_id).name}'"
      )
      # возвращаем ошибку
      return {ok:false, msg:"save failed"}
    end
  end
  
  def self.unsub_all(chat_id)
    # находим пользователя по id
    user = User.get(chat_id)
    # если пользователь не существует или его подписки пустые
    if user.nil? || user.courses.count == 0
      # возвращаем успех, т.к. такой пользователь ни на что не подписан
      Printer::debug(
        who:"[unsub_all #{chat_id}]", 
        msg:"no subscriptions found"
      )
      return {ok:true}
    # если пользователь существует
    else
      # удаляем все его подписки
      user.courses = []
      # если сохранение было успешным
      if user.save
        Printer::debug(
          who:"[unsub_all #{chat_id}]", 
          msg:"@#{user.username} unsubscribed from all subscriptions"
        )
        # возвращаем успех
        return {ok:true}
      # если не удалось сохранить
      else
        Printer::error(
          who:"[unsub_all #{chat_id}]", 
          msg:"failed to save changes"
        )
        # возвращаем неудачу
        return {ok:false}
      end
    end
  end
end

class Course
  BASE_URL='https://lk.msu.ru/course/view?id='

  include DataMapper::Resource

  property :course_id, Integer, :key => true
  property :name, String, :length => 256
  property :current, Integer, :required => true
  property :all, Integer, :required => true
  property :update_time, DateTime, :required => true
  property :has_changed, Boolean, :default => true
  property :times_subscribed, Integer, :default => 0

  has n, :users, :through => Resource

  # Синхронизируется ли курс с сервером?
  # если нет подписчиков, то синхронизировать нет смысла
  def is_synced?
    return users.count > 0
  end

  def has_free?
    current < all
  end

  def self.check_site_for_updates(id)
    begin
      time = Time.now
      data = URI.parse(BASE_URL+"#{id}").read
      places_rgx = /Записалось \/ всего мест<\/strong><br \/>\s+(?<current>\d+)\s+\/\s+(?<all>\d+)/
      name_rgx = /<title>(?<name>.*)<\/title>/
      if data =~ places_rgx
        ret_hsh = {current: $~['current'].to_i, all: $~['all'].to_i, time: time, ok: true}
        data =~ name_rgx
        ret_hsh[:name] = $~['name']
        return ret_hsh
      else
        Printer::error(
          who:"[check_site_for_updates #{id}]", 
          msg: "failed to parse server response"
        )
        return {ok:false, msg:"regex fail"}
      end
    rescue OpenURI::HTTPError => exc
      Printer::error(
        who:"[check_site_for_updates #{id}]", 
        msg: exc.message
      )
      return {ok: false, msg:'http fail'}
    end
  end

  def self.create_course(course_id)
  	# если такой курс уже существует
  	if Course.count(course_id:course_id) != 0
      Printer::debug(
        who:"[create_course #{course_id}]", 
        msg:"course already exists"
      )
      return {ok:true, course:Course.get(course_id)}
    end
    # курс не существует
	  # запросим у сервера информацию
	  rsp = check_site_for_updates(course_id)
    # если запрос был неуспешен
	  if !rsp[:ok]
      Printer::error(
        who:"[create_course #{course_id}]", 
        msg: "failed to get response from server"
      )
      return {ok: false}
    end
    # запрос был успешен
    # если создание было успешным
    if Course.create(
      course_id: course_id,
      name: rsp[:name],
      current: rsp[:current],
      all: rsp[:all],
      update_time: rsp[:time]
    ).saved?
      # возвращаем успех
      Printer::debug(
        who:"[create_course #{course_id}]", 
        msg: "created course '#{rsp[:name]}'"
      )
      return {ok: true, course:Course.get(course_id)}
    # если не сохранилось
    else
      # печатаем ошибку и возвращаемся
      Printer::error(
        who:"[create_course #{course_id}]", 
        msg: "failed to save course '#{rsp[:name]}'"
      )
      return {ok:false}
    end
  end
  # def self.delete_course(course_id)
    # бессмысленная вещь, я хочу знать, какие курсы были популярны
  # end
  def self.update_course(course_id)
    # если курс не существует
    if Course.count(course_id:course_id) == 0
      # печатаем ошибку и возвращаемся
      Printer::error(
        who:"[update_course #{course_id}]", 
        msg:"course does not exist"
      )
      return {ok:false}
    end
    # курс существует
    # сохраним запись о курсе
    course = Course.get(course_id)
    # запросим у сервера информацию
    rsp = check_site_for_updates(course_id)
    # если сервер ответил некорректно или не ответил
    if !rsp[:ok]
      Printer::error(
        who:"[update_course #{course_id}]", 
        msg:"server response was bad"
      )
      return {ok:false}
    end
    # сервер ответил корректно
    # если заполненность изменилась
    if rsp[:current] != course.current
      # обновляем время, заполненность и has_changed
      status = course.update(
        update_time: rsp[:time],
        current: rsp[:current],
        all: rsp[:all],
        has_changed: true
      )
      # если сохранение было успешным
      if status
        # возвращаем успех
        Printer::debug(
          who:"[update_course #{course_id}]", 
          msg:"update for '#{course.name}': #{course.current}/#{course.all}, has_changed = #{course.has_changed}"
        )
        return {ok:true}
      # если не сохранилось
      else
        # печатаем сообщение и возвращаем ошибку
        Printer::error(
          who:"[update_course #{course_id}]", 
          msg:"update for '#{course.name}': failed to save changes"
        )
        return {ok:false}
      end
    # если заполненность не поменялась
    else
      # обновляем время и has_changed
      status = course.update(
        update_time: rsp[:time],
        has_changed: false
      )
      # если сохранение было успешным
      if status
        # возвращаем успех
        Printer::debug(
          who:"[update_course #{course_id}]", 
          msg:"update for '#{course.name}': #{course.current}/#{course.all}, has_changed = #{course.has_changed}"
        )
        return {ok:true}
      # если не сохранилось
      else
        # печатаем сообщение и возвращаем ошибку
        Printer::error(
          who:"[update_course #{course_id}]", 
          msg:"update for '#{course.name}': failed to save changes"
        )
        return {ok:false}
      end
    end
  end
end

DataMapper.finalize
DataMapper.setup :default, "mysql://@localhost/"
DataMapper.auto_upgrade!
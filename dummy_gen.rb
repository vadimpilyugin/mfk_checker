require_relative 'model'

SECONDS_TO_WAIT = 60

def update_courses
  while true
    courses_to_update = DataMapper.repository.adapter.select(
      'select courses.course_id as id from courses 
      where update_time < \''+(Time.now-SECONDS_TO_WAIT).strftime('%Y-%m-%d %H:%M:%S')+'\'  and
              (select count(*) from course_users 
              where course_course_id = courses.course_id) > 0 order by (select count(*) from course_users 
              where course_course_id = courses.course_id) desc')
    Printer::debug(
      who:"[update_courses]",
      msg:"#{courses_to_update.size} courses to update"
    )
    if courses_to_update.empty?
      sleep 1
    else
      courses_to_update.each {|course_id| Course.update_course(course_id)}
    end
  end
end

def update_users
  while true
  	nmb = rand 1..100
  	user = User.all.sample
  	course = Course.all.sample
  	user_course = user.courses.sample
  	case nmb
  	  when 1...30, 41..60
        # sub 
        User.sub(user.chat_id, course.course_id)
      when 30...35
      	# unsub
      	User.unsub(user.chat_id, user_course.course_id) if user_course
      when 35...40
      	# unsub all
      	User.unsub_all(user.chat_id)
      when 40..60
      	# new user
      	User.create_user rand(1..100000000), ('a'..'z').to_a.shuffle[0,12].join
      # when 60...100
      	# test
      	# Course.update_course(course.course_id)
    end
    sleep 0.1
  end
end

['vadimpilyugin', 'dmitry', 'olga', 'andrew'].each do |name| 
  if User.count(username:name) == 0
    User.create(chat_id:rand(1..1000), username:name)
  end
end

# [{name:'Brain', id:1}, {name:'English', id:2}, {name:'Startups', id:3}].each do |crs|
#   if Course.count(name:crs[:name]) == 0
#   	Course.create(
#   	  course_id: crs[:id],
#   	  name: crs[:name],
#   	  current: rand(1..100),
#   	  all: 100,
#   	  update_time: Time.now
#   	)
#   end
# end

(550..700).each {|course_id| Course.create_course(course_id)}
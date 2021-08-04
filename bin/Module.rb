#!/usr/bin/env ruby
#
# ::CModule for parsing GPTE instruction modules
# Course::CModule::Topic::Slide
# Course::CModule::Topic::Lab
# Course::CModule::Topic::Assessment

# Courses:
#   CModules:
#     Topics:
#       Slides
#     Labs:
#       Topics

require 'logger'
require 'git'
require 'octokit'
require 'asciidoctor'
require 'erb'
require 'logger'

class GitHubOrg
  def initialize(org='redhat-gpe',repo_base='/tmp/course_repos')
    @org       = org
    @client    = Octokit::Client.new(:login => ENV["git_username"], :password => ENV["git_password"])
    @repo_base = repo_base
    @repos     = Hash.new
    @courses   = Array.new(0)
    MyLog.log.debug "org: #{org}: #{repo_base}"
    ocp_courses
    load_courses
  end

  # returns list of courses
  def courses
    courses = @client.org_repos('redhat-gpe', {:type => 'all', :sort => 'pushed'})
    courses.each { |c| MyLog.log.info c.name }
  end

  def ocp_courses
    c_repos = @client.org_repos('redhat-gpe', {:type => 'all', :sort => 'pushed'})
    MyLog.log.debug "ocp_courses"
    c_repos.each do |c|
      if c.name.start_with?('ocp')
        @repos[c.name] = c.html_url
        MyLog.log.debug "#{c.name} #{@repos[c.name]}"
      end
    end
    MyLog.log.debug @repos
  end

  def clone_repo(repo_name)
    MyLog.log.debug "clone repo: #{repo_name}"
    repo_path = @repo_base + '/' + repo_name
    MyLog.log.debug "clone path: #{repo_path}"
    if ( g = Git.open( repo_path ) )
      MyLog.log.debug "Pull"
      g.pull
    else
      MyLog.log.debug "Clone"
      Git.clone(repo_name, :path => repo_path)
    end
    return repo_path
  end

  def refresh_repo(repo_name)
    repo_base_name = "#{@repo_base}/#{repo_name}"
    MyLog.log.debug "refresh #{@repos[repo_name]} basename: #{repo_base_name}"
    g = Git.clone(@repos[repo_name], repo_base_name)
    # if g failed, then clone
    return repo_base_name
  end

  def load_courses
    @repos.each_key do |r_name|
      MyLog.log.debug "rname #{r_name}"
      # refresh the repo
      r_path = clone_repo(r_name)
      MyLog.log.debug "repo path: #{r_path}"
      # load the course
      MyLog.log.debug "course new"
      @courses << Course.new(r_name,r_path)
    end
  end
end

class ReadMe

  attr_reader :course

  def initialize
    # takes and adoc and parses into sections
    @readme_overview = Array.new
    @readme_modules = Array.new
    @readme_skills = nil
  end

  def load(readme_asciidoc)
    readme_asciidoc.find_by(context: :section).each do |sect|
      MyLog.log.debug "sect.title"
      if sect.level == 1
        if sect.title == 'Overview'
          @readme_overview = sect
        end
        if sect.title == 'Modules Review'
          @readme_modules = sect
        end
        if sect.title == 'Version'
          @readme_version = sect
        end
      end
    end
  end

  def render
    @template = File.read('./README.adoc.erb')
    puts ERB.new(@template).result( binding )
  end

  def construct(course)
    @course = course
    render
  end

end

class Course
  def initialize(name, path)
    @name    = name
    @path    = path
    @modules = Array.new
    load
    #load_readme
  end

  def load_readme
    readme_path = @path + '/README.adoc'
    if FileTest.readable?(readme_path)
      @readme_asciidoc = Asciidoctor.load_file readme_path, safe: :safe, parse: :false
    else
      raise "cant read #{readme_path}"
    end
    @readme = ReadMe.new()
    @readme.load(@readme_asciidoc)
  end

  def render_readme
    # if there's already a readme object, render it
    @readme = ReadMe.new()
    # If there's not already a readme object, construct and then render
    @readme.construct(self)
  end

  def load
    # read URL or path to get all CModule names
    # load by URL

    # load by path
    modules_path = @path + "/modules/"
    # it should have a modules directory
    if FileTest.directory?(modules_path)
      # /*/ == find depth 1
      # load all modules
      Dir[modules_path+"/*/"].sort.each { |p| @modules << CModule.new("",p) }
      @course_title = @modules[0].course_title
    else
      raise "no dir #{modules_path}"
    end
  end

  def title
    @course_title
  end

  def modules
    @modules
  end
end

class CModule

  attr_reader :topics, :labs, :course_title

  def initialize(name, path)
    @name = name
    @path  = path
    @labs = Array.new
    @slides = Array.new
    @topics = Hash.new(0)
    @topics_slides = Hash.new {|h,k| h[k] = Array.new }
    @course_title  = String.new
    @module_title  = String.new
    load
    parse_titles
    parse_slides
    parse_labs
    parse_topics
    return @course_title
  end

  def topic_names
    @topics.keys[1..]
  end

  def slides_by_topic
    @topics_slides.each
  end

  def title
    @module_title
  end

  def course_title
    @course_title
  end

  def slides
    @slides.each
  end

  def load
    MyLog.log.debug "reads in all slides and labs by path or URL of the module"
    # just files for now
    # slides
    # use find to get the _Slides and *_Lab.adoc paths of module
    slides_path = @path + "/_Slides.adoc"
    MyLog.log.debug "slides_path #{slides_path}"
    if FileTest.readable?(slides_path)
      @slides_asciidoc = Asciidoctor.load_file slides_path, safe: :safe, parse: :false, :attributes => 'revealjs_slideshow'
    else
      raise "cant read #{slides_path}"
    end

    #labs
    # for each lab name, use the solutions, else use the lab
    lab_paths = Hash.new("0")
    path = @path + "/[0-9][0-9]*_Lab.adoc"
    Dir.glob(path).each do |l|
      # get names
      lab_name = File.basename(l)
      lab_name.delete_suffix! "_Solution_Lab.adoc"
      lab_name.delete_suffix! "_Lab.adoc"
      # Hash[lab_name: :lab_path]
      lab_paths[lab_name] = l unless lab_paths[lab_name].match?('_Solution_Lab.adoc')
    end

    # process labs asciidoc
    # lab sections are topics
    @labs_asciidoc = Array.new
    lab_paths.each do |lab_name,lab_path|
      @labs_asciidoc << Asciidoctor.load_file(lab_path, safe: :safe, parse: :false)
    end

  end

  def parse_titles
    return unless @slides_asciidoc.find_by(context: :section, id: 'cover')[0]
    title_block = @slides_asciidoc.find_by(context: :section, id: 'cover')[0].blocks
    @course_title = title_block[0].content
    @module_title = title_block[1].content

    #@slides_asciidoc.find_by(context: :section, id: 'cover') do |c|
    #  @course_title c.blocks[0].content
    #end
  end

  def parse_slides
    # create many slides objects from one long _Slides.adoc file
    # _Slides.adoc sections are topics
    @slides_asciidoc.find_by(context: :section).each do |sect|
      @slides << Slide.new(sect.id,sect)
    end
    #@slides.each{|t| MyLog.log.debug "t.topic"}
  end

  def parse_labs
    # all labs asciidocs -> parse into labs objects
    @labs_asciidoc.each do |l|
      @labs << Lab.new(l.title, l)
    end
  end

  def parse_topics
    # a hash of topics and slide count
    @slides.each do |slide|
      MyLog.log.debug "Slide ID: #{slide.id}"
      MyLog.log.debug "Slide Topic: #{slide.topic}"
      @topics[slide.topic] += 1
      @topics_slides[slide.topic] << slide
      @topics_slides[slide.topic].each { |p| MyLog.log.debug "all slides for topic #{p.topic} #{p.id}" }
    end

  end

  def parse_topics_omitted
    @slides_asciidoc.find_by(context: :section).each do |sect|
      if sect.id == "_module_topics"
        module_topics = sect.content
        sect.find_by(context: :ulist).each do |list|
          list.items.each do |item|
            topics << %("#{item.text}", "#{module_name.slice(3..-1)}", "#{course_name}")
          end
        end
      end
    end
  end
end

class Slide
  attr_reader :topic, :content, :id

  def initialize(id,sect)
    @id = id
    @sect = sect
  end

  def topic
    return @sect.title
  end

  def content
    @sect.content
  end
end

class Lab

  attr_reader :scenario, :title, :topics

  def initialize(title,doc)
    @title = title
    @doc  = doc

    # populate topics
    @topics = Array.new
    doc.find_by( context: :section ) {|s| s.level == 1 }.each_with_index do |sect,i|
      @topics << sect.title
      if i == 0
        # the 0th is the scenario
        @scenario = sect.blocks[0].content
      end
    end
  end

#   def topics
#     @topics
#   end

  def prep_blocks
    MyLog.log.debug "prep_block"
  end

  def grade_blocks
    MyLog.log.debug "grade_block"
  end

  def solve_blocks
    MyLog.log.debug "solve_block"
  end
end

class MyLog
  def self.log
    if @logger.nil?
      @logger = Logger.new STDOUT
      #@logger = Logger.new "log.log"
      @logger.level = Logger::DEBUG
      @logger.datetime_format = '%Y-%m-%d %H:%M:%S '
    end
    @logger
  end
end

#course1 = Course.new('ocp4_foundaitons','/Users/jmaltin/newgoliath/ocp4_advanced_deployment')
#course1.render_readme

##module1 = Module.new('intro', '/Users/jmaltin/newgoliath/ocp4_foundations/modules/03_OpenShift_User_Experience/')

#lab1 = Lab.new('test', '/Users/jmaltin/newgoliath/ocp4_foundations/modules/03_OpenShift_User_Experience/03_01_Demonstrate_OpenShift_Resources_Lab.adoc')
#puts lab1.topics

github = GitHubOrg.new()

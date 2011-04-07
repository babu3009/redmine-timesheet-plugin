class TimesheetsController < InheritedResources::Base
  unloadable

  respond_to :html

  before_filter :get_list_size
  before_filter :get_precision
  before_filter :get_activities
  before_filter :run_report_for_show, :only => :show

  helper :timesheet
  helper :sort
  include SortHelper
  helper :issues
  include ApplicationHelper
  helper :timelog

  SessionKey = 'timesheet_filter'

  verify :method => :delete, :only => :reset, :render => {:nothing => true, :status => :method_not_allowed }

  def index
    load_filters_from_session
    unless @timesheet
      @timesheet ||= Timesheet.new
    end
    @timesheet.allowed_projects = allowed_projects

    if @timesheet.allowed_projects.empty?
      render :action => 'no_projects'
      return
    end
  end

  def context_menu
    @time_entries = TimeEntry.find(:all, :conditions => ['id IN (?)', params[:ids]])
    render :layout => false
  end

  def reset
    clear_filters_from_session
    redirect_to :action => 'index'
  end

  private
  def get_list_size
    @list_size = Setting.plugin_timesheet_plugin['list_size'].to_i
  end

  def get_precision
    precision = Setting.plugin_timesheet_plugin['precision']
    
    if precision.blank?
      # Set precision to a high number
      @precision = 10
    else
      @precision = precision.to_i
    end
  end

  def get_activities
    @activities = TimeEntryActivity.all
  end
  
  def allowed_projects
    if User.current.admin?
      Project.timesheet_order_by_name
    elsif Setting.plugin_timesheet_plugin['project_status'] == 'all'
      Project.timesheet_order_by_name.timesheet_with_membership(User.current)
    else
      Project.timesheet_order_by_name.all(:conditions => Project.visible_by(User.current))
    end
  end

  def clear_filters_from_session
    session[SessionKey] = nil
  end

  def load_filters_from_session
    if session[SessionKey]
      @timesheet = Timesheet.new(session[SessionKey])
      # Default to free period
      @timesheet.period_type = Timesheet::ValidPeriodType[:free_period]
    end

    if session[SessionKey] && session[SessionKey]['projects']
      @timesheet.projects = allowed_projects.find_all { |project| 
        session[SessionKey]['projects'].include?(project.id.to_s)
      }
    end
  end

  def save_filters_to_session(timesheet)
    if params[:timesheet]
      session[SessionKey] = params[:timesheet]
    end

    if timesheet
      session[SessionKey]['date_from'] = timesheet.date_from
      session[SessionKey]['date_to'] = timesheet.date_to
    end
  end

  # TODO: extracted out of the action
  def run_report_for_show
    @timesheet = resource
    @timesheet.allowed_projects = allowed_projects
    
    if @timesheet.allowed_projects.empty?
      render :action => 'no_projects'
      return
    end

    @timesheet.projects = @timesheet.allowed_projects

    call_hook(:plugin_timesheet_controller_report_pre_fetch_time_entries, { :timesheet => @timesheet, :params => params })

    save_filters_to_session(@timesheet)

    @timesheet.fetch_time_entries

    # Sums
    @total = { }
    unless @timesheet.sort == :issue
      @timesheet.time_entries.each do |project,logs|
        @total[project] = 0
        if logs[:logs]
          logs[:logs].each do |log|
            @total[project] += log.hours
          end
        end
      end
    else
      @timesheet.time_entries.each do |project, project_data|
        @total[project] = 0
        if project_data[:issues]
          project_data[:issues].each do |issue, issue_data|
            @total[project] += issue_data.collect(&:hours).sum
          end
        end
      end
    end
    
    @grand_total = @total.collect{|k,v| v}.inject{|sum,n| sum + n}
  end
  
end
